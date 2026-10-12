import 'dart:convert';

import 'package:llamadart/llamadart.dart' as llama;

import '../../core/chat/content_block.dart';
import '../../core/chat/message.dart';
import '../../core/providers/providers.dart';
import '../../core/providers/think_parser.dart';
import '../../core/util/ids.dart';
import '../../core/util/json.dart';

/// The request as llama.cpp chat messages. Images reach the model only when a
/// projector is loaded ([vision]); otherwise a placeholder says one was there.
List<llama.LlamaChatMessage> llamaMessages(
  ChatRequest request, {
  required bool vision,
}) => [
  llama.LlamaChatMessage.fromText(
    role: llama.LlamaChatRole.system,
    text: request.systemPrompt,
  ),
  for (final message in request.messages) ..._messages(message, vision),
];

List<llama.LlamaChatMessage> _messages(ChatMessage message, bool vision) {
  final parts = <llama.LlamaContentPart>[];
  final results = <llama.LlamaChatMessage>[];
  final attachments = <llama.LlamaChatMessage>[];
  llama.LlamaContentPart image(ImageBlock block) => vision && block.data != null
      ? llama.LlamaImageContent(bytes: base64Decode(block.data!))
      : llama.LlamaTextContent('[Image: ${block.alt ?? 'not shown'}]');
  for (final block in requestBlocks(message)) {
    switch (block) {
      case TextBlock():
        parts.add(llama.LlamaTextContent(block.text));
      case ImageBlock():
        parts.add(image(block));
      case FileBlock():
        parts.add(
          llama.LlamaTextContent(
            '[Untrusted file: ${block.name}]\n'
            '${block.extractedText ?? '[File attached]'}',
          ),
        );
      case ToolCallBlock():
        parts.add(
          llama.LlamaToolCallContent(
            id: block.id,
            name: block.name,
            arguments: tryDecodeObject(block.arguments) ?? const {},
            rawJson: block.arguments,
          ),
        );
      case ToolResultBlock():
        // One tool message per result, in call order.
        results.add(
          llama.LlamaChatMessage.withContent(
            role: llama.LlamaChatRole.tool,
            content: [
              llama.LlamaToolResultContent(
                id: block.toolCallId,
                name: block.toolName,
                result: block.content,
              ),
            ],
          ),
        );
        if (block.attachments.isNotEmpty) {
          attachments.add(
            llama.LlamaChatMessage.withContent(
              role: llama.LlamaChatRole.user,
              content: [
                llama.LlamaTextContent(
                  '[Untrusted tool attachment: ${block.toolName}]',
                ),
                for (final attachment in block.attachments)
                  if (attachment is ImageBlock)
                    image(attachment)
                  else if (attachment is TextBlock)
                    llama.LlamaTextContent(attachment.text),
              ],
            ),
          );
        }
      case ReasoningBlock() || ProviderStateBlock():
        // Chat templates drop earlier reasoning themselves.
        break;
    }
  }
  return [
    if (parts.isNotEmpty)
      llama.LlamaChatMessage.withContent(
        role: switch (message.role) {
          MessageRole.assistant => llama.LlamaChatRole.assistant,
          _ => llama.LlamaChatRole.user,
        },
        content: parts,
      ),
    ...results,
    // Tool results must directly follow their calls; images are user content.
    ...attachments,
  ];
}

/// Tool definitions that keep Tako's JSON schemas exactly, for grammars and
/// templates, while also listing the top-level parameters for templates that
/// render them one by one.
List<llama.ToolDefinition> llamaTools(List<ToolDefinition> tools) => [
  for (final tool in tools) _SchemaTool(tool),
];

class _SchemaTool extends llama.ToolDefinition {
  _SchemaTool(ToolDefinition tool)
    : schema = tool.schema,
      super(
        name: tool.name,
        description: tool.description,
        parameters: _parameters(tool.schema),
      );
  final JsonMap schema;

  @override
  Map<String, dynamic> toJsonSchema() => schema;
}

List<llama.ToolParam> _parameters(JsonMap schema) {
  final required = {...?asList(schema['required'])?.whereType<String>()};
  return [
    for (final MapEntry(:key, :value)
        in (asMap(schema['properties']) ?? const {}).entries)
      if (asMap(value) case final property?)
        _parameter(key, property, required.contains(key)),
  ];
}

llama.ToolParam _parameter(String name, JsonMap schema, bool required) {
  final description = asString(schema['description']);
  final values = asList(schema['enum'])?.whereType<String>().toList();
  if (values != null && values.isNotEmpty) {
    return llama.ToolParam.enumType(
      name,
      values: values,
      description: description,
      required: required,
    );
  }
  return switch (schema['type']) {
    'integer' => llama.ToolParam.integer(
      name,
      description: description,
      required: required,
    ),
    'number' => llama.ToolParam.number(
      name,
      description: description,
      required: required,
    ),
    'boolean' => llama.ToolParam.boolean(
      name,
      description: description,
      required: required,
    ),
    'array' => llama.ToolParam.array(
      name,
      itemType: _parameter(
        'item',
        asMap(schema['items']) ?? const {'type': 'string'},
        false,
      ),
      description: description,
      required: required,
    ),
    'object' => llama.ToolParam.object(
      name,
      properties: _parameters(schema),
      description: description,
      required: required,
    ),
    _ => llama.ToolParam.string(
      name,
      description: description,
      required: required,
    ),
  };
}

/// Sampling for [config]: thinking follows the model's reasoning settings.
({llama.GenerationParams params, bool thinking}) llamaGeneration(
  ProviderConfig config,
  ChatRequest request,
) {
  final thinking =
      config.capabilities.reasoning &&
      config.reasoningMode != ReasoningMode.off;
  return (
    thinking: thinking,
    params: llama.GenerationParams(
      maxTokens: request.maxTokens ?? config.maxOutputTokens,
      // Qwen's recommended sampling; no repetition penalty, which would
      // bend repeated JSON keys in tool calls.
      temp: thinking ? 0.6 : 0.7,
      topK: 20,
      topP: thinking ? 0.95 : 0.8,
      penalty: 1,
      thinkingBudget: thinking && config.reasoningMode == ReasoningMode.enabled
          ? llama.ThinkingBudget(maxTokens: config.thinkingBudgetTokens)
          : null,
    ),
  );
}

/// Turns completion chunks into provider events. llama.cpp parses tool calls
/// from the model's output, so calls usually arrive whole with the last chunk.
Stream<ProviderEvent> providerEvents(
  Stream<llama.LlamaCompletionChunk> chunks,
) async* {
  final think = ThinkParser();
  final calls = <int, _Call>{};
  String? finishReason;
  llama.LlamaGenerationUsage? usage;
  await for (final chunk in chunks) {
    usage = chunk.usage ?? usage;
    final choice = chunk.choices.firstOrNull;
    if (choice == null) continue;
    finishReason = choice.finishReason ?? finishReason;
    final delta = choice.delta;
    if (delta.thinking case final text? when text.isNotEmpty) {
      yield ReasoningDelta(text);
    }
    if (delta.content case final text? when text.isNotEmpty) {
      yield* Stream.fromIterable(think.add(text));
    }
    for (final fragment
        in delta.toolCalls ?? const <llama.LlamaCompletionChunkToolCall>[]) {
      final call = calls.putIfAbsent(fragment.index, _Call.new);
      call.id ??= fragment.id;
      call.name += fragment.function?.name ?? '';
      call.arguments.write(fragment.function?.arguments ?? '');
    }
  }
  yield* Stream.fromIterable(think.add('', finish: true));
  for (final call in calls.values) {
    if (call.name.isEmpty) continue;
    final id = call.id?.isNotEmpty == true ? call.id! : 'call_${newId()}';
    yield ToolCallStart(id, call.name);
    final arguments = call.arguments.toString();
    yield ToolCallArgsDelta(id, arguments.isEmpty ? '{}' : arguments);
    yield ToolCallEnd(id);
  }
  if (usage != null) {
    yield Usage(
      inputTokens: usage.promptTokens,
      outputTokens: usage.completionTokens,
      totalTokens: usage.promptTokens + usage.completionTokens,
    );
  }
  yield finishReason == 'length'
      ? const ProviderError(
          'The model stopped at its output or context limit',
          code: 'incomplete_response',
        )
      : Done(finishReason ?? 'stop');
}

class _Call {
  String? id;
  String name = '';
  final arguments = StringBuffer();
}
