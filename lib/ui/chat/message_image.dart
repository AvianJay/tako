import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/chat/content_block.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../platform/app_services.dart';

/// Keep the disk read stable while the surrounding response is streaming.
class MessageImage extends StatefulWidget {
  const MessageImage({
    required this.image,
    required this.services,
    required this.onOpen,
    super.key,
  });
  final ImageBlock image;
  final AppServices services;
  final VoidCallback onOpen;
  @override
  State<MessageImage> createState() => _MessageImageState();
}

class _MessageImageState extends State<MessageImage> {
  late Future<Uint8List> _bytes = widget.services.readWorkspaceImage(
    widget.image.path,
  );

  @override
  void didUpdateWidget(MessageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.path != widget.image.path ||
        oldWidget.services != widget.services) {
      _bytes = widget.services.readWorkspaceImage(widget.image.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Semantics(
        button: true,
        label: l.viewImage,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onOpen,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480, maxHeight: 420),
              child: FutureBuilder<Uint8List>(
                future: _bytes,
                builder: (context, snapshot) {
                  Widget fallback(bool failed) => SizedBox(
                    width: 240,
                    height: 160,
                    child: Center(
                      child: failed
                          ? Text(l.fileUnavailable)
                          : const CircularProgressIndicator(),
                    ),
                  );
                  if (snapshot.hasError) return fallback(true);
                  final bytes = snapshot.data;
                  if (bytes == null) return fallback(false);
                  return Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    width: 480,
                    height: 320,
                    cacheWidth: (480 * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => fallback(true),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
