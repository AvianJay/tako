import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/response_accumulator.dart';
import 'package:tako/core/providers/providers.dart';

class _Adapter implements ProviderAdapter {
  _Adapter(this.respond);
  final Stream<ProviderEvent> Function(int attempt) respond;
  final requests = <ChatRequest>[];

  @override
  Stream<ProviderEvent> send(
    ChatRequest request, {
    required CancelToken cancel,
  }) {
    requests.add(request);
    return respond(requests.length - 1);
  }

  @override
  Future<List<ModelInfo>> listModels({CancelToken? cancel}) async => [];
}

const _request = ChatRequest(systemPrompt: 'Task', messages: []);
const _delays = [Duration.zero, Duration.zero];
const _success = [TextDelta('Recovered'), Done('stop')];

void main() {
  test('retry resets partial text, reasoning, calls and usage', () async {
    final adapter = _Adapter(
      (attempt) => Stream.fromIterable(
        attempt == 0
            ? const [
                TextDelta('Discarded'),
                ReasoningDelta('Discarded thought'),
                ToolCallStart('old', 'tap'),
                ToolCallArgsDelta('old', '{"ref":'),
                Usage(inputTokens: 100, outputTokens: 20),
                ProviderError('Unavailable', statusCode: 503),
              ]
            : _success,
      ),
    );
    ResponseAccumulator fresh() =>
        ResponseAccumulator(sourceApi: 'messages', promptHash: 'test');
    var accumulator = fresh();
    var retries = 0;
    await for (final event in adapter.sendWithRetry(
      _request,
      cancel: CancelToken(),
      retryDelays: _delays,
      onRetry: () {
        retries++;
        accumulator = fresh();
      },
    )) {
      accumulator.add(event);
    }
    expect(retries, 1);
    expect(adapter.requests, hasLength(2));
    expect(identical(adapter.requests.first, adapter.requests.last), isTrue);
    expect(accumulator.content.single, isA<TextBlock>());
    expect((accumulator.content.single as TextBlock).text, 'Recovered');
    expect(accumulator.usage, isNull);
  });

  for (final error in const [
    ProviderError('Timeout', statusCode: 408),
    ProviderError('Rate limit', statusCode: 429),
    ProviderError('Server', statusCode: 500),
    ProviderError('Gateway', statusCode: 502),
    ProviderError('Unavailable', statusCode: 503),
    ProviderError('Network', code: 'network'),
    ProviderError('Timeout', code: 'timeout'),
    ProviderError('Overloaded', code: 'overloaded_error'),
    ProviderError('Interrupted', code: 'incomplete_stream'),
    ProviderError('Busy', code: 'aicore_busy'),
  ]) {
    test('retries transient ${error.statusCode ?? error.code}', () async {
      final adapter = _Adapter(
        (attempt) => Stream.fromIterable(attempt == 0 ? [error] : _success),
      );
      final events = await adapter
          .sendWithRetry(
            _request,
            cancel: CancelToken(),
            retryDelays: _delays,
            onRetry: () {},
          )
          .toList();
      expect(adapter.requests, hasLength(2));
      expect(events.whereType<ProviderError>(), isEmpty);
      expect(events.last, isA<Done>());
    });
  }

  for (final error in const [
    ProviderError('Invalid', statusCode: 400),
    ProviderError('Unauthorized', statusCode: 401),
    ProviderError('Denied', statusCode: 403),
    ProviderError('Missing model', statusCode: 404),
    ProviderError('Too large', statusCode: 413),
    ProviderError('Quota', statusCode: 429, code: 'insufficient_quota'),
    ProviderError(
      'Billing',
      statusCode: 429,
      code: 'billing_hard_limit_reached',
    ),
    ProviderError('Guardrail', code: 'apple_guardrail'),
    ProviderError('Bad tools', code: 'aicore_invalid_tools'),
  ]) {
    test(
      'surfaces permanent ${error.code ?? error.statusCode} immediately',
      () async {
        final adapter = _Adapter((_) => Stream.value(error));
        var retries = 0;
        final events = await adapter
            .sendWithRetry(
              _request,
              cancel: CancelToken(),
              retryDelays: _delays,
              onRetry: () => retries++,
            )
            .toList();
        expect(adapter.requests, hasLength(1));
        expect(retries, 0);
        expect(events.single, same(error));
      },
    );
  }

  test('stops after two retries and returns the last failure', () async {
    final adapter = _Adapter(
      (attempt) => Stream.fromIterable([
        TextDelta('Attempt $attempt'),
        ProviderError('Failure $attempt', statusCode: 503),
      ]),
    );
    var retries = 0;
    final events = await adapter
        .sendWithRetry(
          _request,
          cancel: CancelToken(),
          retryDelays: _delays,
          onRetry: () => retries++,
        )
        .toList();
    expect(adapter.requests, hasLength(3));
    expect(retries, 2);
    expect(events.whereType<ProviderError>().single.message, 'Failure 2');
  });

  test(
    'a stream ending without Done retries instead of silently stopping',
    () async {
      final adapter = _Adapter(
        (attempt) => Stream.fromIterable(
          attempt == 0 ? const [TextDelta('Interrupted')] : _success,
        ),
      );
      final events = await adapter
          .sendWithRetry(
            _request,
            cancel: CancelToken(),
            retryDelays: _delays,
            onRetry: () {},
          )
          .toList();
      expect(adapter.requests, hasLength(2));
      expect(events.last, isA<Done>());
    },
  );

  test(
    'thrown transport errors retry and do not expose their details',
    () async {
      final adapter = _Adapter((attempt) async* {
        if (attempt == 0) {
          throw http.ClientException('Private transport details');
        }
        if (attempt == 1) throw TimeoutException('Private timeout details');
        yield* Stream.fromIterable(_success);
      });
      final events = await adapter
          .sendWithRetry(
            _request,
            cancel: CancelToken(),
            retryDelays: _delays,
            onRetry: () {},
          )
          .toList();
      expect(adapter.requests, hasLength(3));
      expect(events.whereType<ProviderError>(), isEmpty);
      expect(events.last, isA<Done>());
    },
  );

  test(
    'Stop cancels the backoff and retains the last partial output',
    () async {
      final cancel = CancelToken();
      final adapter = _Adapter(
        (_) => Stream.fromIterable(const [
          TextDelta('Partial'),
          ProviderError('Unavailable', statusCode: 503),
        ]),
      );
      var retries = 0;
      final pending = adapter
          .sendWithRetry(
            _request,
            cancel: cancel,
            retryDelays: const [Duration(days: 1)],
            onRetry: () => retries++,
          )
          .toList();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      cancel.cancel();
      final events = await pending.timeout(const Duration(seconds: 1));
      expect(adapter.requests, hasLength(1));
      expect(retries, 0);
      expect((events.single as TextDelta).text, 'Partial');
    },
  );

  test('an already cancelled request never starts', () async {
    final adapter = _Adapter((_) => Stream.fromIterable(_success));
    final events = await adapter
        .sendWithRetry(
          _request,
          cancel: CancelToken()..cancel(),
          onRetry: () {},
        )
        .toList();
    expect(events, isEmpty);
    expect(adapter.requests, isEmpty);
  });

  test('a delivered image prevents a second image generation', () async {
    final adapter = _Adapter(
      (_) => Stream.fromIterable(const [
        GeneratedImage(base64: 'AQ==', mimeType: 'image/png'),
        ProviderError('Interrupted', code: 'incomplete_stream'),
      ]),
    );
    final events = await adapter
        .sendWithRetry(
          _request,
          cancel: CancelToken(),
          retryDelays: _delays,
          onRetry: () {},
        )
        .toList();
    expect(adapter.requests, hasLength(1));
    expect(events.first, isA<GeneratedImage>());
    expect(events.last, isA<ProviderError>());
  });
}
