import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/chat/response_accumulator.dart';
import 'package:tako/core/providers/messages/messages_adapter.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/core/providers/responses/responses_adapter.dart';
import 'package:tako/core/providers/sse.dart';
import 'package:tako/core/util/json.dart';

import 'fixtures/streams.dart';

ProviderConfig config(ApiType type) => ProviderConfig(
  id: 'provider',
  displayName: 'test',
  apiType: type,
  baseUrl: 'https://provider.example',
  model: 'model',
);

ChatMessage history(List<ContentBlock> blocks) => ChatMessage(
  id: 'message',
  conversationId: 'chat',
  role: MessageRole.assistant,
  content: blocks,
  createdAt: DateTime.utc(2026),
  providerId: 'provider',
  model: 'model',
);

Stream<SseEvent> fixture(String data) =>
    parseSse(Stream.fromIterable(utf8.encode(data).map((byte) => [byte])));

void main() {
  test(
    'Anthropic fixture preserves complete thinking signature and call order through persistence',
    () async {
      final adapter = MessagesAdapter(config(ApiType.messages));
      final accumulator = ResponseAccumulator(
        sourceApi: 'messages',
        promptHash: 'fixed',
      );
      await for (final event in adapter.decode(fixture(messagesStream))) {
        accumulator.add(event);
      }
      expect(accumulator.content.map((b) => b.runtimeType), [
        ReasoningBlock,
        TextBlock,
        ToolCallBlock,
        ToolCallBlock,
      ]);
      expect(
        accumulator.content.whereType<ReasoningBlock>().single.signature,
        'signed-thinking',
      );
      expect(accumulator.usage!.inputTokens, 12);
      expect(accumulator.usage!.outputTokens, 8);
      final persisted = ContentBlock.listFromJson(
        accumulator.content.map((b) => b.toJson()).toList(),
      );
      final body = adapter.buildBody(
        ChatRequest(
          systemPrompt: 'system',
          messages: [history(persisted)],
          promptHash: 'fixed',
        ),
      );
      final messages = asList(body['messages'])!;
      final content = asList(asMap(messages.single)!['content'])!;
      expect(asMap(content.first), {
        'type': 'thinking',
        'thinking': '想一想',
        'signature': 'signed-thinking',
      });
      expect(asMap(content[2])!['id'], 'call_a');
      expect(asMap(content[3])!['id'], 'call_b');
      expect(asMap(content[2])!['input'], {'city': '東京'});
    },
  );

  test(
    'Responses fixture retains encrypted reasoning for stateless replay',
    () async {
      final adapter = ResponsesAdapter(config(ApiType.responses));
      final accumulator = ResponseAccumulator(
        sourceApi: 'responses',
        promptHash: 'fixed',
      );
      await for (final event in adapter.decode(fixture(responsesStream))) {
        accumulator.add(event);
      }
      final body = adapter.buildBody(
        ChatRequest(
          systemPrompt: 'system',
          messages: [history(accumulator.content)],
          promptHash: 'fixed',
        ),
      );
      expect(body['store'], false);
      expect(body['include'], ['reasoning.encrypted_content']);
      final items = asList(body['input'])!;
      expect(asMap(items.first)!['type'], 'reasoning');
      expect(asMap(items.first)!['encrypted_content'], 'opaque-reasoning');
      expect(asMap(items.first)!['id'], 'rs_1');
      expect(asMap(items[1]), {'role': 'assistant', 'content': '你好🌊'});
      expect(asMap(items[2])!['call_id'], 'call_a');
      expect(asMap(items[3])!['call_id'], 'call_b');
      final trimmed = adapter.buildBody(
        ChatRequest(
          systemPrompt: 'system',
          messages: [history(accumulator.content)],
          promptHash: 'fixed',
          replayOpaqueReasoning: false,
        ),
      );
      expect(jsonEncode(trimmed), isNot(contains('opaque-reasoning')));
    },
  );

  test(
    'metadata is a complete value, supports opaque-only thinking, and does not reorder blocks',
    () {
      final accumulator = ResponseAccumulator(
        sourceApi: 'messages',
        promptHash: 'fixed',
      );
      accumulator.add(const TextDelta(''));
      accumulator.add(
        const ReasoningMetadata(
          blockIndex: 0,
          sourceApi: 'messages',
          redactedData: 'redacted',
        ),
      );
      accumulator.add(const ReasoningDelta('summary', blockIndex: 1));
      accumulator.add(const TextDelta('answer'));
      accumulator.add(
        const ReasoningMetadata(
          blockIndex: 1,
          sourceApi: 'messages',
          signature: 'complete-signature',
        ),
      );
      accumulator.add(
        const ReasoningMetadata(
          blockIndex: 1,
          sourceApi: 'messages',
          signature: 'complete-signature',
        ),
      );
      final thoughts = accumulator.content.whereType<ReasoningBlock>().toList();
      expect(thoughts.first.text, isEmpty);
      expect(thoughts.first.redactedData, 'redacted');
      expect(thoughts.last.signature, 'complete-signature');
      expect(thoughts.last.text, 'summary');
      expect(accumulator.content.last, isA<TextBlock>());
    },
  );

  test('late usage merges cumulative input and output values', () {
    final accumulator = ResponseAccumulator(
      sourceApi: 'messages',
      promptHash: 'fixed',
    );
    accumulator.add(const Usage(inputTokens: 100, outputTokens: 1));
    accumulator.add(const TextDelta('answer'));
    accumulator.add(const Usage(outputTokens: 20, totalTokens: 120));
    expect(accumulator.usage!.inputTokens, 100);
    expect(accumulator.usage!.outputTokens, 20);
    expect(accumulator.usage!.totalTokens, 120);
  });

  test(
    'parallel argument fragments accumulate by call ID and preserve first-seen order',
    () {
      final accumulator = ResponseAccumulator(
        sourceApi: 'chatCompletions',
        promptHash: 'fixed',
      );
      for (final event in const <ProviderEvent>[
        ToolCallStart('a', 'first'),
        ToolCallStart('b', 'second'),
        ToolCallArgsDelta('b', '{"x":2}'),
        ToolCallArgsDelta('a', '{"x":'),
        ToolCallArgsDelta('a', '1}'),
        ToolCallEnd('b'),
        ToolCallEnd('a'),
      ]) {
        accumulator.add(event);
      }
      final calls = accumulator.content.whereType<ToolCallBlock>().toList();
      expect(calls.map((c) => c.id), ['a', 'b']);
      expect(calls.first.arguments, '{"x":1}');
      expect(calls.last.arguments, '{"x":2}');
    },
  );
}
