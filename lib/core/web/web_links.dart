import 'dart:math' as math;

/// What a page says about itself, for a link preview.
class LinkPreview {
  const LinkPreview({this.title, this.description, this.siteName, this.image});

  final String? title;
  final String? description;
  final String? siteName;
  final Uri? image;

  bool get isEmpty =>
      title == null && description == null && siteName == null && image == null;
}

/// The YouTube video [uri] points to, if any.
String? youtubeId(Uri uri) {
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  final host = uri.host.toLowerCase().replaceFirst(
    RegExp(r'^(?:www|m|music)\.'),
    '',
  );
  final segments = uri.pathSegments;
  final id = switch (host) {
    'youtu.be' => segments.firstOrNull,
    'youtube.com' || 'youtube-nocookie.com' =>
      uri.path == '/watch'
          ? uri.queryParameters['v']
          : const {
                  'shorts',
                  'embed',
                  'live',
                  'v',
                }.contains(segments.firstOrNull) &&
                segments.length > 1
          ? segments[1]
          : null,
    _ => null,
  };
  return id != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) ? id : null;
}

Uri youtubeThumbnail(String id) =>
    Uri.parse('https://i.ytimg.com/vi/$id/hqdefault.jpg');

/// A place a link shows on a map: coordinates when the link has them,
/// otherwise only a search such as an address.
class MapPoint {
  const MapPoint({this.latitude, this.longitude, this.query});

  final double? latitude;
  final double? longitude;
  final String? query;

  bool get located => latitude != null && longitude != null;
}

/// The place [uri] shows: a `geo:` URI, or a Google or Apple Maps link
/// whose coordinates or search can be read. Null for anything else.
MapPoint? mapPoint(Uri uri) {
  (double, double)? coordinates(String? text) {
    final match = RegExp(
      r'^\s*(-?\d{1,3}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)',
    ).firstMatch(text ?? '');
    if (match == null) return null;
    final latitude = double.parse(match[1]!);
    final longitude = double.parse(match[2]!);
    // geo:0,0 means "no coordinates, search instead".
    if (latitude.abs() > 85 ||
        longitude.abs() > 180 ||
        latitude == 0 && longitude == 0) {
      return null;
    }
    return (latitude, longitude);
  }

  String? label(String? query) {
    final named = RegExp(r'\(([^)]+)\)\s*$').firstMatch(query ?? '')?[1];
    if (named != null) return named.trim();
    return coordinates(query) == null && (query?.trim().isNotEmpty ?? false)
        ? query!.trim()
        : null;
  }

  final host = uri.host.toLowerCase();
  final query = uri.queryParameters;
  if (uri.scheme == 'geo') {
    final q = query['q'];
    final point = coordinates(uri.path) ?? coordinates(q);
    final name = label(q);
    if (point == null && name == null) return null;
    return MapPoint(latitude: point?.$1, longitude: point?.$2, query: name);
  }
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  final google =
      RegExp(r'(?:^|\.)google\.[a-z.]+$').hasMatch(host) &&
          uri.path.startsWith('/maps') ||
      host.startsWith('maps.google.');
  final apple = host == 'maps.apple.com';
  if (!google && !apple) return null;
  final at = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(uri.path);
  final point =
      (at == null ? null : coordinates('${at[1]},${at[2]}')) ??
      coordinates(query['ll'] ?? query['sll'] ?? query['center']) ??
      coordinates(query['q'] ?? query['query']);
  final place = RegExp(r'/maps/place/([^/]+)').firstMatch(uri.path)?[1];
  final name =
      label(query['q'] ?? query['query']) ??
      (place == null ? null : Uri.decodeComponent(place).replaceAll('+', ' '));
  if (point == null && name == null) return null;
  return MapPoint(latitude: point?.$1, longitude: point?.$2, query: name);
}

/// Whether [uri] names an image file by its extension.
bool isImageUrl(Uri uri) =>
    (uri.scheme == 'https' || uri.scheme == 'http') &&
    RegExp(
      r'\.(?:png|jpe?g|gif|webp|bmp)$',
      caseSensitive: false,
    ).hasMatch(uri.path);

/// The fractional Web Mercator tile coordinates of a point at [zoom].
(double, double) tilePosition(double latitude, double longitude, int zoom) {
  final scale = math.pow(2, zoom).toDouble();
  final radians = latitude * math.pi / 180;
  return (
    (longitude + 180) / 360 * scale,
    (1 - math.log(math.tan(radians) + 1 / math.cos(radians)) / math.pi) /
        2 *
        scale,
  );
}
