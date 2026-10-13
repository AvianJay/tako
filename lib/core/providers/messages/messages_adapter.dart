import 'dart:convert';

import '../../chat/content_block.dart';
import '../../chat/message.dart';
import '../../util/json.dart';
import '../provider_adapter.dart';
import '../provider_config.dart';
import '../provider_event.dart';
import '../sse.dart';

class MessagesAdapter extends HttpProviderAdapter {
  MessagesAdapter(
    super.config, {
    super.apiKey,
    super.secretHeaders,
    super.clientFactory,
  });

  @override
  String get endpoint => 'messages';

  @override
  JsonMap buildBody(ChatRequest request) {
    final maxTokens = request.maxTokens ?? config.maxOutputTokens;
    if (maxTokens <= 0 ||
        config.reasoningMode == ReasoningMode.enabled &&
            (config.thinkingBudgetTokens < 1024 ||
                config.thinkingBudgetTokens >= maxTokens)) {
      throw const ProviderError(
        'Thinking budget must be at least 1024 and below the output token limit',
        code: 'invalid_config',
      );
    }
    final messages = <JsonMap>[];
    for (final message in request.messages) {
      final content = _content(message, request);
      if (content.isEmpty) continue;
      final role = message.role == MessageRole.assistant ? 'assistant' : 'user';
      if (messages.isNotEmpty && messages.last['role'] == role) {
        (messages.last['content']! as List<JsonMap>).addAll(content);
      } else {
        messages.add({'role': role, 'content': content});
      }
    }
    final tools = <JsonMap>[
      if (_webSearch(request))
        {'type': 'web_search_20250305', 'name': 'web_search', 'max_uses': 1},
      for (final tool in request.tools)
        if (!_webSearch(request) || tool.name != 'web_search')
          {
            'name': tool.name,
            'description': tool.description,
            'input_schema': tool.schema,
          },
    ];
    if (request.cachePrompt) {
      if (tools.isNotEmpty) tools.last['cache_control'] = {'type': 'ephemeral'};
      if (messages.isNotEmpty) {
        final blocks = messages.last['content'] as List<JsonMap>;
        if (blocks.isNotEmpty &&
            !{'thinking', 'redacted_thinking'}.contains(blocks.last['type'])) {
          blocks.last['cache_control'] = {'type': 'ephemeral'};
        }
      }
    }
    return {
      'model': config.model,
      'stream': true,
      'max_tokens': maxTokens,
      'system': request.cachePrompt
          ? [
              {
                'type': 'text',
                'text': request.systemPrompt,
                'cache_control': {'type': 'ephemeral'},
              },
            ]
          : request.systemPrompt,
      'messages': messages,
      if (_webSearch(request) && request.forceBuiltInWebSearch)
        'tool_choice': {'type': 'tool', 'name': 'web_search'},
      if (config.reasoningMode == ReasoningMode.enabled)
        'thinking': {
          'type': 'enabled',
          'budget_tokens': config.thinkingBudgetTokens,
        },
      if (config.reasoningMode == ReasoningMode.adaptive)
        'thinking': {'type': 'adaptive'},
      if (config.reasoningMode == ReasoningMode.adaptive)
        'output_config': {'effort': config.reasoningEffort},
      if (tools.isNotEmpty) 'tools': tools,
    };
  }

  bool _webSearch(ChatRequest request) =>
      request.builtInWebSearch &&
      config.capabilities.builtInWebSearch &&
      supportsBuiltInWebSearch(config);

  List<JsonMap> _content(ChatMessage message, ChatRequest request) {
    final state = message.content.whereType<ProviderStateBlock>().firstOrNull;
    if (state != null &&
        _webSearch(request) &&
        request.replayOpaqueReasoning &&
        message.status == MessageStatus.done &&
        message.role == MessageRole.assistant &&
        state.sourceApi == ApiType.messages.name &&
        message.providerId == config.id &&
        message.model == config.model &&
        state.promptHash == request.promptHash) {
      return [
        for (final block in state.content) Map<String, Object?>.from(block),
      ];
    }
    final blocks = <JsonMap>[];
    for (final block in requestBlocks(message)) {
      switch (block) {
        case TextBlock():
          if (block.text.isNotEmpty) {
            blocks.add({'type': 'text', 'text': block.text});
          }
        case ImageBlock():
          if (block.data != null) {
            blocks.add({
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': block.mimeType,
                'data': block.data,
              },
            });
          } else if (imageUrl(block) case final url?) {
            blocks.add({
              'type': 'image',
              'source': {'type': 'url', 'url': url},
            });
          }
        case FileBlock():
          blocks.add({
            'type': 'text',
            'text':
                '[Untrusted file: ${block.name}]\n${block.extractedText ?? '[File attached]'}',
          });
        case ToolCallBlock():
          final input = tryDecodeObject(block.arguments);
          final answeredError = request.messages
              .expand((m) => m.content)
              .whereType<ToolResultBlock>()
              .any((result) => result.toolCallId == block.id && result.isError);
          if (input == null && !answeredError) {
            throw const ProviderError(
              'Tool arguments must be a JSON object',
              code: 'invalid_tool_arguments',
            );
          }
          blocks.add({
            'type': 'tool_use',
            'id': block.id,
            'name': block.name,
            'input': input ?? <String, Object?>{},
          });
        case ToolResultBlock():
          blocks.add({
            'type': 'tool_result',
            'tool_use_id': block.toolCallId,
            'content': block.attachments.isEmpty
                ? block.content
                : [
                    {'type': 'text', 'text': block.content},
                    for (final attachment in block.attachments)
                      if (attachment is ImageBlock && attachment.data != null)
                        {
                          'type': 'image',
                          'source': {
                            'type': 'base64',
                            'media_type': attachment.mimeType,
                            'data': attachment.data,
                          },
                        }
                      else if (attachment is TextBlock)
                        {'type': 'text', 'text': attachment.text},
                  ],
            'is_error': block.isError,
          });
        case ReasoningBlock():
          if (state != null) continue;
          if (!canReplayReasoning(message, block, request)) continue;
          if (block.redactedData?.isNotEmpty ?? false) {
            blocks.add({
              'type': 'redacted_thinking',
              'data': block.redactedData,
            });
          } else if (block.signature?.isNotEmpty ?? false) {
            blocks.add({
              'type': 'thinking',
              'thinking': block.text,
              'signature': block.signature,
            });
          }
        case ProviderStateBlock():
          break;
      }
    }
    return blocks;
  }

  @override
  Stream<ProviderEvent> decode(Stream<SseEvent> events) async* {
    final calls = <int, String>{};
    final serverCalls = <int>{};
    final wireBlocks = <int, JsonMap>{};
    final wireInputs = <int, String>{};
    final searchReceipts = <int>{};
    final citations = <String>{};
    var hasServerState = false;
    final signatures = <int, String>{};
    String? stopReason;
    int? inputTokens;
    int? outputTokens;
    await for (final event in events) {
      final data = decodeEvent(event);
      final type = asString(data['type']) ?? event.event;
      final index = asInt(data['index']) ?? 0;
      switch (type) {
        case 'error':
          yield providerError(data);
          return;
        case 'message_start':
          final usage = asMap(asMap(data['message'])?['usage']);
          inputTokens = asInt(usage?['input_tokens']);
          outputTokens = asInt(usage?['output_tokens']);
          if (usage != null) {
            yield Usage(inputTokens: inputTokens, outputTokens: outputTokens);
          }
        case 'content_block_start':
          final block = asMap(data['content_block']);
          if (block != null) {
            wireBlocks[index] = Map<String, Object?>.from(block);
          }
          switch (block?['type']) {
            case 'text':
              final text = asString(block?['text']) ?? '';
              if (text.isNotEmpty) yield TextDelta(text);
              for (final citation
                  in asList(block?['citations']) ?? <Object?>[]) {
                final link = providerCitationLink(citation);
                if (link != null && citations.add(link)) yield TextDelta(link);
              }
            case 'server_tool_use':
              serverCalls.add(index);
              hasServerState = true;
            case 'web_search_tool_result':
              hasServerState = true;
            case 'thinking':
              final text = asString(block?['thinking']) ?? '';
              if (text.isNotEmpty) {
                yield ReasoningDelta(text, blockIndex: index);
              }
              signatures[index] = asString(block?['signature']) ?? '';
            case 'redacted_thinking':
              yield ReasoningMetadata(
                blockIndex: index,
                sourceApi: ApiType.messages.name,
                redactedData: asString(block?['data']),
              );
            case 'tool_use':
              final id = asString(block?['id']) ?? '';
              calls[index] = id;
              yield ToolCallStart(id, asString(block?['name']) ?? '');
              final input = asMap(block?['input']);
              if (input != null && input.isNotEmpty) {
                yield ToolCallArgsDelta(id, jsonEncode(input));
              }
          }
        case 'content_block_delta':
          final delta = asMap(data['delta']);
          final wire = wireBlocks[index];
          if (wire != null) {
            switch (delta?['type']) {
              case 'text_delta':
                wire['text'] =
                    '${asString(wire['text']) ?? ''}${asString(delta?['text']) ?? ''}';
              case 'thinking_delta':
                wire['thinking'] =
                    '${asString(wire['thinking']) ?? ''}${asString(delta?['thinking']) ?? ''}';
              case 'signature_delta':
                wire['signature'] =
                    '${asString(wire['signature']) ?? ''}${asString(delta?['signature']) ?? ''}';
              case 'input_json_delta':
                wireInputs[index] =
                    '${wireInputs[index] ?? ''}${asString(delta?['partial_json']) ?? ''}';
              case 'citations_delta':
                wire['citations'] = [
                  ...?asList(wire['citations']),
                  ?asMap(delta?['citation']),
                ];
            }
          }
          switch (delta?['type']) {
            case 'text_delta':
              yield TextDelta(asString(delta?['text']) ?? '');
            case 'thinking_delta':
              yield ReasoningDelta(
                asString(delta?['thinking']) ?? '',
                blockIndex: index,
              );
            case 'signature_delta':
              signatures[index] =
                  '${signatures[index] ?? ''}${asString(delta?['signature']) ?? ''}';
            case 'input_json_delta':
              if (serverCalls.contains(index)) continue;
              final id = calls[index];
              if (id == null) {
                throw const ProviderError(
                  'Provider returned arguments for an unknown tool call',
                  code: 'invalid_stream',
                );
              }
              yield ToolCallArgsDelta(
                id,
                asString(delta?['partial_json']) ?? '',
              );
            case 'citations_delta':
              final link = providerCitationLink(delta?['citation']);
              if (link != null && citations.add(link)) yield TextDelta(link);
          }
        case 'content_block_stop':
          final searchReceipt = _searchReceipt(
            wireBlocks[index],
            index,
            searchReceipts,
          );
          if (searchReceipt != null) yield searchReceipt;
          final partialInput = wireInputs.remove(index);
          if (partialInput case final input?) {
            final parsed = tryDecodeObject(input);
            if (parsed != null) wireBlocks[index]?['input'] = parsed;
          }
          if ((partialInput == null || partialInput.isEmpty) &&
              calls[index] != null) {
            // Anthropic emits input:{} with no JSON delta for a no-argument
            // tool. Preserve the valid empty object instead of empty text.
            final input = asMap(wireBlocks[index]?['input']);
            if (input != null && input.isEmpty) {
              yield ToolCallArgsDelta(calls[index]!, '{}');
            }
          }
          if (calls.remove(index) case final id?) yield ToolCallEnd(id);
          if (signatures.remove(index) case final signature?) {
            if (signature.isNotEmpty) {
              yield ReasoningMetadata(
                blockIndex: index,
                sourceApi: ApiType.messages.name,
                signature: signature,
              );
            }
          }
        case 'message_delta':
          stopReason =
              asString(asMap(data['delta'])?['stop_reason']) ?? stopReason;
          final usage = asMap(data['usage']);
          inputTokens = asInt(usage?['input_tokens']) ?? inputTokens;
          outputTokens = asInt(usage?['output_tokens']) ?? outputTokens;
          if (usage != null) {
            yield Usage(
              inputTokens: inputTokens,
              outputTokens: outputTokens,
              totalTokens: inputTokens != null && outputTokens != null
                  ? inputTokens + outputTokens
                  : null,
            );
          }
        case 'message_stop':
          for (final entry in wireBlocks.entries) {
            final receipt = _searchReceipt(
              entry.value,
              entry.key,
              searchReceipts,
            );
            if (receipt != null) yield receipt;
          }
          for (final id in calls.values) {
            yield ToolCallEnd(id);
          }
          if (hasServerState && stopReason != 'max_tokens') {
            final indices = wireBlocks.keys.toList()..sort();
            yield ProviderStateMetadata(
              sourceApi: ApiType.messages.name,
              content: [for (final index in indices) wireBlocks[index]!],
            );
          }
          if (stopReason == 'max_tokens' ||
              (stopReason == 'pause_turn' && !hasServerState)) {
            yield ProviderError(
              'Provider response is incomplete: $stopReason',
              code: 'incomplete_response',
            );
          } else {
            yield Done(stopReason ?? 'end_turn');
          }
          return;
      }
    }
  }

  HostedSearchEvent? _searchReceipt(
    JsonMap? block,
    int index,
    Set<int> receipts,
  ) {
    if (block?['type'] != 'web_search_tool_result' || !receipts.add(index)) {
      return null;
    }
    final content = block?['content'];
    if (content is List) return const HostedSearchEvent(success: true);
    final error = asMap(content);
    return HostedSearchEvent(
      success: false,
      errorCode: error?['type'] == 'web_search_tool_result_error'
          ? redact(asString(error?['error_code']) ?? 'web_search_failed')
          : 'invalid_search_result',
    );
  }
}
