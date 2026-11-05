import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import 'web_assets.g.dart';
import 'content_type.dart';

const webHeaders = {
  'content-security-policy':
      "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
  'referrer-policy': 'no-referrer',
  'x-content-type-options': 'nosniff',
};

/// The development root is resolved before access, including symlinks.
Response serveWeb(Request request, String? directory) {
  var path = request.url.pathSegments.join('/');
  if (path.isEmpty) path = 'index.html';
  if (directory == null) {
    final asset =
        webAssets[path] ??
        (p.extension(path).isEmpty ? webAssets['index.html'] : null);
    if (asset == null) return Response.notFound('Web app unavailable.');
    return Response.ok(
      base64.decode(asset.bytes),
      headers: {...webHeaders, 'content-type': asset.contentType},
    );
  }
  final root = Directory(directory).resolveSymbolicLinksSync();
  File? resolve(String path) {
    if (path.contains(r'\') ||
        path.split('/').any((v) => v == '..' || v == '.')) {
      return null;
    }
    final file = File(p.join(root, path));
    if (!file.existsSync()) return null;
    final resolved = file.resolveSymbolicLinksSync();
    return p.isWithin(root, resolved) ? File(resolved) : null;
  }

  final file =
      resolve(path) ??
      (p.extension(path).isEmpty ? resolve('index.html') : null);
  if (file == null) return Response.notFound('Web app unavailable.');
  final relative = p.relative(file.path, from: root).replaceAll(r'\', '/');
  final type = contentType(relative);
  return Response.ok(
    file.openRead(),
    headers: {...webHeaders, 'content-type': type},
  );
}
