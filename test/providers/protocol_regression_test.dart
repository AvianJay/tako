import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/providers/providers.dart';

import 'fixtures/streams.dart';

ProviderConfig config(ApiType type) => ProviderConfig(
  id: 'provider',
  displayName: 'provider',
  apiType: type,
  baseUrl: 'https://provider.example',
  model: 'model',
);

ChatMessage history(MessageStatus status, List<ContentBlock> blocks) =>
    ChatMessage(
      id: 'message',
      conversationId: 'chat',
      role: MessageRole.assistant,
      content: blocks,
      createdAt: DateTime.utc(2026),
      providerId: 'provider',
      model: 'model',
      status: status,
    );

class StreamClient extends http.BaseClient {
  StreamClient(this.source, {this.status = 200});
  final Stream<List<int>> source;
  final int status;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(source, status);

  @override
  void close() => closed = true;
}

const request = ChatRequest(systemPrompt: 'system', messages: []);

void main() {
  test(
    'Kimi uses completion token limit and preserves valid reasoning history',
    () {
      final kimi = config(
        ApiType.chatCompletions,
      ).copyWith(baseUrl: 'https://api.moonshot.ai/v1', model: 'kimi-k3');
      final adapter = ProviderAdapter.create(kimi) as HttpProviderAdapter;
      final message = ChatMessage(
        id: 'a',
        conversationId: 'c',
        role: MessageRole.assistant,
        createdAt: DateTime.utc(2026),
        providerId: kimi.id,
        model: kimi.model,
        content: const [
          ReasoningBlock(
            text: 'reasoning',
            sourceApi: 'chatCompletions',
            promptHash: 'fixed',
          ),
          TextBlock('answer'),
        ],
      );
      final body = adapter.buildBody(
        ChatRequest(
          systemPrompt: 'system',
          messages: [message],
          promptHash: 'fixed',
        ),
      );
      expect(body.containsKey('max_completion_tokens'), isTrue);
      expect(body.containsKey('max_tokens'), isFalse);
      expect(jsonEncode(body), contains('reasoning_content'));
      final changed = adapter.buildBody(
        ChatRequest(
          systemPrompt: 'system',
          messages: [message],
          promptHash: 'fixed',
          replayOpaqueReasoning: false,
        ),
      );
      expect(jsonEncode(changed), isNot(contains('reasoning_content')));
    },
  );
  test(
    'interrupted responses never replay opaque reasoning, but retain readable partial text',
    () {
      for (final type in [ApiType.messages, ApiType.responses]) {
        final adapter =
            ProviderAdapter.create(config(type)) as HttpProviderAdapter;
        final blocks = [
          ReasoningBlock(
            text: 'thoughts',
            signature: 'opaque-signature',
            encryptedContent: 'opaque-encrypted',
            sourceApi: type.name,
            promptHash: 'fixed',
          ),
          const TextBlock('partial answer'),
        ];
        for (final status in [
          MessageStatus.stopped,
          MessageStatus.streaming,
          MessageStatus.error,
        ]) {
          final body = jsonEncode(
            adapter.buildBody(
              ChatRequest(
                systemPrompt: 'system',
                messages: [history(status, blocks)],
                promptHash: 'fixed',
              ),
            ),
          );
          expect(body, isNot(contains('opaque-')), reason: '$type/$status');
          expect(body, contains('partial answer'));
        }
      }
    },
  );

  test(
    'empty or unsigned reasoning blocks cannot produce invalid request items',
    () {
      for (final type in [ApiType.messages, ApiType.responses]) {
        final adapter =
            ProviderAdapter.create(config(type)) as HttpProviderAdapter;
        final blocks = [
          ReasoningBlock(
            text: 'unsigned-thoughts',
            signature: '',
            encryptedContent: '',
            redactedData: '',
            sourceApi: type.name,
            promptHash: 'fixed',
          ),
          const TextBlock('answer'),
        ];
        final body = jsonEncode(
          adapter.buildBody(
            ChatRequest(
              systemPrompt: 'system',
              messages: [history(MessageStatus.done, blocks)],
              promptHash: 'fixed',
            ),
          ),
        );
        expect(body, isNot(contains('unsigned-thoughts')));
        expect(body, contains('answer'));
      }
    },
  );

  for (final entry in {
    ApiType.chatCompletions: chatCompletionsStream.replaceAll(
      '"finish_reason":"tool_calls"',
      '"finish_reason":"length"',
    ),
    ApiType.messages: messagesStream.replaceAll(
      '"stop_reason":"tool_use"',
      '"stop_reason":"max_tokens"',
    ),
    ApiType.responses:
        'event: response.output_text.delta\ndata: {"type":"response.output_text.delta","delta":"partial"}\n\nevent: response.incomplete\ndata: {"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"}}}\n\n',
  }.entries) {
    test(
      '${entry.key.name} flags token truncation and preserves streamed output',
      () async {
        final client = StreamClient(Stream.value(utf8.encode(entry.value)));
        final events = await ProviderAdapter.create(
          config(entry.key),
          clientFactory: () => client,
        ).send(request, cancel: CancelToken()).toList();
        expect(
          events.whereType<ProviderError>().single.code,
          'incomplete_response',
        );
        expect(events.whereType<TextDelta>(), isNotEmpty);
        expect(events.whereType<Done>(), isEmpty);
        if (entry.key != ApiType.responses) {
          expect(events.whereType<Usage>().last.outputTokens, 8);
        }
        expect(client.closed, isTrue);
      },
    );
  }

  test(
    'cancelling model-body reads immediately detaches idle subscriptions',
    () async {
      final listening = Completer<void>();
      final detached = Completer<void>();
      final source = StreamController<List<int>>(
        onListen: listening.complete,
        onCancel: detached.complete,
      );
      final client = StreamClient(source.stream);
      final token = CancelToken();
      final future = ProviderAdapter.create(
        config(ApiType.messages),
        clientFactory: () => client,
      ).listModels(cancel: token);
      final expectation = expectLater(future, throwsA(isA<RequestCancelled>()));
      await listening.future;
      token.cancel();
      await expectation;
      await detached.future.timeout(const Duration(seconds: 1));
      await source.close();
      expect(client.closed, isTrue);
    },
  );

  test(
    'cancelling an idle HTTP error body detaches its subscription',
    () async {
      final listening = Completer<void>();
      final detached = Completer<void>();
      final source = StreamController<List<int>>(
        onListen: listening.complete,
        onCancel: detached.complete,
      );
      final client = StreamClient(source.stream, status: 500);
      final token = CancelToken();
      final future = ProviderAdapter.create(
        config(ApiType.messages),
        clientFactory: () => client,
      ).send(request, cancel: token).toList();
      await listening.future;
      token.cancel();
      expect(await future, isEmpty);
      await detached.future.timeout(const Duration(seconds: 1));
      await source.close();
      expect(client.closed, isTrue);
    },
  );

  test('socket failures never expose raw exception details', () async {
    final source = Stream<List<int>>.error(
      StateError('headers: credential-that-must-not-appear'),
    );
    final client = StreamClient(source);
    final events = await ProviderAdapter.create(
      config(ApiType.messages),
      clientFactory: () => client,
    ).send(request, cancel: CancelToken()).toList();
    expect(events.whereType<ProviderError>().single.code, 'network');
    expect(
      events.last.toString(),
      isNot(contains('credential-that-must-not-appear')),
    );
    expect(client.closed, isTrue);
  });
}
