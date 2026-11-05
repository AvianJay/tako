import 'dart:convert';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

/// A request body was larger than its route allows.
final class BodyTooLarge implements Exception {
  const BodyTooLarge(this.limit);
  final int limit;
}

/// Reads a UTF-8 body, failing as soon as it passes [maxBytes], so a client
/// cannot make the server buffer an unbounded upload.
Future<String> readBody(Request request, int maxBytes) async {
  if ((request.contentLength ?? 0) > maxBytes) throw BodyTooLarge(maxBytes);
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in request.read()) {
    bytes.add(chunk);
    if (bytes.length > maxBytes) throw BodyTooLarge(maxBytes);
  }
  return utf8.decode(bytes.takeBytes());
}
