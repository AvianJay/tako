import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../chat/content_block.dart';
import '../../chat/message.dart';
import '../../util/json.dart';
import '../cancel_token.dart';
import '../provider_adapter.dart';
import '../provider_config.dart';
import '../provider_event.dart';
import '../sse.dart';
import 'generated_image.dart';

/// OpenAI-compatible Images API. Image models use only the newest user turn;
/// references are uploaded as bytes, never interpreted as local or remote paths.
class ImagesAdapter extends HttpProviderAdapter {
  ImagesAdapter(
    super.config, {
    super.apiKey,
    super.secretHeaders,
    super.clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() _clientFactory;
  static const _generationTimeout = Duration(minutes: 5);
  bool get _xaiImages => Uri.tryParse(config.baseUrl)?.host == 'api.x.ai';

  @override
  String get endpoint => 'images/generations';

  ChatMessage _userMessage(ChatRequest request) {
    final message = request.messages.reversed
        .where((message) => message.role == MessageRole.user)
        .firstOrNull;
    if (message == null) {
      throw const ProviderError(
        'Enter an image prompt',
        code: 'invalid_request',
      );
    }
    return message;
  }

  @override
  JsonMap buildBody(ChatRequest request) {
    final prompt = _userMessage(request).content
        .whereType<TextBlock>()
        .map((block) => block.text)
        .join('\n')
        .trim();
    if (prompt.isEmpty) {
      throw const ProviderError(
        'Enter an image prompt',
        code: 'invalid_request',
      );
    }
    // Do not force response_format: GPT Image rejects that legacy parameter.
    return {
      'model': config.model,
      'prompt': prompt,
      'n': 1,
      if (_xaiImages) 'response_format': 'b64_json',
    };
  }

  @override
  Stream<ProviderEvent> decode(Stream<SseEvent> events) =>
      throw UnsupportedError('Images API uses a JSON response');

  http.BaseRequest _outgoing(ChatRequest request, CancelToken cancel) {
    final body = buildBody(request);
    final references = _userMessage(
      request,
    ).content.whereType<ImageBlock>().toList();
    if (references.isNotEmpty && !config.capabilities.imageReferenceInput) {
      throw const ProviderError(
        'This image model does not support reference images',
        code: 'unsupported_image_input',
      );
    }
    final maxReferences = _xaiImages ? 5 : 16;
    if (references.length > maxReferences) {
      throw ProviderError(
        'Use at most $maxReferences reference images',
        code: 'invalid_request',
      );
    }
    if (references.isEmpty) {
      return http.AbortableRequest(
          'POST',
          providerEndpoint(config.baseUrl, endpoint),
          abortTrigger: cancel.whenCancelled,
        )
        ..followRedirects = false
        ..headers.addAll({
          ...headers,
          'accept': 'application/json',
          'content-type': 'application/json',
        })
        ..body = jsonEncode(body);
    }
    // xAI uses JSON data URIs for edits, rather than OpenAI's multipart upload.
    if (_xaiImages) {
      var totalBytes = 0;
      final images = <JsonMap>[];
      for (final reference in references) {
        if (reference.data == null) {
          throw const ProviderError(
            'Reference image could not be loaded',
            code: 'invalid_image',
          );
        }
        final image = generatedImageFromBase64(
          reference.data!,
          mimeType: reference.mimeType,
        );
        totalBytes += base64Decode(image.base64).length;
        if (totalBytes > 4 * maxGeneratedImageBytes) {
          throw const ProviderError(
            'Reference images exceed the 80 MB request limit',
            code: 'invalid_image',
          );
        }
        images.add({
          'type': 'image_url',
          'url': 'data:${image.mimeType};base64,${image.base64}',
        });
      }
      return http.AbortableRequest(
          'POST',
          providerEndpoint(config.baseUrl, 'images/edits'),
          abortTrigger: cancel.whenCancelled,
        )
        ..followRedirects = false
        ..headers.addAll({
          ...headers,
          'accept': 'application/json',
          'content-type': 'application/json',
        })
        ..body = jsonEncode({
          ...body,
          if (images.length == 1) 'image': images.single else 'images': images,
        });
    }
    final outgoing =
        http.AbortableMultipartRequest(
            'POST',
            providerEndpoint(config.baseUrl, 'images/edits'),
            abortTrigger: cancel.whenCancelled,
          )
          ..followRedirects = false
          ..headers.addAll({...headers, 'accept': 'application/json'})
          ..fields.addAll(body.map((key, value) => MapEntry(key, '$value')));
    outgoing.headers.remove('content-type');
    var totalBytes = 0;
    for (var i = 0; i < references.length; i++) {
      final reference = references[i];
      if (reference.data == null) {
        throw const ProviderError(
          'Reference image could not be loaded',
          code: 'invalid_image',
        );
      }
      final image = generatedImageFromBase64(
        reference.data!,
        mimeType: reference.mimeType,
      );
      final bytes = base64Decode(image.base64);
      totalBytes += bytes.length;
      if (totalBytes > 4 * maxGeneratedImageBytes) {
        throw const ProviderError(
          'Reference images exceed the 80 MB request limit',
          code: 'invalid_image',
        );
      }
      final extension = image.mimeType.split('/').last;
      outgoing.files.add(
        http.MultipartFile.fromBytes(
          references.length == 1 ? 'image' : 'image[]',
          bytes,
          filename: 'reference-${i + 1}.$extension',
          contentType: http.MediaType.parse(image.mimeType),
        ),
      );
    }
    return outgoing;
  }

  @override
  Stream<ProviderEvent> send(
    ChatRequest request, {
    required CancelToken cancel,
  }) async* {
    if (cancel.isCancelled) return;
    final client = _clientFactory();
    cancel.addListener(client.close);
    try {
      final outgoing = _outgoing(request, cancel);
      final response = await cancel.bind(
        client.send(outgoing).timeout(_generationTimeout),
      );
      final success = response.statusCode >= 200 && response.statusCode < 300;
      final bytes = await readImageResponseBytes(
        response,
        cancel: cancel,
        maxBytes: success ? 32 * 1024 * 1024 : 1024 * 1024,
        idleTimeout: _generationTimeout,
      );
      final payload = tryDecodeObject(utf8.decode(bytes, allowMalformed: true));
      if (!success || payload?['error'] != null) {
        yield providerError(payload, statusCode: response.statusCode);
        return;
      }
      final results = asList(payload?['data']);
      if (results == null || results.isEmpty || results.length > 10) {
        throw const ProviderError(
          'Provider returned no valid generated images',
          code: 'invalid_image',
        );
      }
      for (final result in results) {
        cancel.throwIfCancelled();
        final data = asMap(result);
        final base64 = asString(data?['b64_json']);
        final url = asString(data?['url']);
        final revisedPrompt = asString(data?['revised_prompt']);
        final alt = revisedPrompt == null ? null : redact(revisedPrompt);
        if (base64?.isNotEmpty == true) {
          final format = asString(payload?['output_format']);
          yield generatedImageFromBase64(
            base64!,
            mimeType: format == null ? null : 'image/$format',
            alt: alt,
          );
        } else if (url?.isNotEmpty == true) {
          final downloadClient = _clientFactory();
          cancel.addListener(downloadClient.close);
          try {
            yield await downloadGeneratedImage(
              url!,
              client: downloadClient,
              cancel: cancel,
              alt: alt,
            );
          } finally {
            cancel.removeListener(downloadClient.close);
            downloadClient.close();
          }
        } else {
          throw const ProviderError(
            'Provider returned invalid image data',
            code: 'invalid_image',
          );
        }
      }
      final usage = asMap(payload?['usage']);
      if (usage != null) {
        yield Usage(
          inputTokens: asInt(usage['input_tokens']),
          outputTokens: asInt(usage['output_tokens']),
          totalTokens: asInt(usage['total_tokens']),
        );
      }
      if (!cancel.isCancelled) yield const Done('stop');
    } on RequestCancelled {
      // Stop is a user action, not a provider failure.
    } on ProviderError catch (error) {
      if (!cancel.isCancelled) {
        yield ProviderError(
          redact(error.message),
          statusCode: error.statusCode,
          code: error.code,
        );
      }
    } on TimeoutException {
      if (!cancel.isCancelled) {
        yield const ProviderError(
          'Image generation timed out',
          code: 'timeout',
        );
      }
    } on FormatException {
      if (!cancel.isCancelled) {
        yield const ProviderError(
          'Invalid provider URL or image response',
          code: 'invalid_data',
        );
      }
    } catch (_) {
      if (!cancel.isCancelled) {
        // Never expose client exceptions: they may include signed URLs or headers.
        yield const ProviderError(
          'Could not complete image generation. Check the connection and provider.',
          code: 'network',
        );
      }
    } finally {
      cancel.removeListener(client.close);
      client.close();
    }
  }
}
