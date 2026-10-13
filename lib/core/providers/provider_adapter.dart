import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../chat/content_block.dart';
import '../chat/message.dart';
import '../on_device/on_device_capability.dart';
import '../util/json.dart';
import 'cancel_token.dart';
import 'chat_completions/chat_completions_adapter.dart';
import 'images/images_adapter.dart';
import 'messages/messages_adapter.dart';
import 'on_device/on_device_adapter.dart';
import 'provider_config.dart';
import 'provider_event.dart';
import 'responses/responses_adapter.dart';
import 'sse.dart';

class ChatRequest {
  const ChatRequest({
    required this.systemPrompt,
    required this.messages,
    this.tools = const [],
    this.maxTokens,
    this.promptHash,
    this.replayOpaqueReasoning = true,
    this.builtInWebSearch = false,
    this.forceBuiltInWebSearch = false,
  });
  final String systemPrompt;
  final List<ChatMessage> messages;
  final List<ToolDefinition> tools;
  final int? maxTokens;
  final String? promptHash;

  /// Disable when trimming or otherwise rewriting the preceding history.
  final bool replayOpaqueReasoning;

  /// Granted by PermissionGate for this request; configuration alone never
  /// enables a provider-executed search.
  final bool builtInWebSearch;

  /// Used only for an explicit capability probe. Still requires the normal
  /// search grant, model capability and endpoint checks.
  final bool forceBuiltInWebSearch;
}

/// Official APIs are supported automatically; compatible custom endpoints
/// require an explicit per-model opt-in. URL validation always applies.
bool supportsBuiltInWebSearch(ProviderConfig config) {
  final endpoint = switch (config.apiType) {
    ApiType.responses => 'responses',
    ApiType.messages => 'messages',
    _ => null,
  };
  if (endpoint == null) return false;
  try {
    final uri = providerEndpoint(config.baseUrl, endpoint);
    if (config.capabilities.allowCustomSearchEndpoint) return true;
    return uri.scheme == 'https' &&
        uri.port == 443 &&
        uri.path == '/v1/$endpoint' &&
        uri.host ==
            (config.apiType == ApiType.responses
                ? 'api.openai.com'
                : 'api.anthropic.com');
  } on FormatException {
    return false;
  }
}

/// Citation titles/URLs are untrusted provider data, escaped as ordinary links.
String? providerCitationLink(Object? value) {
  final citation = asMap(value);
  final url = asString(citation?['url']);
  if (url == null ||
      url.length > 8192 ||
      url.codeUnits.any((unit) => unit <= 32)) {
    return null;
  }
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !{'https', 'http'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  var title = (asString(citation?['title']) ?? uri.host)
      .replaceAll(RegExp(r'[\r\n\t]'), ' ')
      .trim();
  if (title.isEmpty) title = uri.host;
  if (title.length > 200) title = title.substring(0, 200);
  title = title.replaceAllMapped(
    RegExp(r'[\\\[\]*_`<>]'),
    (match) => '\\${match[0]}',
  );
  final target = uri.toString().replaceAll('(', '%28').replaceAll(')', '%29');
  return ' [$title]($target)';
}

class ToolDefinition {
  const ToolDefinition({
    required this.name,
    required this.description,
    required this.schema,
  });
  final String name;
  final String description;
  final JsonMap schema;
}

class ModelInfo {
  const ModelInfo({required this.id, String? displayName})
    : displayName = displayName ?? id;
  final String id;
  final String displayName;
}

abstract class ProviderAdapter {
  factory ProviderAdapter.create(
    ProviderConfig config, {
    String? apiKey,
    Map<String, String> secretHeaders = const {},
    http.Client Function()? clientFactory,
    OnDeviceCapability? onDevice,
  }) {
    if (config.capabilities.imageGeneration == ImageGenerationMode.imagesApi &&
        (config.apiType == ApiType.chatCompletions ||
            config.apiType == ApiType.responses)) {
      return ImagesAdapter(
        config,
        apiKey: apiKey,
        secretHeaders: secretHeaders,
        clientFactory: clientFactory,
      );
    }
    return switch (config.apiType) {
      ApiType.onDevice => OnDeviceAdapter(
        config,
        onDevice ?? UnavailableOnDevice(),
      ),
      ApiType.chatCompletions => ChatCompletionsAdapter(
        config,
        apiKey: apiKey,
        secretHeaders: secretHeaders,
        clientFactory: clientFactory,
      ),
      ApiType.responses => ResponsesAdapter(
        config,
        apiKey: apiKey,
        secretHeaders: secretHeaders,
        clientFactory: clientFactory,
      ),
      ApiType.messages => MessagesAdapter(
        config,
        apiKey: apiKey,
        secretHeaders: secretHeaders,
        clientFactory: clientFactory,
      ),
    };
  }

  Stream<ProviderEvent> send(
    ChatRequest request, {
    required CancelToken cancel,
  });
  Future<List<ModelInfo>> listModels({CancelToken? cancel});
}

/// A separate client per request lets Stop abort the socket without affecting
/// another chat or the model picker. Redirects are deliberately disabled so that
/// a misconfigured provider cannot forward custom authorization headers elsewhere.
abstract class HttpProviderAdapter implements ProviderAdapter {
  HttpProviderAdapter(
    this.config, {
    String? apiKey,
    Map<String, String> secretHeaders = const {},
    http.Client Function()? clientFactory,
  }) : _apiKey = apiKey,
       _secretHeaders = secretHeaders,
       _clientFactory = clientFactory ?? http.Client.new;

  final ProviderConfig config;
  final String? _apiKey;
  final Map<String, String> _secretHeaders;
  final http.Client Function() _clientFactory;

  String get endpoint;
  JsonMap buildBody(ChatRequest request);
  Stream<ProviderEvent> decode(Stream<SseEvent> events);

  Map<String, String> get headers {
    final values = <String, String>{
      'content-type': 'application/json',
      'accept': 'text/event-stream',
      if (config.apiType == ApiType.messages) 'anthropic-version': '2023-06-01',
      if (_apiKey?.isNotEmpty ?? false)
        if (config.apiType == ApiType.messages)
          'x-api-key': _apiKey!
        else
          'authorization': 'Bearer $_apiKey',
    };
    for (final entry in {...config.extraHeaders, ..._secretHeaders}.entries) {
      values[entry.key.toLowerCase()] = entry.value;
    }
    return values;
  }

  String redact(String message) {
    var value = message;
    final secrets =
        <String>{
            if (_apiKey != null) _apiKey,
            ...config.extraHeaders.values,
            ..._secretHeaders.values,
            for (final value in {
              ...config.extraHeaders,
              ..._secretHeaders,
            }.values)
              if (value.toLowerCase().startsWith('bearer ')) value.substring(7),
          }.where((s) => s.isNotEmpty).toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    for (final secret in secrets) {
      value = value.replaceAll(secret, '[REDACTED]');
      value = value.replaceAll(Uri.encodeComponent(secret), '[REDACTED]');
    }
    value = value.replaceAll(RegExp(r'sk-[A-Za-z0-9_-]+'), '[REDACTED]');
    return value.length > 2000 ? '${value.substring(0, 2000)}…' : value;
  }

  ProviderError providerError(Object? payload, {int? statusCode}) {
    final root = asMap(payload);
    final error = asMap(root?['error']) ?? root;
    final message =
        asString(error?['message']) ??
        asString(root?['error']) ??
        'Provider request failed';
    return ProviderError(
      redact(message),
      statusCode: statusCode,
      code: switch (asString(error?['code']) ?? asString(error?['type'])) {
        final code? => redact(code),
        null => null,
      },
    );
  }

  JsonMap decodeEvent(SseEvent event) {
    final data = tryDecodeObject(event.data);
    if (data == null) {
      throw const ProviderError(
        'Provider returned malformed stream data',
        code: 'invalid_stream',
      );
    }
    return data;
  }

  http.AbortableRequest _request(
    String method,
    String endpoint,
    CancelToken cancel,
  ) =>
      http.AbortableRequest(
          method,
          providerEndpoint(config.baseUrl, endpoint),
          abortTrigger: cancel.whenCancelled,
        )
        ..followRedirects = false
        ..headers.addAll(headers);

  @override
  Stream<ProviderEvent> send(
    ChatRequest request, {
    required CancelToken cancel,
  }) async* {
    if (cancel.isCancelled) return;
    final client = _clientFactory();
    cancel.addListener(client.close);
    try {
      final outgoing = _request('POST', endpoint, cancel)
        ..body = jsonEncode(buildBody(request));
      final response = await cancel.bind(
        client
            .send(outgoing)
            .timeout(
              config.capabilities.imageGeneration == ImageGenerationMode.none
                  ? const Duration(seconds: 45)
                  : const Duration(minutes: 5),
            ),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await cancel.bind(
          _readLimited(_cancelable(response.stream, cancel)),
        );
        final parsed = tryDecodeObject(body);
        yield parsed == null
            ? ProviderError(
                redact(body.isEmpty ? 'Provider request failed' : body),
                statusCode: response.statusCode,
              )
            : providerError(parsed, statusCode: response.statusCode);
        return;
      }
      var terminal = false;
      await for (final event in decode(
        parseSse(_cancelable(response.stream, cancel)),
      )) {
        if (cancel.isCancelled) return;
        if (event is ProviderError) {
          terminal = true;
          yield ProviderError(
            redact(event.message),
            statusCode: event.statusCode,
            code: event.code,
          );
          return;
        }
        yield event is GeneratedImage
            ? GeneratedImage(
                base64: event.base64,
                mimeType: event.mimeType,
                alt: event.alt == null ? null : redact(event.alt!),
              )
            : event;
        if (event is Done) {
          terminal = true;
          break;
        }
      }
      if (!terminal && !cancel.isCancelled) {
        yield const ProviderError(
          'Provider stream ended before completion',
          code: 'incomplete_stream',
        );
      }
    } on RequestCancelled {
      // Cancellation is a user action, not an error.
    } on http.RequestAbortedException {
      if (!cancel.isCancelled) {
        yield const ProviderError(
          'Provider request was interrupted',
          code: 'network',
        );
      }
    } on ProviderError catch (error) {
      if (!cancel.isCancelled) {
        yield ProviderError(
          redact(error.message),
          statusCode: error.statusCode,
          code: error.code,
        );
      }
    } on FormatException {
      if (!cancel.isCancelled) {
        yield const ProviderError(
          'Invalid provider URL or response data',
          code: 'invalid_data',
        );
      }
    } on TimeoutException {
      if (!cancel.isCancelled) {
        yield const ProviderError(
          'Provider connection timed out',
          code: 'timeout',
        );
      }
    } catch (_) {
      // Client exceptions may contain full headers, URLs, or request contents.
      if (!cancel.isCancelled) {
        yield const ProviderError(
          'Could not reach the provider. Check the connection and URL.',
          code: 'network',
        );
      }
    } finally {
      cancel.removeListener(client.close);
      client.close();
    }
  }

  @override
  Future<List<ModelInfo>> listModels({CancelToken? cancel}) async {
    final token = cancel ?? CancelToken();
    token.throwIfCancelled();
    final client = _clientFactory();
    token.addListener(client.close);
    try {
      final request = _request('GET', 'models', token)
        ..headers['accept'] = 'application/json';
      final response = await token.bind(
        client.send(request).timeout(const Duration(seconds: 30)),
      );
      final body = await token.bind(
        _readLimited(_cancelable(response.stream, token)),
      );
      final payload = tryDecodeObject(body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw payload == null
            ? ProviderError(redact(body), statusCode: response.statusCode)
            : providerError(payload, statusCode: response.statusCode);
      }
      if (payload == null || payload['data'] is! List) {
        throw const ProviderError(
          'Provider returned an invalid model list',
          code: 'invalid_data',
        );
      }
      final models = <String, ModelInfo>{};
      for (final item in asList(payload['data'])!) {
        final data = asMap(item);
        final id = asString(data?['id']);
        if (id != null && id.isNotEmpty) {
          models[id] = ModelInfo(
            id: id,
            displayName: asString(data?['display_name']),
          );
        }
      }
      return models.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    } on ProviderError {
      rethrow;
    } on RequestCancelled {
      rethrow;
    } catch (_) {
      token.throwIfCancelled();
      throw const ProviderError(
        'Could not load models. Check the connection or enter a model manually.',
        code: 'network',
      );
    } finally {
      token.removeListener(client.close);
      client.close();
    }
  }

  bool canReplayReasoning(
    ChatMessage message,
    ReasoningBlock block,
    ChatRequest request,
  ) =>
      request.replayOpaqueReasoning &&
      message.status == MessageStatus.done &&
      block.sourceApi == config.apiType.name &&
      (message.providerId == null || message.providerId == config.id) &&
      (message.model == null || message.model == config.model) &&
      block.promptHash == request.promptHash;
}

Future<String> _readLimited(Stream<List<int>> source) async {
  final bytes = <int>[];
  await for (final chunk in source.timeout(const Duration(seconds: 30))) {
    if (bytes.length + chunk.length > 1024 * 1024) {
      throw const ProviderError(
        'Provider response is too large',
        code: 'invalid_data',
      );
    }
    bytes.addAll(chunk);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

Stream<List<int>> _cancelable(Stream<List<int>> source, CancelToken token) {
  late StreamController<List<int>> controller;
  StreamSubscription<List<int>>? subscription;
  void cancelled() {
    unawaited(subscription?.cancel());
    unawaited(controller.close());
  }

  controller = StreamController<List<int>>(
    onListen: () {
      subscription = source.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      token.addListener(cancelled);
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () async {
      token.removeListener(cancelled);
      await subscription?.cancel();
    },
  );
  return controller.stream;
}

List<ContentBlock> requestBlocks(ChatMessage message) => [
  if (message.role == MessageRole.user &&
      message.contextEnvelope?.isNotEmpty == true)
    TextBlock('${message.contextEnvelope}\n'),
  ...message.content,
];

String? imageUrl(ImageBlock image) => image.data != null
    ? 'data:${image.mimeType};base64,${image.data}'
    : Uri.tryParse(image.path)?.scheme == 'https'
    ? image.path
    : null;
