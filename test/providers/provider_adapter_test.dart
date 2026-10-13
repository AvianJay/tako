import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/chat/response_accumulator.dart';
import 'package:tako/core/providers/chat_completions/chat_completions_adapter.dart';
import 'package:tako/core/providers/messages/messages_adapter.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/core/providers/responses/responses_adapter.dart';
import 'package:tako/core/providers/sse.dart';
import 'package:tako/core/util/json.dart';

import 'fixtures/streams.dart';

ProviderConfig config(ApiType type) => ProviderConfig(
  id: 'provider',
  displayName: 'Fixture provider',
  apiType: type,
  baseUrl: 'https://provider.example/v1/',
  model: 'fixture-model',
);

ChatMessage message(
  MessageRole role,
  List<ContentBlock> content, {
  String? contextEnvelope,
}) => ChatMessage(
  id: 'message',
  conversationId: 'conversation',
  role: role,
  content: content,
  createdAt: DateTime.utc(2026, 10, 10),
  contextEnvelope: contextEnvelope,
  providerId: 'provider',
  model: 'fixture-model',
);

final request = ChatRequest(
  systemPrompt: 'fixed system',
  messages: [
    message(MessageRole.user, [const TextBlock('hello')]),
  ],
);

Stream<List<int>> fragmented(String data) =>
    Stream.fromIterable(utf8.encode(data).map((byte) => [byte]));

class FakeClient extends http.BaseClient {
  FakeClient(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  http.BaseRequest? lastRequest;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    lastRequest = request;
    return handler(request);
  }

  @override
  void close() => closed = true;
}

void main() {
  test(
    'native Messages no-argument tool remains a valid empty JSON object',
    () async {
      final adapter = MessagesAdapter(config(ApiType.messages));
      final acc = ResponseAccumulator(
        sourceApi: 'messages',
        promptHash: 'test',
      );
      final events = await adapter
          .decode(
            Stream.fromIterable([
              SseEvent(
                data: jsonEncode({
                  'type': 'content_block_start',
                  'index': 0,
                  'content_block': {
                    'type': 'tool_use',
                    'id': 'read',
                    'name': 'read_screen',
                    'input': {},
                  },
                }),
              ),
              SseEvent(
                data: jsonEncode({
                  'type': 'content_block_delta',
                  'index': 0,
                  'delta': {'type': 'input_json_delta', 'partial_json': ''},
                }),
              ),
              SseEvent(
                data: jsonEncode({'type': 'content_block_stop', 'index': 0}),
              ),
              SseEvent(
                data: jsonEncode({
                  'type': 'message_delta',
                  'delta': {'stop_reason': 'tool_use'},
                }),
              ),
              SseEvent(data: jsonEncode({'type': 'message_stop'})),
            ]),
          )
          .toList();
      for (final event in events) {
        acc.add(event);
      }
      expect(acc.content.whereType<ToolCallBlock>().single.arguments, '{}');
      expect(events.whereType<ProviderError>(), isEmpty);
    },
  );
  const fixtures = {
    ApiType.chatCompletions: chatCompletionsStream,
    ApiType.responses: responsesStream,
    ApiType.messages: messagesStream,
  };
  const errors = {
    ApiType.chatCompletions: chatErrorStream,
    ApiType.responses: responsesErrorStream,
    ApiType.messages: messagesErrorStream,
  };

  // On-device models have their own tests in test/on_device.
  for (final type in ApiType.values.where((t) => t != ApiType.onDevice)) {
    group(type.name, () {
      test(
        'streams split UTF-8, reasoning, two distinct tool calls and usage',
        () async {
          final client = FakeClient(
            (_) async =>
                http.StreamedResponse(fragmented(fixtures[type]!), 200),
          );
          final adapter = ProviderAdapter.create(
            config(type),
            apiKey: 'fixture-key',
            clientFactory: () => client,
          );
          final events = await adapter
              .send(request, cancel: CancelToken())
              .toList();
          expect(events.whereType<ProviderError>(), isEmpty);
          expect(
            events.whereType<TextDelta>().map((e) => e.text).join(),
            '你好🌊',
          );
          expect(
            events.whereType<ReasoningDelta>().map((e) => e.text).join(),
            '想一想',
          );
          expect(events.whereType<ToolCallStart>().map((e) => e.id).toSet(), {
            'call_a',
            'call_b',
          });
          expect(events.whereType<ToolCallStart>().map((e) => e.name).toSet(), {
            'weather',
            'clock',
          });
          final args = <String, String>{};
          for (final event in events.whereType<ToolCallArgsDelta>()) {
            args[event.id] = '${args[event.id] ?? ''}${event.jsonFragment}';
          }
          expect(jsonDecode(args['call_a']!), {'city': '東京'});
          expect(jsonDecode(args['call_b']!), {'city': '台北'});
          expect(
            events.whereType<ToolCallEnd>().map((e) => e.id).toList()..sort(),
            ['call_a', 'call_b'],
          );
          expect(events.whereType<Usage>().last.inputTokens, 12);
          expect(events.whereType<Usage>().last.outputTokens, 8);
          expect(events.last, isA<Done>());
          expect(client.closed, isTrue);
          expect(client.lastRequest!.followRedirects, isFalse);
          expect(client.lastRequest!.url.path, switch (type) {
            ApiType.chatCompletions => '/v1/chat/completions',
            ApiType.responses => '/v1/responses',
            ApiType.messages => '/v1/messages',
            ApiType.onDevice => throw StateError('no endpoint'),
          });
          if (type == ApiType.messages) {
            expect(client.lastRequest!.headers['x-api-key'], 'fixture-key');
            expect(
              client.lastRequest!.headers['anthropic-version'],
              '2023-06-01',
            );
            expect(
              events.whereType<ReasoningMetadata>().single.signature,
              'signed-thinking',
            );
          } else {
            expect(
              client.lastRequest!.headers['authorization'],
              'Bearer fixture-key',
            );
          }
          if (type == ApiType.responses) {
            expect(
              events.whereType<ReasoningMetadata>().single.encryptedContent,
              'opaque-reasoning',
            );
          }
        },
      );

      test(
        'keeps partial text and reports a mid-stream provider error',
        () async {
          final client = FakeClient(
            (_) async => http.StreamedResponse(fragmented(errors[type]!), 200),
          );
          final events = await ProviderAdapter.create(
            config(type),
            clientFactory: () => client,
          ).send(request, cancel: CancelToken()).toList();
          expect(events.whereType<TextDelta>().single.text, 'partial');
          expect(
            events.whereType<ProviderError>().single.message,
            'overloaded',
          );
          expect(events.whereType<Done>(), isEmpty);
        },
      );

      test(
        'HTTP and stream errors cannot echo API keys or custom secrets',
        () async {
          for (final status in [401, 200]) {
            final body = jsonEncode({
              'error': {
                'message': 'Bad test-key and private-header',
                'code': 'unauthorized',
              },
            });
            final client = FakeClient(
              (_) async => http.StreamedResponse(
                fragmented(
                  status == 200 ? 'event: error\ndata: $body\n\n' : body,
                ),
                status,
              ),
            );
            final adapter = ProviderAdapter.create(
              config(type),
              apiKey: 'test-key',
              secretHeaders: {'X-Private': 'private-header'},
              clientFactory: () => client,
            );
            final events = await adapter
                .send(request, cancel: CancelToken())
                .toList();
            final error = events.whereType<ProviderError>().single;
            expect(error.message, contains('[REDACTED]'));
            expect(error.toString(), isNot(contains('test-key')));
            expect(error.toString(), isNot(contains('private-header')));
            if (status != 200) expect(error.statusCode, 401);
          }
        },
      );

      test('fetches sorted model list using provider authentication', () async {
        final client = FakeClient(
          (_) async => http.StreamedResponse(
            fragmented(
              '{"data":[{"id":"z"},{"id":"a","display_name":"Model A"}]}',
            ),
            200,
          ),
        );
        final adapter = ProviderAdapter.create(
          config(type),
          apiKey: 'fixture-key',
          clientFactory: () => client,
        );
        final models = await adapter.listModels(cancel: CancelToken());
        expect(models.map((m) => m.id), ['a', 'z']);
        expect(models.first.displayName, 'Model A');
        expect(client.lastRequest!.url.path, '/v1/models');
        expect(client.lastRequest!.method, 'GET');
        expect(client.closed, isTrue);
      });

      test('Stop cancels while waiting for headers', () async {
        final started = Completer<void>();
        final pending = Completer<http.StreamedResponse>();
        final client = FakeClient((_) {
          started.complete();
          return pending.future;
        });
        final cancel = CancelToken();
        final future = ProviderAdapter.create(
          config(type),
          clientFactory: () => client,
        ).send(request, cancel: cancel).toList();
        await started.future;
        cancel.cancel();
        expect(await future.timeout(const Duration(seconds: 1)), isEmpty);
        expect(client.closed, isTrue);
      });

      test('Stop cancels an idle stream without an error or Done', () async {
        final source = StreamController<List<int>>();
        final started = Completer<void>();
        source.onListen = started.complete;
        final client = FakeClient(
          (_) async => http.StreamedResponse(source.stream, 200),
        );
        final cancel = CancelToken();
        final future = ProviderAdapter.create(
          config(type),
          clientFactory: () => client,
        ).send(request, cancel: cancel).toList();
        await started.future;
        cancel.cancel();
        expect(await future.timeout(const Duration(seconds: 1)), isEmpty);
        expect(client.closed, isTrue);
        await source.close();
      });

      test('model listing can be cancelled while pending', () async {
        final started = Completer<void>();
        final pending = Completer<http.StreamedResponse>();
        final client = FakeClient((_) {
          started.complete();
          return pending.future;
        });
        final cancel = CancelToken();
        final future = ProviderAdapter.create(
          config(type),
          clientFactory: () => client,
        ).listModels(cancel: cancel);
        final expectation = expectLater(
          future,
          throwsA(isA<RequestCancelled>()),
        );
        await started.future;
        cancel.cancel();
        await expectation;
        expect(client.closed, isTrue);
      });

      test('reports premature EOF rather than successful completion', () async {
        final partial = errors[type]!.split('\n\n').first;
        final client = FakeClient(
          (_) async => http.StreamedResponse(fragmented('$partial\n\n'), 200),
        );
        final events = await ProviderAdapter.create(
          config(type),
          clientFactory: () => client,
        ).send(request, cancel: CancelToken()).toList();
        expect(
          events.whereType<ProviderError>().single.code,
          'incomplete_stream',
        );
        expect(events.whereType<Done>(), isEmpty);
      });
    });
  }

  test(
    'SSE handles BOM, CRLF, comments, multiple data lines and final EOF',
    () async {
      final events = await parseSse(
        fragmented(
          '\uFEFF: comment\r\nevent: custom\r\nid: 1\r\ndata: 你好\r\ndata: 🌊\r\n\r\ndata:last',
        ),
      ).toList();
      expect(events.first.data, '你好\n🌊');
      expect(events.first.event, 'custom');
      expect(events.last.id, '1');
      expect(events.last.data, 'last');
    },
  );

  test('all adapters map the frozen context and tool call/result IDs', () {
    final toolRequest = ChatRequest(
      systemPrompt: 'fixed system',
      messages: [
        message(MessageRole.user, [
          const TextBlock('hello'),
        ], contextEnvelope: '<ctx time="frozen"/>'),
        message(MessageRole.assistant, [
          const ToolCallBlock(
            id: 'call_a',
            name: 'weather',
            arguments: '{"city":"東京"}',
          ),
        ]),
        message(MessageRole.tool, [
          const ToolResultBlock(
            toolCallId: 'call_a',
            toolName: 'weather',
            content: 'sunny',
          ),
        ]),
      ],
      tools: [
        const ToolDefinition(
          name: 'weather',
          description: 'Read weather.',
          schema: {'type': 'object', 'properties': {}},
        ),
      ],
    );
    final chat = ChatCompletionsAdapter(
      config(ApiType.chatCompletions),
    ).buildBody(toolRequest);
    final chatMessages = chat['messages']! as List<Object?>;
    expect(asMap(chatMessages.first)!['role'], 'system');
    expect(asMap(chatMessages[1])!['content'], '<ctx time="frozen"/>\nhello');
    expect(asMap(chatMessages.last)!['tool_call_id'], 'call_a');
    expect(asMap((chat['tools']! as List).first)!['type'], 'function');
    final responses = ResponsesAdapter(
      config(ApiType.responses),
    ).buildBody(toolRequest);
    expect(responses['instructions'], 'fixed system');
    expect(responses['store'], false);
    final input = responses['input']! as List<Object?>;
    expect(asMap(input[1])!['call_id'], 'call_a');
    expect(asMap(input[2])!['call_id'], 'call_a');
    final messages = MessagesAdapter(
      config(ApiType.messages),
    ).buildBody(toolRequest);
    expect(messages['system'], 'fixed system');
    expect(messages['max_tokens'], 4096);
    final last = asMap((messages['messages']! as List).last)!;
    expect(last['role'], 'user');
    expect(asMap((last['content']! as List).single)!['tool_use_id'], 'call_a');
  });

  test('opaque thinking is replayed only for the original API and prompt', () {
    final blocks = [
      const ReasoningBlock(
        text: 'reason',
        signature: 'opaque-signature',
        sourceApi: 'messages',
        promptHash: 'original',
      ),
      const ReasoningBlock(
        text: 'reason',
        encryptedContent: 'opaque-encrypted',
        itemId: 'rs_1',
        sourceApi: 'responses',
        promptHash: 'original',
      ),
      const TextBlock('answer'),
    ];
    final history = [message(MessageRole.assistant, blocks)];
    for (final type in [ApiType.messages, ApiType.responses]) {
      final adapter =
          ProviderAdapter.create(config(type)) as HttpProviderAdapter;
      final same = jsonEncode(
        adapter.buildBody(
          ChatRequest(
            systemPrompt: 's',
            messages: history,
            promptHash: 'original',
          ),
        ),
      );
      expect(
        same,
        contains(
          type == ApiType.messages ? 'opaque-signature' : 'opaque-encrypted',
        ),
      );
      final changed = jsonEncode(
        adapter.buildBody(
          ChatRequest(
            systemPrompt: 's',
            messages: history,
            promptHash: 'changed',
          ),
        ),
      );
      expect(changed, isNot(contains('opaque-')));
    }
  });

  test('thinking is optional and validates an explicit Anthropic budget', () {
    final adaptive = MessagesAdapter(
      config(ApiType.messages).copyWith(
        reasoningMode: ReasoningMode.adaptive,
        reasoningEffort: 'xhigh',
      ),
    );
    expect(adaptive.buildBody(request)['thinking'], {'type': 'adaptive'});
    expect(adaptive.buildBody(request)['output_config'], {'effort': 'xhigh'});
    final basic = MessagesAdapter(config(ApiType.messages));
    expect(basic.buildBody(request).containsKey('thinking'), isFalse);
    final enabled = MessagesAdapter(
      config(ApiType.messages).copyWith(reasoningMode: ReasoningMode.enabled),
    );
    expect(enabled.buildBody(request)['thinking'], {
      'type': 'enabled',
      'budget_tokens': 1024,
    });
    expect(
      () => enabled.buildBody(
        ChatRequest(systemPrompt: '', messages: [], maxTokens: 1000),
      ),
      throwsA(isA<ProviderError>()),
    );
  });

  test('config never serializes runtime header secrets', () {
    final value = config(ApiType.responses).copyWith(
      apiKeyRef: 'key-reference',
      extraHeadersRef: 'headers-reference',
      extraHeaders: {'authorization': 'private-header'},
    );
    expect(jsonEncode(value.toJson()), isNot(contains('private-header')));
    final restored = ProviderConfig.fromJson(value.toJson());
    expect(restored.apiKeyRef, 'key-reference');
    expect(restored.extraHeadersRef, 'headers-reference');
    expect(restored.extraHeaders, isEmpty);
    expect(restored.apiType, ApiType.responses);
  });

  test('URL normalization accepts standard roots and endpoint URLs', () {
    for (final base in [
      'https://example.org',
      'https://example.org/',
      'https://example.org/v1',
      'https://example.org/v1/',
      'https://example.org/v1/chat/completions',
    ]) {
      expect(
        providerEndpoint(base, 'models').toString(),
        'https://example.org/v1/models',
      );
    }
    expect(
      providerEndpoint('https://example.org/proxy/v2/', '/responses').path,
      '/proxy/v2/responses',
    );
    for (final invalid in [
      'ftp://host',
      'https://key@host/v1',
      'https://host?api_key=secret',
      'https://host/#fragment',
    ]) {
      expect(() => providerEndpoint(invalid, 'models'), throwsFormatException);
    }
  });

  test('loopback, LAN IPv4 and private IPv6 are detected without DNS', () {
    for (final host in [
      'localhost',
      '127.0.0.1',
      '10.1.2.3',
      '192.168.1.2',
      '172.16.2.3',
      '172.31.2.3',
      'server.local',
      '::1',
      'fd12::1',
      'fe80::1',
    ]) {
      expect(isLocalHost(host), isTrue, reason: host);
    }
    for (final host in [
      '172.32.1.1',
      '8.8.8.8',
      'api.openai.com',
      '127.0.0.999',
    ]) {
      expect(isLocalHost(host), isFalse, reason: host);
    }
  });
}
