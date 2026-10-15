import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'visual_text.dart';

/// A chart or diagram that renders to PNG only when asked, so sharing costs
/// nothing until the user taps Share.
class VisualImage {
  const VisualImage(this.fileName, this._render);

  final String fileName;
  final Future<Uint8List> Function() _render;

  Future<Uint8List> toPng() => _render();
}

/// `tako-chart-20261015-143000.png`
String visualFileName(String kind, DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return 'tako-$kind-${time.year}${two(time.month)}${two(time.day)}-'
      '${two(time.hour)}${two(time.minute)}${two(time.second)}.png';
}

/// Draws [paint] at its natural [size] below an optional [title], on an
/// opaque [background] with a margin. Drawn afresh rather than captured from
/// the screen, so scaling, scrolling and open tooltips never leak in. Up to
/// 3× and at most 4096 px on a side or about 8.4 megapixels.
Future<Uint8List> renderVisualPng({
  required Size size,
  required void Function(Canvas canvas) paint,
  required Color background,
  required VisualText text,
  required Color titleColor,
  String? title,
}) async {
  const margin = 24.0;
  final titleSize = title == null
      ? Size.zero
      : text.measure(
          title,
          VisualTextRole.title,
          maxWidth: math.max(size.width, 240),
          maxLines: 2,
        );
  final width = math.max(size.width, titleSize.width) + 2 * margin;
  final titleBand = title == null ? 0.0 : titleSize.height + 12;
  final height = size.height + titleBand + 2 * margin;
  final ratio = math.min(
    3.0,
    math.min(
      4096 / math.max(width, height),
      math.sqrt(8.4e6 / (width * height)),
    ),
  );
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(ratio);
  canvas.drawRect(
    Offset.zero & Size(width, height),
    Paint()..color = background.withValues(alpha: 1),
  );
  if (title != null) {
    text.paint(
      canvas,
      title,
      VisualTextRole.title,
      const Offset(margin, margin),
      color: titleColor,
      maxWidth: math.max(size.width, 240),
      maxLines: 2,
    );
  }
  canvas.translate(margin, margin + titleBand);
  paint(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (width * ratio).ceil(),
    (height * ratio).ceil(),
  );
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
