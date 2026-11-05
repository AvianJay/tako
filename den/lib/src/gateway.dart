import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

import 'account_store.dart';
import 'api.dart';
import 'body.dart';
import 'config.dart';
import 'providers.dart';
import 'store.dart';

/// One gateway for shared and private providers; authorization precedes I/O.
final class Gateway {
  Gateway(this.upstreams, this.store, {http.Client? client})
    : _client = client ?? http.Client(),
      _injectedClient = client;
  final List<Upstream> upstreams;
  final Store store;
  final http.Client _client;
  final http.Client? _injectedClient;
  late Providers providers;
  late http.Client _ownClient;
  final _modelCache = <String, (DateTime, List<String>)>{};

  void configure(Providers value) {
    providers = value;
    _ownClient =
        _injectedClient ??
        value.guard.client(() => value.settings.allowPrivate);
  }

  void invalidate() {
    _modelCache.clear();
    if (_injectedClient == null) {
      _ownClient.close();
      _ownClient = providers.guard.client(
        () => providers.settings.allowPrivate,
      );
    }
  }

  Future<http.StreamedResponse> _send(
    Provider provider,
    String method,
    String path, {
    String? body,
    String? key,
  }) async {
    await providers.check(provider);
    key ??= await providers.key(provider);
    final request = http.Request(method, Uri.parse('${provider.baseUrl}/$path'))
      ..followRedirects = false;
    request.headers.addAll({
      'accept': 'application/json',
      if (key.isNotEmpty) 'authorization': 'Bearer $key',
    });
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = body;
    }
    return (provider.own ? _ownClient : _client)
        .send(request)
        .timeout(const Duration(seconds: 30));
  }

  Future<List<String>> _upstreamModels(
    Provider provider, {
    bool test = false,
  }) async {
    await providers.check(provider);
    if (!test && provider.models.isNotEmpty) return provider.models;
    final cacheKey =
        '${provider.ownerId}:${provider.id}:${provider.data['updatedAt']}';
    final cached = _modelCache[cacheKey];
    if (!test &&
        cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(minutes: 5)) {
      return cached.$2;
    }
    final response = await _send(provider, 'GET', 'models');
    if (response.statusCode != 200) {
      await response.stream.listen(null).cancel();
      throw StateError('Provider unavailable');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 15),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > 4 * 1024 * 1024) {
        throw StateError('Provider response too large');
      }
    }
    final value = jsonDecode(utf8.decode(bytes)) as Map;
    final models = [
      for (final item in value['data'] as List)
        if (item is Map && item['id'] is String) item['id'] as String,
    ]..sort();
    _modelCache[cacheKey] = (DateTime.now(), models);
    return models;
  }

  Future<Response> test(Provider provider) async {
    try {
      return json({
        'ok': true,
        'models': await _upstreamModels(provider, test: true),
      });
    } on ApiException {
      rethrow;
    } on Object {
      return json({
        'ok': false,
        'error': 'Provider unavailable or invalid response.',
      });
    }
  }

  Future<Response> models(User user) async {
    final entries = <Map<String, Object?>>[];
    for (final provider in providers.visible(user)) {
      try {
        for (final model in await _upstreamModels(provider)) {
          entries.add({
            'id': '${provider.prefix}$model',
            'object': 'model',
            'owned_by': provider.name,
          });
        }
      } on ApiException {
        rethrow;
      } on Object {
        /* A sleeping upstream must not hide the others. */
      }
    }
    return json({'object': 'list', 'data': entries});
  }

  Future<Response> chatCompletions(Request request, Device device) async {
    final value = jsonDecode(await readBody(request, 32 * 1024 * 1024));
    if (value is! Map<String, Object?> || value['model'] is! String) {
      fail(400, 'invalid_request');
    }
    final requested = value['model'] as String;
    final target = providers
        .visible(device.user)
        .where((p) => requested.startsWith(p.prefix))
        .firstOrNull;
    if (target == null) fail(404, 'model_not_found');
    final model = requested.substring(target.prefix.length);
    if (target.models.isNotEmpty && !target.models.contains(model)) {
      fail(404, 'model_not_found');
    }
    final configuredLimit = device.user.permissions['dailyTokenLimit'] as int?;
    final limit = configuredLimit == -1 ? null : configuredLimit;
    if (!target.own &&
        limit != null &&
        AccountStore(store).sharedToday(device.user) >= limit) {
      fail(429, 'quota_exceeded');
    }
    final http.StreamedResponse response;
    final String providerKey;
    try {
      providerKey = await providers.key(target);
      response = await _send(
        target,
        'POST',
        'chat/completions',
        body: jsonEncode({...value, 'model': model}),
        key: providerKey,
      );
    } on ApiException {
      rethrow;
    } on Object {
      fail(502, 'upstream_unreachable');
    }
    // Upstream diagnostics may contain credentials. Do not relay error bodies.
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = await _upstreamMessage(response, providerKey);
      final status = response.statusCode;
      if (status case 400 || 404 || 413 || 422) {
        return error(400, 'upstream_rejected', message: message);
      }
      if (status case 401 || 403) {
        return error(
          502,
          'upstream_auth',
          message: 'Upstream authentication failed.',
        );
      }
      if (status == 429) {
        return error(
          429,
          'upstream_rate_limited',
          message: 'Upstream rate limit reached.',
          headers: {'retry-after': ?response.headers['retry-after']},
        );
      }
      return error(
        502,
        'upstream_error',
        message: 'Upstream returned HTTP $status.',
      );
    }
    final meter = _UsageMeter();
    Stream<List<int>> stream() async* {
      try {
        await for (final chunk in response.stream) {
          meter.add(chunk);
          yield chunk;
        }
      } finally {
        if (store.userById(device.user.id) != null) {
          store.recordUsage(
            device.user,
            requested,
            inputTokens: meter.inputTokens,
            outputTokens: meter.outputTokens,
            shared: !target.own,
          );
        }
      }
    }

    return Response(
      response.statusCode,
      body: stream(),
      headers: {
        'content-type': response.headers['content-type'] ?? 'application/json',
        'cache-control': 'no-cache',
      },
      context: {'shelf.io.buffer_output': false},
    );
  }

  void close() {
    _client.close();
    if (_injectedClient == null) _ownClient.close();
  }
}

const _maxUpstreamErrorBytes = 64 * 1024;

Future<String> _upstreamMessage(
  http.StreamedResponse response,
  String providerKey,
) async {
  final bytes = <int>[];
  try {
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 15),
    )) {
      final remaining = _maxUpstreamErrorBytes - bytes.length;
      bytes.addAll(
        chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
      );
      if (bytes.length == _maxUpstreamErrorBytes) break;
    }
  } catch (_) {
    // Keep the status mapping even if the upstream stops sending its body.
  }

  String? message;
  try {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is Map) {
      final upstreamError = value['error'];
      if (upstreamError is Map && upstreamError['message'] is String) {
        message = upstreamError['message'] as String;
      } else if (value['message'] is String) {
        message = value['message'] as String;
      } else if (upstreamError is String) {
        message = upstreamError;
      }
    }
  } on Object {
    // A non-JSON body is intentionally replaced with a generic message.
  }
  var result = message ?? 'Upstream rejected the request.';
  if (providerKey.isNotEmpty) {
    for (final encoded in {
      Uri.encodeComponent(providerKey),
      Uri.encodeQueryComponent(providerKey),
    }) {
      result = result.replaceAll(
        RegExp(RegExp.escape(encoded), caseSensitive: false),
        '[REDACTED]',
      );
    }
    result = result.replaceAll(providerKey, '[REDACTED]');
  }
  result = result.replaceAll(
    RegExp(r'(?:sk-|tako_)[A-Za-z0-9_.-]+', caseSensitive: false),
    '[REDACTED]',
  );
  return result.length <= 500 ? result : result.substring(0, 500);
}

/// Recognizes the top-level usage object without retaining completion text.
final class _UsageMeter {
  int inputTokens = 0;
  int outputTokens = 0;
  int _depth = 0;
  bool _quoted = false;
  bool _escaped = false;
  String _word = '';
  int _candidate = 0;
  StringBuffer? _usage;
  int _usageDepth = 0;

  void add(List<int> chunk) {
    for (final byte in chunk) {
      final char = String.fromCharCode(byte);
      final capture = _usage;
      if (capture != null) {
        capture.write(char);
        if (capture.length > 65536) {
          _usage = null;
          _usageDepth = 0;
          _candidate = 0;
        }
      }
      if (_quoted) {
        if (_escaped) {
          _escaped = false;
        } else if (char == r'\') {
          _escaped = true;
        } else if (char == '"') {
          _quoted = false;
          if (_usage == null && _depth == 1 && _word == 'usage') _candidate = 1;
        } else if (_word.length < 64) {
          _word += char;
        }
        continue;
      }
      if (char == '"') {
        _quoted = true;
        _word = '';
        continue;
      }
      if (_usage != null) {
        if (char == '{' || char == '[') _usageDepth++;
        if (char == '}' || char == ']') _usageDepth--;
        if (_usageDepth == 0) {
          _read(_usage.toString());
          _usage = null;
          _candidate = 0;
        }
        continue;
      }
      if (_candidate > 0 && char.trim().isNotEmpty) {
        if (_candidate == 1 && char == ':') {
          _candidate = 2;
          continue;
        }
        if (_candidate == 2 && char == '{') {
          _usage = StringBuffer('{');
          _usageDepth = 1;
          _candidate = 0;
          continue;
        }
        _candidate = 0;
      }
      if (char == '{' || char == '[') _depth++;
      if (char == '}' || char == ']') _depth--;
    }
  }

  void _read(String value) {
    try {
      final usage = jsonDecode(value) as Map;
      final input = usage['prompt_tokens'];
      final output = usage['completion_tokens'];
      if (input is int && input >= 0) inputTokens = input;
      if (output is int && output >= 0) outputTokens = output;
    } on FormatException {
      // Incomplete or malformed upstream metadata cannot break the stream.
    }
  }
}
