import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A full-screen, zoomable view of a drawing, opened from a diagram.
Future<void> showVisualViewer(
  BuildContext context, {
  required String title,
  required Size size,
  required CustomPainter painter,
  String? shareLabel,
  VoidCallback? onShare,
}) => showDialog<void>(
  context: context,
  builder: (context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (onShare != null)
            IconButton(
              tooltip: shareLabel,
              onPressed: onShare,
              icon: const Icon(Icons.ios_share),
            ),
        ],
      ),
      body: _Zoomable(size: size, painter: painter),
    ),
  ),
);

class _Zoomable extends StatefulWidget {
  const _Zoomable({required this.size, required this.painter});
  final Size size;
  final CustomPainter painter;

  @override
  State<_Zoomable> createState() => _ZoomableState();
}

class _ZoomableState extends State<_Zoomable> {
  final _transform = TransformationController();
  Size? _fitted;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = constraints.biggest;
      final fit = math.min(
        2.0,
        math.min(
          (viewport.width - 32) / widget.size.width,
          (viewport.height - 32) / widget.size.height,
        ),
      );
      // Start fitted and centred; refit after rotation.
      if (_fitted != viewport) {
        _fitted = viewport;
        _transform.value = Matrix4.identity()
          ..translateByDouble(
            (viewport.width - widget.size.width * fit) / 2,
            (viewport.height - widget.size.height * fit) / 2,
            0,
            1,
          )
          ..scaleByDouble(fit, fit, 1, 1);
      }
      return InteractiveViewer(
        transformationController: _transform,
        constrained: false,
        boundaryMargin: EdgeInsets.all(
          math.max(viewport.width, viewport.height),
        ),
        minScale: math.min(fit, 1) * .5,
        maxScale: 6,
        child: RepaintBoundary(
          child: CustomPaint(size: widget.size, painter: widget.painter),
        ),
      );
    },
  );
}
