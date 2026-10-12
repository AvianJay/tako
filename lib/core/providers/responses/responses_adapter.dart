import '../../chat/content_block.dart';
import '../../chat/message.dart';
import '../../util/json.dart';
import '../provider_adapter.dart';
import '../provider_config.dart';
import '../provider_event.dart';
import '../sse.dart';

class ResponsesAdapter extends HttpProviderAdapter {
  ResponsesAdapter(
    super.config, {
    super.apiKey,
    super.secretHeaders,
    super.clientFactory,
  });

  @override
  String get endpoint => 'responses';

  @override
  JsonMap buildBody(ChatRequest request) => {
    'model': config.model,
    'stream': true,
    'store': false,
    if (_webSearch(request)) 'max_tool_calls': 1,
    if (_webSearch(request) && request.forceBuiltInWebSearch)
      'tool_choice': {'type': 'web_search'},
    'instructions': request.systemPrompt,
    'max_output_tokens': request.maxTokens ?? config.maxOutputTokens,
    'include': ['reasoning.encrypted_content'],
    if (config.reasoningMode != ReasoningMode.off)
      'reasoning': {'effort': config.reasoningEffort, 'summary': 'auto'},
    'input': [
      for (final message in request.messages) ..._items(message, request),
    ],
    if (request.tools.isNotEmpty || _webSearch(request))
      'tools': [
        if (_webSearch(request)) {'type': 'web_search'},
        for (final tool in request.tools)
          if (!_webSearch(request) || tool.name != 'web_search')
            {
              'type': 'function',
              'name': tool.name,
              'description': tool.description,
              'parameters': tool.schema,
              'strict': false,
            },
      ],
  };

  bool _webSearch(ChatRequest request) =>
      request.builtInWebSearch &&
      config.capabilities.builtInWebSearch &&
      supportsBuiltInWebSearch(config);

  List<JsonMap> _items(ChatMessage message, ChatRequest request) {
    final state = message.content.whereType<ProviderStateBlock>().firstOrNull;
    if (state != null &&
        _webSearch(request) &&
        request.replayOpaqueReasoning &&
        message.status == MessageStatus.done &&
        message.role == MessageRole.assistant &&
        state.sourceApi == ApiType.responses.name &&
        message.providerId == config.id &&
        message.model == config.model &&
        state.promptHash == request.promptHash) {
      return [
        for (final item in state.content) Map<String, Object?>.from(item),
      ];
    }
    final items = <JsonMap>[];
    var content = <JsonMap>[];
    void flush() {
      if (content.isEmpty) return;
      items.add({
        'role': message.role == MessageRole.tool ? 'user' : message.role.name,
        // The documented easy-message format accepts assistant history as text.
        // Output-message objects have additional required fields, so do not
        // reconstruct incomplete output_text objects for ordinary chat history.
        'content':
            content.every(
              (part) =>
                  part['type'] == 'input_text' || part['type'] == 'output_text',
            )
            ? content.map((part) => part['text']).join()
            : content,
      });
      content = [];
    }

    for (final block in requestBlocks(message)) {
      switch (block) {
        case TextBlock():
          content.add({
            'type': message.role == MessageRole.assistant
                ? 'output_text'
                : 'input_text',
            'text': block.text,
          });
        case ImageBlock():
          final url = imageUrl(block);
          if (url != null) {
            content.add({'type': 'input_image', 'image_url': url});
          }
        case FileBlock():
          content.add({
            'type': 'input_text',
            'text':
                '[Untrusted file: ${block.name}]\n${block.extractedText ?? '[File attached]'}',
          });
        case ToolCallBlock():
          flush();
          items.add({
            'type': 'function_call',
            'call_id': block.id,
            'name': block.name,
            'arguments': block.arguments,
          });
        case ToolResultBlock():
          flush();
          items.add({
            'type': 'function_call_output',
            'call_id': block.toolCallId,
            'output': block.content,
          });
          if (block.attachments.isNotEmpty) {
            items.add({
              'role': 'user',
              'content': [
                {
                  'type': 'input_text',
                  'text': '[Untrusted tool attachment: ${block.toolName}]',
                },
                for (final attachment in block.attachments)
                  if (attachment is ImageBlock && imageUrl(attachment) != null)
                    {'type': 'input_image', 'image_url': imageUrl(attachment)}
                  else if (attachment is TextBlock)
                    {'type': 'input_text', 'text': attachment.text},
              ],
            });
          }
        case ReasoningBlock():
          if (state == null &&
              canReplayReasoning(message, block, request) &&
              (block.encryptedContent?.isNotEmpty ?? false)) {
            flush();
            items.add({
              'type': 'reasoning',
              if (block.itemId != null) 'id': block.itemId,
              'summary': [
                if (block.text.isNotEmpty)
                  {'type': 'summary_text', 'text': block.text},
              ],
              'encrypted_content': block.encryptedContent,
            });
          }
        case ProviderStateBlock():
          break;
      }
    }
    flush();
    return items;
  }

  @override
  Stream<ProviderEvent> decode(Stream<SseEvent> events) async* {
    final calls = <String, _Call>{};
    final citations = <String>{};
    final wireItems = <int, JsonMap>{};
    final searchReceipts = <String>{};
    await for (final event in events) {
      if (event.data == '[DONE]') continue;
      final data = decodeEvent(event);
      final type = asString(data['type']) ?? event.event;
      switch (type) {
        case 'response.web_search_call.completed':
          final id =
              asString(data['item_id']) ??
              'index:${asInt(data['output_index']) ?? 0}';
          if (!searchReceipts.contains('failed:$id') &&
              searchReceipts.add('completed:$id')) {
            yield const HostedSearchEvent(success: true);
          }
        case 'error':
        case 'response.failed':
          yield providerError(asMap(data['response']) ?? data);
          return;
        case 'response.incomplete':
          final response = asMap(data['response']);
          final reason =
              asString(asMap(response?['incomplete_details'])?['reason']) ??
              'incomplete';
          yield ProviderError(
            'Provider response is incomplete: ${redact(reason)}',
            code: 'incomplete_response',
          );
          return;
        case 'response.output_text.delta':
        case 'response.refusal.delta':
          yield TextDelta(asString(data['delta']) ?? '');
        case 'response.output_text.annotation.added':
          final annotation = asMap(data['annotation']);
          if (annotation?['type'] == 'url_citation') {
            final link = providerCitationLink(annotation);
            if (link != null && citations.add(link)) yield TextDelta(link);
          }
        case 'response.reasoning_summary_text.delta':
        case 'response.reasoning_text.delta':
          yield ReasoningDelta(
            asString(data['delta']) ?? '',
            blockIndex: asInt(data['output_index']) ?? 0,
          );
        case 'response.output_item.added':
          final item = asMap(data['item']);
          if (item?['type'] == 'function_call') {
            final itemId = asString(item?['id']) ?? '';
            final call = _Call(
              asString(item?['call_id']) ?? itemId,
              asString(item?['name']) ?? '',
            );
            calls[itemId] = call;
            yield ToolCallStart(call.id, call.name);
            final arguments = asString(item?['arguments']);
            if (arguments != null && arguments.isNotEmpty) {
              call.arguments += arguments;
              yield ToolCallArgsDelta(call.id, arguments);
            }
          }
        case 'response.function_call_arguments.delta':
          final call = calls[asString(data['item_id'])];
          if (call == null) {
            throw const ProviderError(
              'Provider returned arguments for an unknown tool call',
              code: 'invalid_stream',
            );
          }
          final fragment = asString(data['delta']) ?? '';
          call.arguments += fragment;
          yield ToolCallArgsDelta(call.id, fragment);
        case 'response.function_call_arguments.done':
          final call = calls[asString(data['item_id'])];
          if (call != null) {
            final args = asString(data['arguments']);
            if (args != null &&
                args.startsWith(call.arguments) &&
                args.length > call.arguments.length) {
              yield ToolCallArgsDelta(
                call.id,
                args.substring(call.arguments.length),
              );
              call.arguments = args;
            }
          }
        case 'response.output_item.done':
          final item = asMap(data['item']);
          if (item != null) {
            wireItems[asInt(data['output_index']) ?? wireItems.length] = item;
          }
          final itemId = asString(item?['id']);
          final searchReceipt = _searchReceipt(
            item,
            asInt(data['output_index']) ?? 0,
            searchReceipts,
          );
          if (searchReceipt != null) yield searchReceipt;
          final call = calls[itemId];
          if (item?['type'] == 'function_call' && call != null && !call.ended) {
            final args = asString(item?['arguments']);
            if (args != null &&
                args.startsWith(call.arguments) &&
                args.length > call.arguments.length) {
              yield ToolCallArgsDelta(
                call.id,
                args.substring(call.arguments.length),
              );
              call.arguments = args;
            }
            call.ended = true;
            yield ToolCallEnd(call.id);
          }
          if (item?['type'] == 'reasoning') {
            yield ReasoningMetadata(
              blockIndex: asInt(data['output_index']) ?? 0,
              sourceApi: ApiType.responses.name,
              encryptedContent: asString(item?['encrypted_content']),
              itemId: itemId,
            );
          }
          if (item?['type'] == 'message') {
            for (final content in asList(item?['content']) ?? <Object?>[]) {
              for (final annotation
                  in asList(asMap(content)?['annotations']) ?? <Object?>[]) {
                if (asMap(annotation)?['type'] != 'url_citation') continue;
                final link = providerCitationLink(annotation);
                if (link != null && citations.add(link)) yield TextDelta(link);
              }
            }
          }
        case 'response.completed':
          final response = asMap(data['response']);
          final status = response?['status'];
          // Compatible proxies may send contradictory event/envelope states.
          // An explicit non-completed status must never become a clean Done.
          if (status != null && status != 'completed') {
            if (status == 'failed') {
              yield providerError(response);
            } else {
              yield const ProviderError(
                'Provider response ended without a completed status',
                code: 'incomplete_response',
              );
            }
            return;
          }
          final output = asList(response?['output']);
          if (output != null) {
            for (var i = 0; i < output.length; i++) {
              if (asMap(output[i]) case final item?) {
                wireItems[i] = item;
                final receipt = _searchReceipt(item, i, searchReceipts);
                if (receipt != null) yield receipt;
              }
            }
          }
          if (wireItems.values.any(
            (item) => item['type'] == 'web_search_call',
          )) {
            final indices = wireItems.keys.toList()..sort();
            yield ProviderStateMetadata(
              sourceApi: ApiType.responses.name,
              content: [for (final index in indices) wireItems[index]!],
            );
          }
          final usage = asMap(response?['usage']);
          if (usage != null) {
            yield Usage(
              inputTokens: asInt(usage['input_tokens']),
              outputTokens: asInt(usage['output_tokens']),
              totalTokens: asInt(usage['total_tokens']),
            );
          }
          for (final call in calls.values) {
            if (!call.ended) yield ToolCallEnd(call.id);
          }
          yield Done(calls.isEmpty ? 'stop' : 'tool_calls');
          return;
      }
    }
  }

  HostedSearchEvent? _searchReceipt(
    JsonMap? item,
    int index,
    Set<String> receipts,
  ) {
    if (item?['type'] != 'web_search_call') return null;
    final status = asString(item?['status']);
    if (status != 'completed' && status != 'failed') return null;
    final id = asString(item?['id']) ?? 'index:$index';
    // Preserve later failure evidence even after an earlier success event;
    // capability probes must treat any native-search failure as sticky.
    if (status == 'completed' && receipts.contains('failed:$id')) return null;
    if (!receipts.add('$status:$id')) return null;
    return HostedSearchEvent(
      success: status == 'completed',
      errorCode: status == 'failed' ? 'web_search_failed' : null,
    );
  }
}

class _Call {
  _Call(this.id, this.name);
  final String id;
  final String name;
  String arguments = '';
  bool ended = false;
}
