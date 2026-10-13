import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../chat/content_block.dart';
import '../../chat/message.dart';
import '../../util/json.dart';
import '../images/generated_image.dart';
import '../provider_adapter.dart';
import '../provider_config.dart';
import '../provider_event.dart';
import '../sse.dart';
import '../think_parser.dart';

class ChatCompletionsAdapter extends HttpProviderAdapter {
  ChatCompletionsAdapter(
    super.config, {
    super.apiKey,
    super.secretHeaders,
    super.clientFactory,
  });

  @override
  String get endpoint => 'chat/completions';

  @override
  JsonMap buildBody(ChatRequest request) => {
    'model': config.model,
    'stream': true,
    'stream_options': {'include_usage': true},
    if (config.capabilities.imageGeneration == ImageGenerationMode.chatOutput)
      'modalities': ['text', 'image'],
    if ({
      'api.openai.com',
      'api.moonshot.ai',
      'api.moonshot.cn',
      'api.kimi.com',
    }.contains(Uri.parse(config.baseUrl).host))
      'max_completion_tokens': request.maxTokens ?? config.maxOutputTokens
    else
      'max_tokens': request.maxTokens ?? config.maxOutputTokens,
    if (config.reasoningMode != ReasoningMode.off)
      'reasoning_effort': config.reasoningEffort,
    'messages': [
      {'role': 'system', 'content': request.systemPrompt},
      for (final message in request.messages) ..._messages(message, request),
    ],
    if (request.tools.isNotEmpty)
      'tools': [
        for (final tool in request.tools)
          {
            'type': 'function',
            'function': {
              'name': tool.name,
              'description': tool.description,
              'parameters': tool.schema,
            },
          },
      ],
  };

  List<JsonMap> _messages(ChatMessage message, ChatRequest request) {
    final result = <JsonMap>[];
    final attachmentMessages = <JsonMap>[];
    final content = <JsonMap>[];
    final calls = <JsonMap>[];
    final reasoning = StringBuffer();
    for (final block in requestBlocks(message)) {
      switch (block) {
        case TextBlock():
          content.add({'type': 'text', 'text': block.text});
        case ImageBlock():
          final url = imageUrl(block);
          if (url != null) {
            final image = <String, Object?>{
              'type': 'image_url',
              'image_url': {'url': url},
            };
            if (message.role == MessageRole.assistant) {
              attachmentMessages.add({
                'role': 'user',
                'content': [
                  {
                    'type': 'text',
                    'text':
                        '[Image generated in the preceding assistant reply]',
                  },
                  image,
                ],
              });
            } else {
              content.add(image);
            }
          }
        case ToolCallBlock():
          calls.add({
            'id': block.id,
            'type': 'function',
            'function': {'name': block.name, 'arguments': block.arguments},
          });
        case ToolResultBlock():
          result.add({
            'role': 'tool',
            'tool_call_id': block.toolCallId,
            'content': block.content,
          });
          if (block.attachments.isNotEmpty) {
            attachmentMessages.add({
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text': '[Untrusted tool attachment: ${block.toolName}]',
                },
                for (final attachment in block.attachments)
                  if (attachment is ImageBlock && imageUrl(attachment) != null)
                    {
                      'type': 'image_url',
                      'image_url': {'url': imageUrl(attachment)},
                    }
                  else if (attachment is TextBlock)
                    {'type': 'text', 'text': attachment.text},
              ],
            });
          }
        case FileBlock():
          content.add({
            'type': 'text',
            'text':
                '[Untrusted file: ${block.name}]\n${block.extractedText ?? '[File attached]'}',
          });
        case ReasoningBlock():
          // Kimi requires preserved reasoning for multi-turn requests.
          if (config.model.toLowerCase().split('/').last.startsWith('kimi-') &&
              canReplayReasoning(message, block, request)) {
            reasoning.write(block.text);
          }
          break;
        case ProviderStateBlock():
          break;
      }
    }
    if (content.isNotEmpty || calls.isNotEmpty) {
      result.insert(0, {
        'role': message.role == MessageRole.tool ? 'user' : message.role.name,
        'content': content.every((part) => part['type'] == 'text')
            ? content.map((part) => part['text']).join()
            : content,
        if (calls.isNotEmpty) 'tool_calls': calls,
        if (reasoning.isNotEmpty) 'reasoning_content': reasoning.toString(),
      });
    }
    // All tool replies must immediately follow their assistant's tool calls.
    // Images are user content in this API, so append them after the full batch.
    if (message.role == MessageRole.assistant && calls.isNotEmpty) {
      return [...attachmentMessages, ...result];
    }
    return [...result, ...attachmentMessages];
  }

  @override
  Stream<ProviderEvent> decode(Stream<SseEvent> events) async* {
    final think = ThinkParser();
    final calls = <int, _Call>{};
    final images = <String>{};
    String? finishReason;
    await for (final event in events) {
      if (event.data.trim() == '[DONE]') {
        yield* Stream.fromIterable(think.add('', finish: true));
        for (final call in calls.values) {
          if (!call.started) yield ToolCallStart(call.id, call.name);
          yield ToolCallEnd(call.id);
        }
        yield _terminalEvent(finishReason);
        return;
      }
      final data = decodeEvent(event);
      if (data['error'] != null) {
        yield providerError(data);
        return;
      }
      final usage = asMap(data['usage']);
      if (usage != null) {
        yield Usage(
          inputTokens: asInt(usage['prompt_tokens']),
          outputTokens: asInt(usage['completion_tokens']),
          totalTokens: asInt(usage['total_tokens']),
        );
      }
      for (final rawChoice in asList(data['choices']) ?? []) {
        final choice = asMap(rawChoice);
        if (choice == null || (asInt(choice['index']) ?? 0) != 0) continue;
        finishReason = asString(choice['finish_reason']) ?? finishReason;
        // Some compatible providers return the final message in an SSE chunk.
        final delta = asMap(choice['delta']) ?? asMap(choice['message']);
        if (delta == null) continue;
        final reasoning =
            asString(delta['reasoning_content']) ??
            asString(delta['reasoning']);
        if (reasoning != null && reasoning.isNotEmpty) {
          yield ReasoningDelta(reasoning);
        }
        final text = asString(delta['content']);
        if (text != null) yield* Stream.fromIterable(think.add(text));
        for (final rawPart in asList(delta['content']) ?? <Object?>[]) {
          final part = asMap(rawPart);
          if (part == null) continue;
          if (part['type'] == 'text') {
            final text = asString(part['text']);
            if (text != null) yield* Stream.fromIterable(think.add(text));
          } else if (part['type'] == 'image_url' || part['type'] == 'image') {
            final image = _image(part, images);
            if (image != null) yield image;
          }
        }
        for (final rawImage in asList(delta['images']) ?? <Object?>[]) {
          final image = _image(rawImage, images);
          if (image != null) yield image;
        }
        // Final message images can accompany an otherwise empty delta.
        if (choice['delta'] != null) {
          for (final rawImage
              in asList(asMap(choice['message'])?['images']) ?? <Object?>[]) {
            final image = _image(rawImage, images);
            if (image != null) yield image;
          }
        }
        final refusal = asString(delta['refusal']);
        if (refusal != null && refusal.isNotEmpty) yield TextDelta(refusal);
        for (final rawCall in asList(delta['tool_calls']) ?? []) {
          final tool = asMap(rawCall);
          if (tool == null) continue;
          final index = asInt(tool['index']) ?? 0;
          final call = calls.putIfAbsent(index, _Call.new);
          call.id = asString(tool['id']) ?? call.id;
          final function = asMap(tool['function']);
          final nameFragment = asString(function?['name']) ?? '';
          call.name += nameFragment;
          if (call.id.isNotEmpty &&
              call.name.isNotEmpty &&
              (!call.started || nameFragment.isNotEmpty)) {
            call.started = true;
            yield ToolCallStart(call.id, call.name);
          }
          final args = asString(function?['arguments']);
          if (args != null && args.isNotEmpty) {
            if (!call.started) {
              throw const ProviderError(
                'Provider returned an invalid tool call',
                code: 'invalid_stream',
              );
            }
            yield ToolCallArgsDelta(call.id, args);
          }
        }
      }
    }
    if (finishReason != null) {
      yield* Stream.fromIterable(think.add('', finish: true));
      for (final call in calls.values) {
        if (!call.started) yield ToolCallStart(call.id, call.name);
        yield ToolCallEnd(call.id);
      }
      yield _terminalEvent(finishReason);
    }
  }

  GeneratedImage? _image(Object? value, Set<String> images) {
    final item = asMap(value);
    final url =
        asString(asMap(item?['image_url'])?['url']) ??
        asString(item?['image_url']) ??
        asString(asMap(item?['image'])?['url']) ??
        asString(item?['url']);
    if (url == null || url.isEmpty) {
      throw const ProviderError(
        'Provider returned an image without image data',
        code: 'invalid_image',
      );
    }
    if (!url.startsWith('data:')) {
      throw const ProviderError(
        'Chat image output requires a base64 data URL; remote image URLs are not supported',
        code: 'unsupported_image_url',
      );
    }
    final key = sha256.convert(utf8.encode(url)).toString();
    if (!images.add(key)) return null;
    return generatedImageFromDataUrl(url, alt: asString(item?['alt']));
  }
}

ProviderEvent _terminalEvent(String? reason) =>
    reason == 'length' || reason == 'content_filter'
    ? ProviderError(
        'Provider response is incomplete: $reason',
        code: 'incomplete_response',
      )
    : Done(reason ?? 'stop');

class _Call {
  String id = '';
  String name = '';
  bool started = false;
}
