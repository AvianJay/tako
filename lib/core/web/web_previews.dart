import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../providers/cancel_token.dart';
import '../search/search_service.dart';
import '../util/json.dart';
import 'web_links.dart';

/// Fetches what previews in replies show: page summaries, images, video
/// details and map tiles. The chat only asks after the user tapped a
/// preview or turned on automatic loading, and no host on the private
/// network is ever contacted.
class WebPreviews {
  WebPreviews({http.Client Function()? clientFactory, this.cacheDirectory})
    : _clientFactory = clientFactory ?? http.Client.new;

  /// Identifies the app, as the map tile server's usage policy requires.
  static const userAgent = 'Tako (+https://github.com/AvianJay/tako)';
  static const tileServer = 'https://tile.openstreetmap.org';

  final http.Client Function() _clientFactory;

  /// Where map tiles are kept for a week, as the tile server asks. Without
  /// one, tiles are cached in memory only.
  final Future<Directory?> Function()? cacheDirectory;

  /// Links the user loaded in this session. They stay loaded when the
  /// message scrolls away and back.
  final loaded = <String>{};

  final _previews = _Lru<Future<LinkPreview?>>(200);
  final _images = _Lru<Future<Uint8List>>(64);

  /// A summary of the page at [uri], or null when it has none. YouTube
  /// links are summarised from YouTube's oEmbed endpoint.
  Future<LinkPreview?> preview(Uri uri) =>
      _cached(_previews, '$uri', () => _preview(uri));

  Future<Uint8List> image(Uri uri) => _cached(
    _images,
    '$uri',
    () => _fetch(
      uri,
      accept: 'image/*',
      types: const {
        'image/png',
        'image/jpeg',
        'image/jpg',
        'image/gif',
        'image/webp',
        'image/bmp',
        'application/octet-stream',
        'binary/octet-stream',
      },
      maxBytes: 8 * 1024 * 1024,
    ),
  );

  /// One OpenStreetMap tile.
  Future<Uint8List> tile(int zoom, int x, int y) =>
      _cached(_images, 'tile/$zoom/$x/$y', () => _tile(zoom, x, y));

  Future<T> _cached<T>(
    _Lru<Future<T>> cache,
    String key,
    Future<T> Function() load,
  ) {
    if (cache[key] case final cached?) return cached;
    final future = load();
    cache[key] = future;
    // A failed load is tried again next time instead of staying cached.
    future.then<void>(
      (_) {},
      onError: (Object _) {
        cache.remove(key);
      },
    );
    return future;
  }

  Future<LinkPreview?> _preview(Uri uri) async {
    if (youtubeId(uri) case final id?) {
      final details = tryDecodeObject(
        utf8.decode(
          await _fetch(
            Uri.https('www.youtube.com', '/oembed', {
              'url': 'https://www.youtube.com/watch?v=$id',
              'format': 'json',
            }),
            accept: 'application/json',
            types: const {'application/json'},
          ),
          allowMalformed: true,
        ),
      );
      return LinkPreview(
        title: _clip(asString(details?['title']), 200),
        siteName: _clip(asString(details?['author_name']), 100),
        image: youtubeThumbnail(id),
      );
    }
    final document = html.parse(
      utf8.decode(
        await _fetch(
          uri,
          accept: 'text/html, application/xhtml+xml',
          types: const {'text/html', 'application/xhtml+xml'},
        ),
        allowMalformed: true,
      ),
    );
    String? meta(List<String> names) {
      for (final name in names) {
        for (final element in document.getElementsByTagName('meta')) {
          final key =
              element.attributes['property'] ?? element.attributes['name'];
          final content = element.attributes['content']?.trim();
          if (key?.toLowerCase() == name && (content?.isNotEmpty ?? false)) {
            return content;
          }
        }
      }
      return null;
    }

    final title = document.getElementsByTagName('title').firstOrNull?.text;
    final image = Uri.tryParse(
      meta([
            'og:image',
            'og:image:secure_url',
            'og:image:url',
            'twitter:image',
          ]) ??
          '',
    );
    final resolved = image == null || image.toString().isEmpty
        ? null
        : uri.resolveUri(image);
    final preview = LinkPreview(
      title: _clip(meta(['og:title', 'twitter:title']) ?? title, 200),
      description: _clip(
        meta(['og:description', 'description', 'twitter:description']),
        400,
      ),
      siteName: _clip(meta(['og:site_name', 'application-name']), 100),
      image: resolved != null && {'https', 'http'}.contains(resolved.scheme)
          ? resolved
          : null,
    );
    return preview.isEmpty ? null : preview;
  }

  Future<Uint8List> _tile(int zoom, int x, int y) async {
    File? file;
    try {
      if (await cacheDirectory?.call() case final directory?) {
        file = File(p.join(directory.path, 'map-tiles', '$zoom-$x-$y.png'));
        final stat = await file.stat();
        if (stat.type == FileSystemEntityType.file &&
            DateTime.now().difference(stat.modified) <
                const Duration(days: 7)) {
          return await file.readAsBytes();
        }
      }
    } on Object {
      file = null;
    }
    final bytes = await _fetch(
      Uri.parse('$tileServer/$zoom/$x/$y.png'),
      accept: 'image/png',
      types: const {'image/png'},
    );
    try {
      await file?.parent.create(recursive: true);
      await file?.writeAsBytes(bytes);
    } on Object {
      // The cache only saves requests; a failed write changes nothing else.
    }
    return bytes;
  }

  Future<Uint8List> _fetch(
    Uri uri, {
    required String accept,
    required Set<String> types,
    int maxBytes = 2 * 1024 * 1024,
  }) async {
    if (!{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        isPrivateWebUrl('$uri')) {
      throw const SearchFailure('invalid_url');
    }
    final (bytes, _) = await boundedBytes(
      uri,
      cancel: CancelToken(),
      clientFactory: _clientFactory,
      headers: {'Accept': accept, 'User-Agent': userAgent},
      allowedContentTypes: types,
      maxRedirects: 5,
      maxBytes: maxBytes,
    );
    return bytes;
  }
}

String? _clip(String? value, int length) {
  final text = value?.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text == null || text.isEmpty) return null;
  return text.length <= length ? text : '${text.substring(0, length - 1)}…';
}

/// A map that forgets its least recently used entries past [capacity].
class _Lru<V> {
  _Lru(this.capacity);

  final int capacity;
  final _entries = <String, V>{};

  V? operator [](String key) {
    final value = _entries.remove(key);
    if (value != null) _entries[key] = value;
    return value;
  }

  void operator []=(String key, V value) {
    _entries
      ..remove(key)
      ..[key] = value;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  void remove(String key) {
    _entries.remove(key);
  }
}
