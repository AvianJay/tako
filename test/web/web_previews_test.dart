import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tako/core/web/web_previews.dart';

void main() {
  test('page previews come from Open Graph tags, then the title', () async {
    final requests = <http.Request>[];
    final previews = WebPreviews(
      clientFactory: () => MockClient((request) async {
        requests.add(request);
        return http.Response(
          '<html><head><title>Fallback</title>'
          '<meta property="og:title" content="  The   title ">'
          '<meta name="description" content="What it says">'
          '<meta property="og:site_name" content="Example">'
          '<meta property="og:image" content="/cover.png">'
          '</head><body>${'x' * 1000}</body></html>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }),
    );
    final preview = (await previews.preview(
      Uri.parse('https://example.com/post/1'),
    ))!;
    expect(preview.title, 'The title');
    expect(preview.description, 'What it says');
    expect(preview.siteName, 'Example');
    expect(preview.image, Uri.parse('https://example.com/cover.png'));
    expect(requests.single.headers['User-Agent'], WebPreviews.userAgent);

    // Cached for the session.
    await previews.preview(Uri.parse('https://example.com/post/1'));
    expect(requests, hasLength(1));
  });

  test('YouTube links are summarised by oEmbed', () async {
    final previews = WebPreviews(
      clientFactory: () => MockClient((request) async {
        expect(request.url.host, 'www.youtube.com');
        expect(request.url.path, '/oembed');
        expect(
          request.url.queryParameters['url'],
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        );
        return http.Response(
          jsonEncode({'title': 'A video', 'author_name': 'A channel'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final preview = (await previews.preview(
      Uri.parse('https://youtu.be/dQw4w9WgXcQ'),
    ))!;
    expect((preview.title, preview.siteName), ('A video', 'A channel'));
    expect(
      preview.image,
      Uri.parse('https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg'),
    );
  });

  test('private hosts and wrong content are refused, and retried', () async {
    var calls = 0;
    var type = 'text/html';
    final previews = WebPreviews(
      clientFactory: () => MockClient((request) async {
        calls++;
        return http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'content-type': type},
        );
      }),
    );
    for (final address in [
      'http://192.168.1.1/admin.png',
      'http://localhost/x.png',
      'https://printer.local/x.png',
      'file:///etc/passwd',
    ]) {
      await expectLater(
        previews.image(Uri.parse(address)),
        throwsA(anything),
        reason: address,
      );
    }
    expect(calls, 0);

    final image = Uri.parse('https://example.com/a.png');
    await expectLater(previews.image(image), throwsA(anything));
    type = 'image/png';
    expect(await previews.image(image), [1, 2, 3]);
    expect(calls, 2);
  });

  test('map tiles identify the app and are kept on disk', () async {
    final directory = await Directory.systemTemp.createTemp('tiles');
    addTearDown(() => directory.delete(recursive: true));
    final urls = <Uri>[];
    WebPreviews previews() => WebPreviews(
      cacheDirectory: () async => directory,
      clientFactory: () => MockClient((request) async {
        urls.add(request.url);
        expect(request.headers['User-Agent'], WebPreviews.userAgent);
        return http.Response.bytes(
          [9],
          200,
          headers: {'content-type': 'image/png'},
        );
      }),
    );
    expect(await previews().tile(16, 54897, 28058), [9]);
    // A new session reads the tile from disk.
    expect(await previews().tile(16, 54897, 28058), [9]);
    expect(urls, [
      Uri.parse('https://tile.openstreetmap.org/16/54897/28058.png'),
    ]);
  });
}
