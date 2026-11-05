import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Harness h;
  tearDown(() => h.close());

  for (final status in [400, 404, 413, 422]) {
    test(
      'upstream $status becomes 400 upstream_rejected with a JSON message',
      () async {
        h = Harness(
          upstream: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'error': {
                  'message': 'Context length exceeded',
                  'internal': 'hidden diagnostics',
                },
                'request': 'hidden request',
              }),
              status,
            ),
          ),
        );
        await h.provider();
        final response = await h.jsonCall(
          'POST',
          'v1/chat/completions',
          asAdmin: true,
          status: 400,
          data: {'model': 'test/model'},
        );
        expect(response, {
          'error': {
            'code': 'upstream_rejected',
            'message': 'Context length exceeded',
          },
        });
      },
    );
  }

  for (final entry in [
    (
      {
        'error': {'message': 'nested'},
        'message': 'top level',
      },
      'nested',
    ),
    (
      {
        'error': {'message': 123},
        'message': 'top level',
      },
      'top level',
    ),
    ({'error': 'string error'}, 'string error'),
    (
      {
        'error': 123,
        'message': ['invalid'],
      },
      'Upstream rejected the request.',
    ),
  ]) {
    test(
      'upstream rejection extracts only the supported message: ${entry.$2}',
      () async {
        h = Harness(
          upstream: MockClient(
            (_) async => http.Response(jsonEncode(entry.$1), 400),
          ),
        );
        await h.provider();
        final result = await h.jsonCall(
          'POST',
          'v1/chat/completions',
          asAdmin: true,
          status: 400,
          data: {'model': 'test/model'},
        );
        expect((result['error'] as Map)['message'], entry.$2);
      },
    );
  }

  for (final payload in [
    '<html>private diagnostics</html>',
    'not JSON',
    '"private diagnostics"',
    '{broken',
  ]) {
    test(
      'non-object or invalid JSON rejection bodies stay private: $payload',
      () async {
        h = Harness(
          upstream: MockClient((_) async => http.Response(payload, 400)),
        );
        await h.provider();
        final result = await h.jsonCall(
          'POST',
          'v1/chat/completions',
          asAdmin: true,
          status: 400,
          data: {'model': 'test/model'},
        );
        expect(
          (result['error'] as Map)['message'],
          'Upstream rejected the request.',
        );
      },
    );
  }

  for (final status in [401, 403]) {
    test(
      'upstream $status becomes 502 upstream_auth without diagnostics',
      () async {
        h = Harness(
          upstream: MockClient(
            (_) async => http.Response(
              '{"error":{"message":"private diagnostics"}}',
              status,
            ),
          ),
        );
        await h.provider();
        final result = await h.jsonCall(
          'POST',
          'v1/chat/completions',
          asAdmin: true,
          status: 502,
          data: {'model': 'test/model'},
        );
        expect((result['error'] as Map)['code'], 'upstream_auth');
        expect(jsonEncode(result), isNot(contains('private diagnostics')));
      },
    );
  }

  for (final retryAfter in [null, '120', 'Wed, 21 Oct 2037 07:28:00 GMT']) {
    test('429 passes Retry-After through: $retryAfter', () async {
      h = Harness(
        upstream: MockClient(
          (_) async => http.Response(
            'private diagnostics',
            429,
            headers: {'retry-after': ?retryAfter},
          ),
        ),
      );
      await h.provider();
      final response = await h.call(
        'POST',
        'v1/chat/completions',
        asAdmin: true,
        data: {'model': 'test/model'},
      );
      expect(response.statusCode, 429);
      expect(response.headers['retry-after'], retryAfter);
      final result = await readJson(response);
      expect((result['error'] as Map)['code'], 'upstream_rate_limited');
      expect(jsonEncode(result), isNot(contains('private diagnostics')));
    });
  }

  for (final status in [302, 408, 500, 503]) {
    test(
      'upstream $status becomes 502 upstream_error naming its status',
      () async {
        h = Harness(
          upstream: MockClient(
            (_) async => http.Response('private diagnostics', status),
          ),
        );
        await h.provider();
        final result = await h.jsonCall(
          'POST',
          'v1/chat/completions',
          asAdmin: true,
          status: 502,
          data: {'model': 'test/model'},
        );
        expect((result['error'] as Map)['code'], 'upstream_error');
        expect((result['error'] as Map)['message'], contains('$status'));
        expect(jsonEncode(result), isNot(contains('private diagnostics')));
      },
    );
  }

  test('connection failures remain 502 upstream_unreachable', () async {
    h = Harness(
      upstream: MockClient(
        (_) async => throw const SocketException('private diagnostics'),
      ),
    );
    await h.provider(changes: {'models': []});
    await h.expectError(
      'POST',
      'v1/chat/completions',
      502,
      'upstream_unreachable',
      asAdmin: true,
      data: {'model': 'test/model'},
    );
  });

  test(
    'messages redact raw and encoded provider keys and token-shaped strings before truncation',
    () async {
      const key = 'provider/secret+key =?';
      final sensitive = [
        key,
        Uri.encodeComponent(key),
        Uri.encodeComponent(key).toLowerCase(),
        Uri.encodeQueryComponent(key),
        'sk-proj_123-abc',
        'tako_token-123_abc',
      ];
      var message = 'Credentials: ${sensitive.join(' | ')}';
      h = Harness(
        upstream: MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer $key');
          return http.Response(
            jsonEncode({
              'error': {'message': message},
            }),
            400,
          );
        }),
      );
      await h.provider(changes: {'apiKey': key});
      var result = await h.jsonCall(
        'POST',
        'v1/chat/completions',
        asAdmin: true,
        status: 400,
        data: {'model': 'test/model'},
      );
      expect(
        (result['error'] as Map)['message'],
        'Credentials: ${List.filled(sensitive.length, '[REDACTED]').join(' | ')}',
      );
      message = '${'x' * 495}$key';
      result = await h.jsonCall(
        'POST',
        'v1/chat/completions',
        asAdmin: true,
        status: 400,
        data: {'model': 'test/model'},
      );
      final truncated = (result['error'] as Map)['message'] as String;
      expect(truncated.length, 500);
      expect(truncated, '${'x' * 495}[REDA');
    },
  );

  for (final chunkSize in [1024, 128 * 1024]) {
    test(
      'error body reading stops and cancels at 64 KiB ($chunkSize-byte chunks)',
      () async {
        var chunks = 0;
        var cancelled = false;
        Stream<List<int>> body() async* {
          try {
            while (true) {
              chunks++;
              yield List.filled(chunkSize, 120);
            }
          } finally {
            cancelled = true;
          }
        }

        h = Harness(
          upstream: MockClient.streaming((request, stream) async {
            await stream.drain<void>();
            return http.StreamedResponse(body(), 400);
          }),
        );
        await h.provider();
        final result = await h.jsonCall(
          'POST',
          'v1/chat/completions',
          asAdmin: true,
          status: 400,
          data: {'model': 'test/model'},
        );
        expect(
          (result['error'] as Map)['message'],
          'Upstream rejected the request.',
        );
        expect(chunks, chunkSize == 1024 ? 64 : 1);
        expect(cancelled, true);
      },
    );
  }

  test(
    'a failed error body stream preserves the upstream status mapping',
    () async {
      h = Harness(
        upstream: MockClient.streaming((request, stream) async {
          await stream.drain<void>();
          return http.StreamedResponse(
            Stream.error(const SocketException('private diagnostics')),
            413,
          );
        }),
      );
      await h.provider();
      await h.expectError(
        'POST',
        'v1/chat/completions',
        400,
        'upstream_rejected',
        asAdmin: true,
        data: {'model': 'test/model'},
      );
    },
  );

  test(
    'model discovery cancels upstream error bodies without draining them',
    () async {
      var cancelled = false;
      h = Harness(
        upstream: MockClient.streaming((request, stream) async {
          await stream.drain<void>();
          final body = StreamController<List<int>>(
            onCancel: () {
              cancelled = true;
            },
          );
          return http.StreamedResponse(body.stream, 503);
        }),
      );
      await h.provider(changes: {'models': []});
      expect(
        (await h.jsonCall('GET', 'v1/models', asAdmin: true))['data'],
        isEmpty,
      );
      expect(cancelled, true);
    },
  );
}
