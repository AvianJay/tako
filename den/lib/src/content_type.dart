import 'package:path/path.dart' as p;

String contentType(String path) => switch (p.extension(path).toLowerCase()) {
  '.html' => 'text/html; charset=utf-8',
  '.css' => 'text/css; charset=utf-8',
  '.js' || '.mjs' => 'text/javascript; charset=utf-8',
  '.json' || '.map' => 'application/json',
  '.svg' => 'image/svg+xml',
  '.png' => 'image/png',
  '.jpg' || '.jpeg' => 'image/jpeg',
  '.gif' => 'image/gif',
  '.webp' => 'image/webp',
  '.ico' => 'image/x-icon',
  '.woff' => 'font/woff',
  '.woff2' => 'font/woff2',
  '.wasm' => 'application/wasm',
  '.txt' => 'text/plain; charset=utf-8',
  '.webmanifest' => 'application/manifest+json',
  _ => 'application/octet-stream',
};
