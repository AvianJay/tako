import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/web/web_links.dart';
import 'package:tako/ui/render/message_markdown.dart';
import 'package:tako/ui/render/web_embeds.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

/// Records every request a preview makes.
class FakeWeb {
  final previews = <Uri>[];
  final images = <Uri>[];
  final tiles = <(int, int, int)>[];
  final loaded = <String>{};

  WebEmbeds embeds({bool autoLoad = false, Set<String> trusted = const {}}) =>
      WebEmbeds(
        preview: (uri) async {
          previews.add(uri);
          return const LinkPreview(title: 'Page title', description: 'Summary');
        },
        image: (uri) async {
          images.add(uri);
          return Uint8List.fromList(_png);
        },
        tile: (zoom, x, y) async {
          tiles.add((zoom, x, y));
          return Uint8List.fromList(_png);
        },
        autoLoad: autoLoad,
        trusted: trusted.contains,
        loaded: loaded,
      );
}

Widget host(
  String data, {
  WebEmbeds? web,
  bool visuals = true,
  ValueChanged<Uri>? onLink,
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: SizedBox(
        width: 360,
        child: MessageMarkdown(
          data: data,
          copyLabel: 'Copy code',
          imageLabel: 'Image',
          fileLabel: 'File',
          visuals: visuals,
          web: web,
          onLink: onLink,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('a link alone becomes a card that loads only when tapped', (
    tester,
  ) async {
    final web = FakeWeb();
    await tester.pumpWidget(
      host('Read this:\n\nhttps://example.com/post', web: web.embeds()),
    );
    expect(find.byType(LinkPreviewCard), findsOneWidget);
    expect(find.text('https://example.com/post'), findsOneWidget);
    expect(find.text('example.com'), findsOneWidget);
    expect(web.previews, isEmpty);

    await tester.tap(find.text('Load preview'));
    await tester.pumpAndSettle();
    expect(web.previews, [Uri.parse('https://example.com/post')]);
    expect(find.text('Page title'), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
    expect(web.loaded, {'https://example.com/post'});

    // Loaded once, it stays loaded in a new view of the same reply.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      host('Read this:\n\nhttps://example.com/post', web: web.embeds()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Page title'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('automatic loading trusts only links the model did not invent', (
    tester,
  ) async {
    final web = FakeWeb();
    await tester.pumpWidget(
      host(
        'https://example.com/made-up\n\n[Found](https://example.com/found)',
        web: web.embeds(autoLoad: true, trusted: {'https://example.com/found'}),
      ),
    );
    await tester.pumpAndSettle();
    expect(web.previews, [Uri.parse('https://example.com/found')]);
    expect(find.text('Load preview'), findsOneWidget);

    // Video thumbnails come from YouTube itself, so they need no trust.
    await tester.pumpWidget(
      host('https://youtu.be/dQw4w9WgXcQ', web: web.embeds(autoLoad: true)),
    );
    await tester.pumpAndSettle();
    expect(web.previews.last, Uri.parse('https://youtu.be/dQw4w9WgXcQ'));
    expect(find.byIcon(Icons.play_circle_fill), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web images wait for a tap, then load', (tester) async {
    final web = FakeWeb();
    await tester.pumpWidget(
      host('Look ![A cat](https://example.com/cat.png)', web: web.embeds()),
    );
    expect(find.text('A cat'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    await tester.tap(find.text('A cat'));
    await tester.pumpAndSettle();
    expect(web.images, [Uri.parse('https://example.com/cat.png')]);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('places show a map on request and open the maps app', (
    tester,
  ) async {
    final web = FakeWeb();
    final opened = <Uri>[];
    await tester.pumpWidget(
      host(
        '[Taipei 101](geo:25.0340,121.5645)',
        web: web.embeds(),
        onLink: opened.add,
      ),
    );
    expect(find.text('Taipei 101'), findsOneWidget);
    expect(find.text('25.03400, 121.56450'), findsOneWidget);
    expect(web.tiles, isEmpty);
    await tester.tap(find.text('Load map'));
    await tester.pumpAndSettle();
    expect(web.tiles, isNotEmpty);
    expect(web.tiles.map((tile) => tile.$1).toSet(), hasLength(1));
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    await tester.tap(find.text('Taipei 101'));
    expect(opened, [Uri.parse('geo:25.0340,121.5645')]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('links in sentences, footnotes and user messages stay links', (
    tester,
  ) async {
    final web = FakeWeb();
    for (final data in [
      'See https://example.com/post for more.',
      'Claim[^1].\n\n[^1]: https://example.com/post',
    ]) {
      await tester.pumpWidget(host(data, web: web.embeds()));
      expect(find.byType(LinkPreviewCard), findsNothing, reason: data);
    }
    await tester.pumpWidget(
      host('https://example.com/post', web: web.embeds(), visuals: false),
    );
    expect(find.byType(LinkPreviewCard), findsNothing);
    await tester.pumpWidget(host('https://example.com/post'));
    expect(find.byType(LinkPreviewCard), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
