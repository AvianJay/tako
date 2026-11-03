import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/browser/browser_settings.dart';
import 'package:tako/core/web/web_links.dart';

void main() {
  test('YouTube links of every shape name their video', () {
    for (final link in [
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42',
      'https://youtu.be/dQw4w9WgXcQ',
      'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
      'https://www.youtube.com/shorts/dQw4w9WgXcQ',
      'https://www.youtube.com/embed/dQw4w9WgXcQ',
      'https://music.youtube.com/watch?v=dQw4w9WgXcQ',
    ]) {
      expect(youtubeId(Uri.parse(link)), 'dQw4w9WgXcQ', reason: link);
    }
    for (final link in [
      'https://www.youtube.com/',
      'https://www.youtube.com/watch?v=short',
      'https://example.com/watch?v=dQw4w9WgXcQ',
      'ftp://youtu.be/dQw4w9WgXcQ',
    ]) {
      expect(youtubeId(Uri.parse(link)), isNull, reason: link);
    }
  });

  test('map links give coordinates, a search, or both', () {
    final geo = mapPoint(Uri.parse('geo:25.0340,121.5645'))!;
    expect((geo.latitude, geo.longitude, geo.query), (25.034, 121.5645, null));

    final named = mapPoint(
      Uri.parse('geo:0,0?q=25.0340,121.5645(${Uri.encodeComponent('台北101')})'),
    )!;
    expect((named.latitude, named.query), (25.034, '台北101'));

    final search = mapPoint(
      Uri.parse('geo:0,0?q=${Uri.encodeComponent('台北市信義路五段7號')}'),
    )!;
    expect((search.located, search.query), (false, '台北市信義路五段7號'));

    final google = mapPoint(
      Uri.parse(
        'https://www.google.com/maps/place/Taipei+101/@25.0339639,121.5644722,17z',
      ),
    )!;
    expect(
      (google.latitude, google.longitude, google.query),
      (25.0339639, 121.5644722, 'Taipei 101'),
    );
    final apple = mapPoint(
      Uri.parse('https://maps.apple.com/?ll=25.034,121.565&q=Taipei%20101'),
    )!;
    expect((apple.latitude, apple.query), (25.034, 'Taipei 101'));

    for (final link in [
      'geo:0,0',
      'geo:95,10',
      'https://example.com/maps/@25.0,121.0',
      'https://www.google.com/search?q=maps',
    ]) {
      expect(mapPoint(Uri.parse(link)), isNull, reason: link);
    }
  });

  test('image links and tile positions', () {
    expect(isImageUrl(Uri.parse('https://example.com/a/photo.JPG')), isTrue);
    expect(
      isImageUrl(Uri.parse('https://example.com/photo.jpg?w=200')),
      isTrue,
    );
    expect(isImageUrl(Uri.parse('https://example.com/page.html')), isFalse);
    expect(isImageUrl(Uri.parse('file:///photo.png')), isFalse);

    expect(tilePosition(0, 0, 1), (1.0, 1.0));
    // The Web Mercator square ends at ±85.0511°.
    final (left, top) = tilePosition(85.0511287798, -180, 3);
    final (right, bottom) = tilePosition(-85.0511287798, 180, 3);
    expect(
      [left, top, right, bottom],
      [0, closeTo(0, 1e-6), 8, closeTo(8, 1e-6)],
    );
  });

  test('loading web content is off by default and survives a round trip', () {
    expect(const BrowserSettings().loadWebContent, isFalse);
    expect(BrowserSettings.fromJson(const {}).loadWebContent, isFalse);
    final on = const BrowserSettings().copyWith(loadWebContent: true);
    final restored = BrowserSettings.fromJson(on.toJson());
    expect((restored.loadWebContent, restored.openLinksInApp), (true, true));
  });
}
