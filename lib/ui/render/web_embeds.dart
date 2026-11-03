import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/web/web_links.dart';
import 'visuals/visual_labels.dart';

/// Network access for previews, supplied by the host. Nothing loads until
/// the user taps a preview, unless [autoLoad] is on. Even then, images and
/// page previews load at once only for links the reply did not make up
/// ([trusted]): a link the model wrote by itself could carry private data
/// to whoever runs the site. Map tiles and video thumbnails come from fixed
/// services and need only [autoLoad].
@immutable
class WebEmbeds {
  const WebEmbeds({
    required this.preview,
    required this.image,
    required this.tile,
    this.autoLoad = false,
    this.trusted = _never,
    this.loaded,
  });

  final Future<LinkPreview?> Function(Uri uri) preview;
  final Future<Uint8List> Function(Uri uri) image;
  final Future<Uint8List> Function(int zoom, int x, int y) tile;
  final bool autoLoad;

  /// Whether [url] appeared before the reply, in the user's messages or in
  /// tool results.
  final bool Function(String url) trusted;

  /// Links loaded earlier in the session, which stay loaded.
  final Set<String>? loaded;

  bool loadsAtOnce(String url, {bool fixedHost = false}) =>
      (loaded?.contains(url) ?? false) ||
      autoLoad && (fixedHost || trusted(url));

  void markLoaded(String url) => loaded?.add(url);
}

bool _never(String url) => false;

String _site(Uri uri) => uri.host.replaceFirst(RegExp(r'^www\.'), '');

/// The outlined, tappable frame every preview shares.
class _Frame extends StatelessWidget {
  const _Frame({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Material(
          color: scheme.surfaceContainerLow,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: InkWell(onTap: onTap, child: child),
        ),
      ),
    );
  }
}

class _LoadButton extends StatelessWidget {
  const _LoadButton({
    required this.label,
    required this.state,
    required this.failedLabel,
    this.onPressed,
  });

  final String label;
  final String failedLabel;

  /// Null before loading, false while loading, true after a failure.
  final bool? state;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => switch (state) {
    null => TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.download_outlined, size: 18),
      label: Text(label),
    ),
    false => const Padding(
      padding: EdgeInsets.all(12),
      child: SizedBox.square(
        dimension: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
    true => Tooltip(
      message: failedLabel,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(
          Icons.link_off,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  };
}

/// Image bytes from the host, drawn once they arrive.
class _NetworkImage extends StatefulWidget {
  const _NetworkImage({
    required this.load,
    this.fit = BoxFit.cover,
    this.semanticLabel,
    this.failure,
    super.key,
  });

  final Future<Uint8List> Function() load;
  final BoxFit fit;
  final String? semanticLabel;
  final Widget? failure;

  @override
  State<_NetworkImage> createState() => _NetworkImageState();
}

class _NetworkImageState extends State<_NetworkImage> {
  late final Future<Uint8List> _bytes = widget.load();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failure =
        widget.failure ??
        ColoredBox(
          color: scheme.surfaceContainerHighest,
          child: Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: scheme.onSurfaceVariant,
            ),
          ),
        );
    return FutureBuilder(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.data case final bytes?) {
          return Image.memory(
            bytes,
            fit: widget.fit,
            gaplessPlayback: true,
            semanticLabel: widget.semanticLabel,
            errorBuilder: (_, _, _) => failure,
          );
        }
        if (snapshot.hasError) return failure;
        return ColoredBox(color: scheme.surfaceContainerHighest);
      },
    );
  }
}

/// A card for a link that stands on its own line: the page's title,
/// summary and image once loaded. YouTube links show the video instead.
class LinkPreviewCard extends StatefulWidget {
  const LinkPreviewCard({
    required this.uri,
    required this.label,
    required this.web,
    required this.labels,
    this.onOpen,
    super.key,
  });

  final Uri uri;

  /// The link's own text, shown until the page's title is known.
  final String label;
  final WebEmbeds web;
  final VisualLabels labels;
  final VoidCallback? onOpen;

  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  Future<LinkPreview?>? _preview;
  late final bool _video = youtubeId(widget.uri) != null;

  @override
  void initState() {
    super.initState();
    if (widget.web.loadsAtOnce('${widget.uri}', fixedHost: _video)) {
      _preview = widget.web.preview(widget.uri);
    }
  }

  void _load() {
    widget.web.markLoaded('${widget.uri}');
    setState(() {
      _preview = widget.web.preview(widget.uri);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return FutureBuilder(
      future: _preview,
      builder: (context, snapshot) {
        final preview = snapshot.data;
        final done = snapshot.connectionState == ConnectionState.done;
        final image = preview?.image;
        return _Frame(
          onTap: widget.onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (image != null)
                AspectRatio(
                  aspectRatio: _video ? 16 / 9 : 1.91,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _NetworkImage(load: () => widget.web.image(image)),
                      if (_video)
                        const Center(
                          child: Icon(
                            Icons.play_circle_fill,
                            size: 56,
                            color: Colors.white,
                            shadows: [Shadow(blurRadius: 12)],
                          ),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                child: Row(
                  children: [
                    if (image == null) ...[
                      Icon(
                        _video ? Icons.smart_display_outlined : Icons.link,
                        color: muted,
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            preview?.title ?? widget.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          if (preview?.description case final description?)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                description,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: muted,
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              {
                                ?preview?.siteName,
                                _site(widget.uri),
                              }.join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_preview == null || !done || preview == null)
                      _LoadButton(
                        label: widget.labels.loadPreview,
                        failedLabel: widget.labels.loadFailed,
                        state: _preview == null ? null : done,
                        onPressed: _load,
                      )
                    else
                      const SizedBox(width: 8),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// An image from the web, behind a tap unless the host loads it at once.
class RemoteImage extends StatefulWidget {
  const RemoteImage({
    required this.uri,
    required this.alt,
    required this.web,
    required this.labels,
    this.onOpen,
    super.key,
  });

  final Uri uri;
  final String alt;
  final WebEmbeds web;
  final VisualLabels labels;
  final VoidCallback? onOpen;

  @override
  State<RemoteImage> createState() => _RemoteImageState();
}

class _RemoteImageState extends State<RemoteImage> {
  late bool _shown = widget.web.loadsAtOnce('${widget.uri}');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    if (!_shown) {
      return _Frame(
        onTap: () {
          widget.web.markLoaded('${widget.uri}');
          setState(() => _shown = true);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.image_outlined, color: muted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.alt.isEmpty ? widget.labels.loadImage : widget.alt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      widget.alt.isEmpty
                          ? _site(widget.uri)
                          : '${widget.labels.loadImage} · ${_site(widget.uri)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.download_outlined, color: muted, size: 20),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: widget.onOpen,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 480,
              maxHeight: 360,
              minHeight: 48,
              minWidth: 48,
            ),
            child: _NetworkImage(
              load: () => widget.web.image(widget.uri),
              fit: BoxFit.contain,
              semanticLabel: widget.alt.isEmpty ? null : widget.alt,
              failure: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image_outlined, color: muted),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${widget.labels.loadFailed} · ${_site(widget.uri)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A place from a `geo:` or maps link: a map of the spot once loaded, and a
/// tap that opens the maps app.
class MapCard extends StatefulWidget {
  const MapCard({
    required this.point,
    required this.label,
    required this.web,
    required this.labels,
    this.onOpen,
    this.onAttribution,
    super.key,
  });

  static const height = 168.0;

  final MapPoint point;
  final String label;
  final WebEmbeds web;
  final VisualLabels labels;
  final VoidCallback? onOpen;

  /// Opens the map data's copyright page.
  final VoidCallback? onAttribution;

  @override
  State<MapCard> createState() => _MapCardState();
}

class _MapCardState extends State<MapCard> {
  late final String _key =
      'geo:${widget.point.latitude},${widget.point.longitude}';
  late bool _shown =
      widget.point.located && widget.web.loadsAtOnce(_key, fixedHost: true);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final point = widget.point;
    final coordinates = point.located
        ? '${point.latitude!.toStringAsFixed(5)}, '
              '${point.longitude!.toStringAsFixed(5)}'
        : null;
    final title = widget.label.isNotEmpty
        ? widget.label
        : point.query ?? coordinates ?? '';
    final subtitle = [
      if (point.query != null && point.query != title) point.query!,
      if (coordinates != null && coordinates != title) coordinates,
    ].join(' · ');
    return _Frame(
      onTap: widget.onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (point.located)
            SizedBox(
              height: MapCard.height,
              child: _shown
                  ? _MapTiles(
                      latitude: point.latitude!,
                      longitude: point.longitude!,
                      web: widget.web,
                      onAttribution: widget.onAttribution,
                    )
                  : ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: Center(
                        child: TextButton.icon(
                          onPressed: () {
                            widget.web.markLoaded(_key);
                            setState(() => _shown = true);
                          },
                          icon: const Icon(Icons.map_outlined),
                          label: Text(widget.labels.loadMap),
                        ),
                      ),
                    ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Icon(Icons.place_outlined, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.open_in_new,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// OpenStreetMap tiles around a point, with a pin on it. Tiles are fetched
/// one zoom level deeper and drawn at half size on sharp screens.
class _MapTiles extends StatelessWidget {
  const _MapTiles({
    required this.latitude,
    required this.longitude,
    required this.web,
    this.onAttribution,
  });

  static const _zoom = 15;

  final double latitude;
  final double longitude;
  final WebEmbeds web;
  final VoidCallback? onAttribution;

  @override
  Widget build(BuildContext context) {
    final sharp = MediaQuery.devicePixelRatioOf(context) >= 1.5;
    final zoom = sharp ? _zoom + 1 : _zoom;
    final size = sharp ? 128.0 : 256.0;
    final count = 1 << zoom;
    final (x, y) = tilePosition(latitude, longitude, zoom);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final left = x * size - width / 2;
        final top = y * size - height / 2;
        return ClipRect(
          child: Stack(
            children: [
              for (
                var column = (left / size).floor();
                column <= ((left + width) / size).floor();
                column++
              )
                for (
                  var row = (top / size).floor();
                  row <= ((top + height) / size).floor();
                  row++
                )
                  if (row >= 0 && row < count)
                    Positioned(
                      left: column * size - left,
                      top: row * size - top,
                      width: size,
                      height: size,
                      child: _NetworkImage(
                        key: ValueKey('$zoom/$column/$row'),
                        load: () => web.tile(zoom, column % count, row),
                        fit: BoxFit.fill,
                      ),
                    ),
              Positioned(
                left: width / 2 - 18,
                top: height / 2 - 36,
                child: const Icon(
                  Icons.location_on,
                  size: 36,
                  color: Color(0xffe5484d),
                  shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: onAttribution,
                  child: const ColoredBox(
                    color: Color(0xccffffff),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      child: Text(
                        '© OpenStreetMap contributors',
                        style: TextStyle(fontSize: 10, color: Colors.black87),
                        textScaler: TextScaler.noScaling,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
