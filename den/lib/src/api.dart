import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'body.dart';

final class ApiException implements Exception {
  const ApiException(this.status, this.code);
  final int status;
  final String code;
}

Never fail(int status, String code) => throw ApiException(status, code);

Response json(Object? value, {int status = 200}) => Response(
  status,
  body: jsonEncode(value),
  headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
);

Response error(
  int status,
  String code, {
  String? message,
  Map<String, String>? headers,
}) => Response(
  status,
  body: jsonEncode({
    'error': {
      'code': code,
      'message': message ?? '${code.replaceAll('_', ' ')}.',
    },
  }),
  headers: {
    'content-type': 'application/json',
    'cache-control': 'no-store',
    ...?headers,
  },
);

Future<Map<String, Object?>> body(Request request, {int max = 65536}) async {
  final value = jsonDecode(await readBody(request, max));
  if (value is! Map<String, Object?>) fail(400, 'invalid_json');
  return value;
}

String string(
  Map<String, Object?> value,
  String key, {
  String? fallback,
  int max = 4096,
}) {
  final item = value[key];
  if (!value.containsKey(key) && fallback != null) return fallback;
  if (item is! String || item.length > max) fail(400, 'invalid_request');
  return item;
}

bool boolean(Map<String, Object?> value, String key, {bool fallback = true}) {
  if (!value.containsKey(key)) return fallback;
  if (value[key] is! bool) fail(400, 'invalid_request');
  return value[key] as bool;
}

List<String> strings(Object? value) {
  if (value is! List ||
      value.length > 1000 ||
      value.any((v) => v is! String || v.isEmpty || v.length > 512)) {
    fail(400, 'invalid_request');
  }
  return value.cast<String>();
}

String iso(int millis) =>
    DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toIso8601String();
int now() => DateTime.now().millisecondsSinceEpoch;
String today() => DateTime.now().toUtc().toIso8601String().substring(0, 10);

Uri httpUrl(String value, {bool httpsOnly = false}) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      uri.hasQuery ||
      !(httpsOnly ? ['https'] : ['http', 'https']).contains(uri.scheme)) {
    fail(400, 'invalid_url');
  }
  return uri;
}

String localReturn(String? value) {
  final path = value ?? '/';
  // Reject browser normalization and encoded separators as well as //host.
  if (!path.startsWith('/') ||
      path.startsWith('//') ||
      RegExp(
        r'[\\\x00-\x20\x7f]|%(?:2f|5c|0[0-9a-f]|1[0-9a-f]|7f)',
        caseSensitive: false,
      ).hasMatch(path)) {
    fail(400, 'invalid_return');
  }
  return path;
}
