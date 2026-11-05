import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tako_den/src/network_guard.dart';
import 'package:tako_den/tako_den.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Harness h;
  tearDown(() => h.close());

  test(
    'shared access lists and model allowlists are enforced, own models use me/',
    () async {
      h = Harness();
      final ana = h.addUser('ana');
      final ben = h.addUser('ben');
      final token = h.token(ana);
      final shared = await h.provider(
        changes: {
          'access': {
            'allUsers': false,
            'userIds': [ben.id],
          },
        },
      );
      expect(
        (await h.jsonCall('GET', 'v1/models', token: token))['data'],
        isEmpty,
      );
      await h.expectError(
        'POST',
        'v1/chat/completions',
        404,
        'model_not_found',
        token: token,
        data: {'model': 'test/model'},
      );
      await h.jsonCall(
        'PATCH',
        'v1/admin/providers/${shared['id']}',
        asAdmin: true,
        data: {
          'access': {
            'allUsers': false,
            'userIds': [ana.id],
          },
        },
      );
      final own = await h.provider(token: token);
      final models =
          (await h.jsonCall('GET', 'v1/models', token: token))['data'] as List;
      expect(models.map((m) => (m as Map)['id']), [
        'test/model',
        'test/org/model',
        'me/test/model',
        'me/test/org/model',
      ]);
      await h.jsonCall(
        'POST',
        'v1/chat/completions',
        token: token,
        data: {'model': 'me/test/org/model'},
      );
      expect((jsonDecode(h.requests.last.body) as Map)['model'], 'org/model');
      expect(
        h.requests.last.headers['authorization'],
        'Bearer provider-secret',
      );
      await h.expectError(
        'POST',
        'v1/chat/completions',
        404,
        'model_not_found',
        token: token,
        data: {'model': 'me/test/hidden'},
      );
      await h.jsonCall(
        'PATCH',
        'v1/admin/users/${ana.id}',
        asAdmin: true,
        data: {
          'permissions': {'useSharedProviders': false, 'ownProviders': false},
        },
      );
      expect(
        (await h.jsonCall('GET', 'v1/models', token: token))['data'],
        isEmpty,
      );
      await h.expectError(
        'GET',
        'v1/me/providers',
        403,
        'forbidden',
        token: token,
      );
      await h.expectError(
        'POST',
        'v1/chat/completions',
        404,
        'model_not_found',
        token: token,
        data: {'model': 'me/test/model'},
      );
      await h.expectError(
        'PATCH',
        'v1/me/providers/${own['id']}',
        404,
        'not_found',
        token: h.token(ben),
        data: {'name': 'stolen'},
      );
    },
  );

  test(
    'quota is shared-only, resets by UTC day, and admins are unlimited',
    () async {
      h = Harness();
      final user = h.addUser('ana');
      final token = h.token(user);
      await h.provider();
      await h.provider(token: token);
      await h.jsonCall(
        'PATCH',
        'v1/admin/settings',
        asAdmin: true,
        data: {
          'defaultPermissions': {'dailyTokenLimit': 10},
        },
      );
      await h.jsonCall(
        'POST',
        'v1/chat/completions',
        token: token,
        data: {'model': 'test/model'},
      );
      await h.expectError(
        'POST',
        'v1/chat/completions',
        429,
        'quota_exceeded',
        token: token,
        data: {'model': 'test/model'},
      );
      await h.jsonCall(
        'POST',
        'v1/chat/completions',
        token: token,
        data: {'model': 'me/test/model'},
      );
      final usage = await h.jsonCall('GET', 'v1/usage', token: token);
      expect(usage['today'], {'sharedTokens': 10, 'limit': 10});
      final all =
          (await h.jsonCall(
                'GET',
                'v1/admin/usage?days=1',
                asAdmin: true,
              ))['usage']
              as List;
      expect(all.map((v) => (v as Map)['shared']), containsAll([true, false]));
      await h.jsonCall(
        'POST',
        'v1/chat/completions',
        asAdmin: true,
        data: {'model': 'test/model'},
      );
      h.store.db.execute("UPDATE usage SET day = '2000-01-01'");
      await h.jsonCall(
        'POST',
        'v1/chat/completions',
        token: token,
        data: {'model': 'test/model'},
      );
      expect(
        (await h.jsonCall(
              'GET',
              'v1/admin/usage?days=1',
              asAdmin: true,
            ))['usage']
            as List,
        hasLength(1),
      );
    },
  );

  test(
    'provider secrets are encrypted and write-only; omitted keeps and empty clears',
    () async {
      h = Harness();
      final provider = await h.provider();
      final id = provider['id'];
      expect(provider['hasApiKey'], true);
      expect(jsonEncode(provider), isNot(contains('provider-secret')));
      expect(
        h.store.db.select('SELECT * FROM providers').toString(),
        isNot(contains('provider-secret')),
      );
      final patched = await h.jsonCall(
        'PATCH',
        'v1/admin/providers/$id',
        asAdmin: true,
        data: {'displayName': 'Renamed'},
      );
      expect(patched['hasApiKey'], true);
      final tested = await h.jsonCall(
        'POST',
        'v1/admin/providers/$id/test',
        asAdmin: true,
      );
      expect(tested, {
        'ok': true,
        'models': ['model', 'org/model'],
      });
      expect(
        h.requests.last.headers['authorization'],
        'Bearer provider-secret',
      );
      final cleared = await h.jsonCall(
        'PATCH',
        'v1/admin/providers/$id',
        asAdmin: true,
        data: {'apiKey': ''},
      );
      expect(cleared['hasApiKey'], false);
      await h.expectError(
        'POST',
        'v1/admin/providers',
        409,
        'name_taken',
        asAdmin: true,
        data: {'name': 'test', 'baseUrl': 'https://test.test/v1'},
      );
      await h.jsonCall('DELETE', 'v1/admin/providers/$id', asAdmin: true);
      expect(
        (await h.jsonCall(
          'GET',
          'v1/admin/providers',
          asAdmin: true,
        ))['providers'],
        isEmpty,
      );
    },
  );

  test(
    'config providers are read-only, unavailable upstreams skipped, tests redact errors',
    () async {
      h = Harness(
        config: const DenConfig(
          upstreams: [
            Upstream(name: 'fixed', baseUrl: 'https://fixed.test/v1'),
          ],
        ),
        upstream: MockClient(
          (_) async => http.Response('secret-should-not-leak', 401),
        ),
      );
      final providers =
          (await h.jsonCall(
                'GET',
                'v1/admin/providers',
                asAdmin: true,
              ))['providers']
              as List;
      final id = (providers.single as Map)['id'];
      expect((providers.single as Map)['source'], 'config');
      await h.expectError(
        'PATCH',
        'v1/admin/providers/$id',
        400,
        'read_only',
        asAdmin: true,
        data: {},
      );
      await h.expectError(
        'DELETE',
        'v1/admin/providers/$id',
        400,
        'read_only',
        asAdmin: true,
      );
      expect(
        (await h.jsonCall('GET', 'v1/models', asAdmin: true))['data'],
        isEmpty,
      );
      final tested = await h.jsonCall(
        'POST',
        'v1/admin/providers/$id/test',
        asAdmin: true,
      );
      expect(tested['ok'], false);
      expect(jsonEncode(tested), isNot(contains('secret-should-not-leak')));
    },
  );

  test(
    'model discovery is cached and invalidated; chat forwards unlisted models',
    () async {
      h = Harness();
      final provider = await h.provider(changes: {'models': []});
      await h.jsonCall('GET', 'v1/models', asAdmin: true);
      await h.jsonCall('GET', 'v1/models', asAdmin: true);
      expect(h.requests, hasLength(1));
      await h.jsonCall(
        'POST',
        'v1/chat/completions',
        asAdmin: true,
        data: {'model': 'test/not-listed'},
      );
      expect(h.requests, hasLength(2));
      expect(h.requests.last.url.path, '/v1/chat/completions');
      expect((jsonDecode(h.requests.last.body) as Map)['model'], 'not-listed');
      await h.jsonCall(
        'PATCH',
        'v1/admin/providers/${provider['id']}',
        asAdmin: true,
        data: {'displayName': 'Updated'},
      );
      await h.jsonCall('GET', 'v1/models', asAdmin: true);
      expect(h.requests, hasLength(3));
    },
  );

  test(
    'chat checks allowlists locally and never requests upstream models',
    () async {
      final forwarded = <http.Request>[];
      h = Harness(
        upstream: MockClient((request) async {
          forwarded.add(request);
          if (request.url.path.endsWith('/models')) {
            return http.Response('Models unavailable', 404);
          }
          return http.Response('{"choices":[]}', 200);
        }),
      );
      final provider = await h.provider(changes: {'models': []});
      await h.jsonCall(
        'POST',
        'v1/chat/completions',
        asAdmin: true,
        data: {'model': 'test/arbitrary/model'},
      );
      expect(forwarded.single.url.path, '/v1/chat/completions');
      expect(
        (jsonDecode(forwarded.single.body) as Map)['model'],
        'arbitrary/model',
      );
      await h.jsonCall(
        'PATCH',
        'v1/admin/providers/${provider['id']}',
        asAdmin: true,
        data: {
          'models': ['allowed'],
        },
      );
      await h.expectError(
        'POST',
        'v1/chat/completions',
        404,
        'model_not_found',
        asAdmin: true,
        data: {'model': 'test/arbitrary/model'},
      );
      expect(forwarded, hasLength(1));
      await h.jsonCall(
        'POST',
        'v1/chat/completions',
        asAdmin: true,
        data: {'model': 'test/allowed'},
      );
      expect(forwarded, hasLength(2));
      expect(
        forwarded.every(
          (r) => r.method == 'POST' && r.url.path.endsWith('/chat/completions'),
        ),
        true,
      );
    },
  );

  test(
    'unlimited user override exceeds the default quota and null inherits again',
    () async {
      h = Harness();
      final user = h.addUser('ana');
      final token = h.token(user);
      await h.provider();
      await h.jsonCall(
        'PATCH',
        'v1/admin/settings',
        asAdmin: true,
        data: {
          'defaultPermissions': {'dailyTokenLimit': 1},
        },
      );
      final patched = await h.jsonCall(
        'PATCH',
        'v1/admin/users/${user.id}',
        asAdmin: true,
        data: {
          'permissions': {'dailyTokenLimit': -1},
        },
      );
      expect((patched['permissions'] as Map)['dailyTokenLimit'], -1);
      expect((patched['effectivePermissions'] as Map)['dailyTokenLimit'], null);
      for (var i = 0; i < 3; i++) {
        await h.jsonCall(
          'POST',
          'v1/chat/completions',
          token: token,
          data: {'model': 'test/model'},
        );
      }
      expect((await h.jsonCall('GET', 'v1/usage', token: token))['today'], {
        'sharedTokens': 30,
        'limit': null,
      });
      final me =
          (await h.jsonCall('GET', 'v1/me', token: token))['user'] as Map;
      expect((me['permissions'] as Map)['dailyTokenLimit'], null);
      await h.jsonCall(
        'PATCH',
        'v1/admin/users/${user.id}',
        asAdmin: true,
        data: {
          'permissions': {'dailyTokenLimit': null},
        },
      );
      await h.expectError(
        'POST',
        'v1/chat/completions',
        429,
        'quota_exceeded',
        token: token,
        data: {'model': 'test/model'},
      );
      expect((await h.jsonCall('GET', 'v1/usage', token: token))['today'], {
        'sharedTokens': 30,
        'limit': 1,
      });
      for (final limit in [-1, -2, -100]) {
        await h.expectError(
          'PATCH',
          'v1/admin/settings',
          400,
          'invalid_request',
          asAdmin: true,
          data: {
            'defaultPermissions': {'dailyTokenLimit': limit},
          },
        );
        if (limit != -1) {
          await h.expectError(
            'PATCH',
            'v1/admin/users/${user.id}',
            400,
            'invalid_request',
            asAdmin: true,
            data: {
              'permissions': {'dailyTokenLimit': limit},
            },
          );
        }
      }
    },
  );

  test(
    'private network guard covers IPv4, IPv6, mapped IPv4 and all DNS answers',
    () async {
      var addresses = [InternetAddress('8.8.8.8')];
      h = Harness(resolver: (_) async => addresses);
      final token = h.token(h.addUser('ana'));
      for (final host in [
        '127.0.0.1',
        '10.0.0.1',
        '172.16.1.1',
        '192.168.1.1',
        '169.254.169.254',
        '0.0.0.0',
        '224.0.0.1',
        '[::1]',
        '[::]',
        '[fc00::1]',
        '[fe80::1]',
        '[ff02::1]',
        '[::ffff:127.0.0.1]',
        '[::ffff:192.168.1.1]',
      ]) {
        await h.expectError(
          'POST',
          'v1/me/providers',
          400,
          'private_address',
          token: token,
          data: {'name': 'bad', 'baseUrl': 'http://$host/v1'},
        );
      }
      final provider = await h.provider(token: token);
      await h.jsonCall(
        'POST',
        'v1/me/providers/${provider['id']}/test',
        token: token,
      );
      addresses = [InternetAddress('8.8.8.8'), InternetAddress('127.0.0.1')];
      await h.expectError(
        'POST',
        'v1/me/providers/${provider['id']}/test',
        400,
        'private_address',
        token: token,
      );
      await h.expectError(
        'POST',
        'v1/chat/completions',
        400,
        'private_address',
        token: token,
        data: {'model': 'me/test/model'},
      );
      await h.expectError(
        'GET',
        'v1/models',
        400,
        'private_address',
        token: token,
      );
      await h.jsonCall(
        'PATCH',
        'v1/admin/settings',
        asAdmin: true,
        data: {'userProvidersAllowPrivateNetworks': true},
      );
      await h.jsonCall(
        'POST',
        'v1/chat/completions',
        token: token,
        data: {'model': 'me/test/model'},
      );
      expect(privateAddress(InternetAddress('2606:4700:4700::1111')), false);
      expect(privateAddress(InternetAddress('::ffff:8.8.8.8')), false);
    },
  );

  test('redirects cannot bypass provider network checks', () async {
    h = Harness(
      upstream: MockClient((request) async {
        expect(request.followRedirects, false);
        return http.Response(
          '',
          302,
          headers: {'location': 'http://127.0.0.1/secret'},
        );
      }),
    );
    final token = h.token(h.addUser('ana'));
    final provider = await h.provider(token: token);
    expect(
      (await h.jsonCall(
        'POST',
        'v1/me/providers/${provider['id']}/test',
        token: token,
      ))['ok'],
      false,
    );
    await h.expectError(
      'POST',
      'v1/chat/completions',
      502,
      'upstream_error',
      token: token,
      data: {'model': 'me/test/model'},
    );
  });

  test(
    'large chunked completions and SSE remain unchanged and meter split usage',
    () async {
      var payload = jsonEncode({
        'choices': [
          {
            'message': {'content': 'x' * (2 * 1024 * 1024)},
          },
        ],
        'usage': {'prompt_tokens': 7, 'completion_tokens': 3},
      });
      h = Harness(
        upstream: MockClient.streaming((request, stream) async {
          await stream.drain<void>();
          final bytes = utf8.encode(payload);
          return http.StreamedResponse(
            Stream.fromIterable([
              for (var offset = 0; offset < bytes.length; offset += 1021)
                bytes.sublist(offset, (offset + 1021).clamp(0, bytes.length)),
            ]),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );
      await h.provider();
      final response = await h.call(
        'POST',
        'v1/chat/completions',
        asAdmin: true,
        data: {'model': 'test/model'},
      );
      expect(
        sha256.convert(await response.read().expand((c) => c).toList()),
        sha256.convert(utf8.encode(payload)),
      );
      payload =
          'data: {"choices":[{"delta":{"content":"Hello"}}]}\n\n'
          'data: {"usage":{"prompt_tokens":5,"completion_tokens":2}}\n\n'
          'data: [DONE]\n\n';
      final second = await h.call(
        'POST',
        'v1/chat/completions',
        asAdmin: true,
        data: {'model': 'test/model', 'stream': true},
      );
      expect(await second.readAsString(), payload);
      final usage =
          ((await h.jsonCall('GET', 'v1/usage', asAdmin: true))['usage']
                      as List)
                  .single
              as Map;
      expect(usage['inputTokens'], 12);
      expect(usage['outputTokens'], 5);
    },
  );
}
