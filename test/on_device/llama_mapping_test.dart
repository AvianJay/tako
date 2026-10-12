import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/platform/on_device/llama_mapping.dart';

ChatMessage message(
  MessageRole role,
  List<ContentBlock> content, {
  String? contextEnvelope,
}) => ChatMessage(
  id: 'm-${role.name}',
  conversationId: 'c',
  role: role,
  content: content,
  createdAt: DateTime.utc(2026, 10, 12),
  contextEnvelope: contextEnvelope,
);

final pixel = base64Encode(List.filled(8, 7));

ChatRequest conversation() => ChatRequest(
  systemPrompt: 'fixed system',
  messages: [
    message(
      MessageRole.user,
      [
        const TextBlock('What is on the screen?'),
        ImageBlock(
          path: 'attachments/a.png',
          mimeType: 'image/png',
          data: pixel,
        ),
        const FileBlock(
          path: 'attachments/n.txt',
          name: 'n.txt',
          mimeType: 'text/plain',
          extractedText: 'notes',
        ),
      ],
      contextEnvelope: '<ctx time="2026-10-12 Mon 10:00 +08:00"/>',
    ),
    message(MessageRole.assistant, [
      const ReasoningBlock(text: 'I should look.'),
      const TextBlock('Looking.'),
      const ToolCallBlock(id: 'c1', name: 'read_screen', arguments: '{}'),
      const ToolCallBlock(
        id: 'c2',
        name: 'file_read',
        arguments: '{"path":"n.txt"}',
      ),
    ]),
    message(MessageRole.tool, [
      ToolResultBlock(
        toolCallId: 'c1',
        toolName: 'read_screen',
        content: '[1] button "OK"',
        attachments: [
          ImageBlock(path: 'shots/1.png', mimeType: 'image/png', data: pixel),
        ],
      ),
      const ToolResultBlock(
        toolCallId: 'c2',
        toolName: 'file_read',
        content: 'notes',
      ),
    ]),
  ],
  tools: const [
    ToolDefinition(
      name: 'file_read',
      description: 'Read a file.',
      schema: {
        'type': 'object',
        'properties': {
          'path': {'type': 'string', 'maxLength': 512},
          'limit': {'type': 'integer', 'minimum': 1},
          'mode': {
            'type': 'string',
            'enum': ['text', 'lines'],
          },
        },
        'required': ['path'],
        'additionalProperties': false,
      },
    ),
  ],
);

llama.LlamaCompletionChunk chunk({
  String? content,
  String? thinking,
  List<llama.LlamaCompletionChunkToolCall>? calls,
  String? finish,
  llama.LlamaGenerationUsage? usage,
}) => llama.LlamaCompletionChunk(
  id: 'x',
  object: 'chat.completion.chunk',
  created: 0,
  model: 'm',
  usage: usage,
  choices: [
    llama.LlamaCompletionChunkChoice(
      index: 0,
      finishReason: finish,
      delta: llama.LlamaCompletionChunkDelta(
        content: content,
        thinking: thinking,
        toolCalls: calls,
      ),
    ),
  ],
);

llama.LlamaCompletionChunkToolCall call(
  int index, {
  String? id,
  String? name,
  String? arguments,
}) => llama.LlamaCompletionChunkToolCall(
  index: index,
  id: id,
  function: llama.LlamaCompletionChunkFunction(
    name: name,
    arguments: arguments,
  ),
);

void main() {
  test('a conversation becomes llama.cpp chat messages', () {
    final messages = llamaMessages(conversation(), vision: true);
    expect(messages.map((m) => m.role), [
      llama.LlamaChatRole.system,
      llama.LlamaChatRole.user,
      llama.LlamaChatRole.assistant,
      llama.LlamaChatRole.tool,
      llama.LlamaChatRole.tool,
      llama.LlamaChatRole.user,
    ]);
    expect(messages[0].content, 'fixed system');
    final user = messages[1].parts;
    expect((user[0] as llama.LlamaTextContent).text, startsWith('<ctx time='));
    expect(user[2], isA<llama.LlamaImageContent>());
    expect(
      (user[3] as llama.LlamaTextContent).text,
      '[Untrusted file: n.txt]\nnotes',
    );
    // Earlier reasoning is not replayed; calls keep their IDs and arguments.
    final assistant = messages[2].parts;
    expect(assistant.whereType<llama.LlamaThinkingContent>(), isEmpty);
    final calls = assistant.whereType<llama.LlamaToolCallContent>().toList();
    expect(calls.map((c) => c.id), ['c1', 'c2']);
    expect(calls[1].arguments, {'path': 'n.txt'});
    expect(calls[1].rawJson, '{"path":"n.txt"}');
    // One tool message per result, then the screenshot as user content.
    expect(messages[3].toJson(), {
      'role': 'tool',
      'tool_call_id': 'c1',
      'name': 'read_screen',
      'content': '[1] button "OK"',
    });
    expect(messages[4].toJson()['tool_call_id'], 'c2');
    expect(
      (messages[5].parts.first as llama.LlamaTextContent).text,
      '[Untrusted tool attachment: read_screen]',
    );
    expect(messages[5].parts.last, isA<llama.LlamaImageContent>());
  });

  test('without a projector, images become placeholders', () {
    final messages = llamaMessages(conversation(), vision: false);
    expect(
      messages.expand((m) => m.parts).whereType<llama.LlamaImageContent>(),
      isEmpty,
    );
    expect(
      (messages[1].parts[2] as llama.LlamaTextContent).text,
      '[Image: not shown]',
    );
  });

  test('tools keep their schema and list parameters for templates', () {
    final tool = llamaTools(conversation().tools).single;
    expect(tool.toJsonSchema(), conversation().tools.single.schema);
    expect(tool.parameters.map((p) => p.name), ['path', 'limit', 'mode']);
    expect(tool.parameters.map((p) => p.required), [true, false, false]);
    expect(tool.parameters[1].toJsonSchema()['type'], 'integer');
    expect(tool.parameters[2].toJsonSchema()['enum'], ['text', 'lines']);
  });

  test('thinking follows the model settings', () {
    ProviderConfig config(ReasoningMode mode, {bool reasoning = true}) =>
        ProviderConfig(
          id: 'p',
          displayName: 'p',
          apiType: ApiType.onDevice,
          baseUrl: '',
          model: 'm.gguf',
          maxOutputTokens: 1024,
          reasoningMode: mode,
          thinkingBudgetTokens: 512,
          capabilities: ProviderCapabilities(reasoning: reasoning),
        );
    final request = conversation();
    final off = llamaGeneration(config(ReasoningMode.off), request);
    expect(off.thinking, isFalse);
    expect(off.params.maxTokens, 1024);
    expect(off.params.thinkingBudget, isNull);
    final on = llamaGeneration(config(ReasoningMode.enabled), request);
    expect(on.thinking, isTrue);
    expect(on.params.thinkingBudget!.maxTokens, 512);
    expect(
      llamaGeneration(
        config(ReasoningMode.adaptive),
        request,
      ).params.thinkingBudget,
      isNull,
    );
    expect(
      llamaGeneration(
        config(ReasoningMode.enabled, reasoning: false),
        request,
      ).thinking,
      isFalse,
    );
  });

  test('chunks become provider events', () async {
    final events = await providerEvents(
      Stream.fromIterable([
        chunk(thinking: 'Plan.'),
        chunk(content: 'Hel'),
        chunk(content: 'lo <think>aside</think>!'),
        chunk(
          calls: [
            call(0, id: 'a', name: 'read_screen', arguments: '{}'),
            call(1, name: 'file_', arguments: '{"path":'),
          ],
        ),
        chunk(
          calls: [call(1, name: 'read', arguments: '"n.txt"}')],
          finish: 'tool_calls',
          usage: const llama.LlamaGenerationUsage(
            promptTokens: 30,
            completionTokens: 12,
          ),
        ),
      ]),
    ).toList();
    expect(
      events.whereType<ReasoningDelta>().map((e) => e.text).join(),
      'Plan.aside',
    );
    expect(events.whereType<TextDelta>().map((e) => e.text).join(), 'Hello !');
    final starts = events.whereType<ToolCallStart>().toList();
    expect(starts.map((s) => s.name), ['read_screen', 'file_read']);
    expect(starts.first.id, 'a');
    expect(starts.last.id, startsWith('call_'));
    expect(
      events
          .whereType<ToolCallArgsDelta>()
          .where((e) => e.id == starts.last.id)
          .single
          .jsonFragment,
      '{"path":"n.txt"}',
    );
    expect(events.whereType<ToolCallEnd>(), hasLength(2));
    final usage = events.whereType<Usage>().single;
    expect((usage.inputTokens, usage.outputTokens), (30, 12));
    expect((events.last as Done).stopReason, 'tool_calls');
  });

  test('stopping at the token limit is reported as incomplete', () async {
    final events = await providerEvents(
      Stream.fromIterable([chunk(content: 'Part'), chunk(finish: 'length')]),
    ).toList();
    expect((events.last as ProviderError).code, 'incomplete_response');
  });
}
