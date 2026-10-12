import 'dart:convert';

/// Small helpers for reading loosely typed JSON without throwing.
typedef JsonMap = Map<String, Object?>;

JsonMap? asMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.map((k, v) => MapEntry('$k', v));
  return null;
}

List<Object?>? asList(Object? value) => value is List ? value : null;

String? asString(Object? value) => value is String ? value : null;

int? asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

bool? asBool(Object? value) => value is bool ? value : null;

/// Decodes [source] as a JSON object, or returns null if it is not one.
JsonMap? tryDecodeObject(String source) {
  try {
    return asMap(jsonDecode(source));
  } on FormatException {
    return null;
  }
}
