import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/chat/content_block.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../platform/app_services.dart';

/// Attachments in the composer. Each image keeps its preview read across draft
/// edits and streamed responses; only a path or service change reloads it.
class DraftAttachmentStrip extends StatelessWidget {
  const DraftAttachmentStrip({
    required this.attachments,
    required this.services,
    required this.onRemove,
    required this.onPreview,
    required this.enabled,
    super.key,
  });

  final List<ContentBlock> attachments;
  final AppServices services;
  final ValueChanged<ContentBlock> onRemove;
  final ValueChanged<ImageBlock> onPreview;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final hasImages = attachments.any((block) => block is ImageBlock);
    return SizedBox(
      height: hasImages ? 112 : 72,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        // There are at most eight draft attachments. Keeping these keyed tiles
        // mounted also preserves their image reads while scrolling or removing
        // a neighboring attachment.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, block) in attachments.indexed) ...[
              if (index > 0) const SizedBox(width: 8),
              switch (block) {
                ImageBlock() => _DraftImage(
                  key: ValueKey('draft-image-${block.path}'),
                  image: block,
                  services: services,
                  onRemove: enabled ? () => onRemove(block) : null,
                  onPreview: enabled ? () => onPreview(block) : null,
                ),
                FileBlock() => _DraftFile(
                  key: ValueKey('draft-file-${block.path}'),
                  file: block,
                  onRemove: enabled ? () => onRemove(block) : null,
                ),
                _ => const SizedBox.shrink(),
              },
            ],
          ],
        ),
      ),
    );
  }
}

class _DraftImage extends StatefulWidget {
  const _DraftImage({
    required this.image,
    required this.services,
    required this.onRemove,
    required this.onPreview,
    super.key,
  });

  final ImageBlock image;
  final AppServices services;
  final VoidCallback? onRemove;
  final VoidCallback? onPreview;

  @override
  State<_DraftImage> createState() => _DraftImageState();
}

class _DraftImageState extends State<_DraftImage> {
  late Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_DraftImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.path != widget.image.path ||
        !identical(oldWidget.services, widget.services)) {
      _load();
    }
  }

  void _load() {
    _bytes = Future<Uint8List>.sync(
      () => widget.services.readWorkspaceImage(widget.image.path),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    Widget fallback({bool unavailable = false}) => Center(
      child: Tooltip(
        message: unavailable ? l.fileUnavailable : l.image,
        child: Icon(
          unavailable ? Icons.broken_image_outlined : Icons.image_outlined,
          size: 30,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
    return SizedBox(
      width: 136,
      height: 112,
      child: Material(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List>(
              future: _bytes,
              builder: (context, snapshot) {
                if (snapshot.hasError) return fallback(unavailable: true);
                final bytes = snapshot.data;
                if (bytes == null) return fallback();
                return Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  cacheWidth: (136 * MediaQuery.devicePixelRatioOf(context))
                      .round(),
                  gaplessPlayback: true,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => fallback(unavailable: true),
                );
              },
            ),
            Semantics(
              button: true,
              label: widget.image.alt ?? l.viewImage,
              child: Material(
                color: Colors.transparent,
                child: InkWell(onTap: widget.onPreview),
              ),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: _RemoveAttachmentButton(
                path: widget.image.path,
                onPressed: widget.onRemove,
                overImage: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftFile extends StatelessWidget {
  const _DraftFile({required this.file, required this.onRemove, super.key});

  final FileBlock file;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 220,
        height: 72,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 44, 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 28,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          file.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: _RemoveAttachmentButton(
                  path: file.path,
                  onPressed: onRemove,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemoveAttachmentButton extends StatelessWidget {
  const _RemoveAttachmentButton({
    required this.path,
    required this.onPressed,
    this.overImage = false,
  });

  final String path;
  final VoidCallback? onPressed;
  final bool overImage;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 40,
    child: Stack(
      alignment: Alignment.center,
      children: [
        if (overImage)
          IgnorePointer(
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.black.withValues(
                  alpha: onPressed == null ? .38 : .64,
                ),
                shape: BoxShape.circle,
              ),
            ),
          ),
        IconButton(
          key: ValueKey('remove-attachment-$path'),
          tooltip: AppLocalizations.of(context).delete,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            foregroundColor: overImage ? Colors.white : null,
            disabledForegroundColor: overImage ? Colors.white54 : null,
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(40),
            maximumSize: const Size.square(40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(Icons.close_rounded, size: 20),
        ),
      ],
    ),
  );
}
