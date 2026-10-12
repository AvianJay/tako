import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The Tako mark: a round head over three dots, its tentacles. It is the
/// launcher icon's shape (`ic_launcher_foreground.xml`), drawn in place of an
/// [Icon] and sized and coloured like one.
class TakoMark extends StatelessWidget {
  const TakoMark({this.size, this.color, super.key});
  final double? size;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final icons = IconTheme.of(context);
    return CustomPaint(
      size: Size.square(size ?? icons.size ?? 24),
      painter: TakoMarkPainter(
        color: color ?? icons.color ?? Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

/// Paints the mark on the launcher's 108-unit canvas, centred on (54, 54).
///
/// [morph] runs from the whole mark (0) to three dots on the centre line (1):
/// the dots rise while the head shrinks into the middle one. [wave] is the
/// phase, in periods, of a typing-indicator hop; null keeps the dots still.
class TakoMarkPainter extends CustomPainter {
  const TakoMarkPainter({
    required this.color,
    this.extent = iconExtent,
    this.morph = 0,
    this.wave,
  });

  /// Canvas units across the shorter side. Icons crop close to the mark; the
  /// launch screen shows the whole launcher canvas.
  static const iconExtent = 56.0;
  static const launcherExtent = 108.0;
  static const _dotX = [40.5, 54.0, 67.5];
  static const _dotY = 73.5;
  static const _dotRadius = 4.5;
  static final _head = Path()
    ..moveTo(54, 29.5)
    ..cubicTo(64.22, 29.5, 72.5, 39.13, 72.5, 51)
    ..cubicTo(72.5, 53.87, 72.01, 56.71, 71.05, 59.35)
    ..cubicTo(69.96, 62.34, 67.05, 64.5, 65.4, 64.5)
    ..lineTo(42.6, 64.5)
    ..cubicTo(40.95, 64.5, 38.04, 62.34, 36.95, 59.35)
    ..cubicTo(35.99, 56.71, 35.5, 53.87, 35.5, 51)
    ..cubicTo(35.5, 39.13, 43.78, 29.5, 54, 29.5)
    ..close();

  final Color color;
  final double extent;
  final double morph;
  final double? wave;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final progress = morph.clamp(0.0, 1.0);
    final t = Curves.easeInOutCubic.transform(progress);
    final dotY = _dotY + (54 - _dotY) * t;
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(size.shortestSide / extent)
      ..translate(-54, -54);
    if (t < 1) {
      canvas
        ..save()
        ..translate(54, dotY)
        ..scale(1 - t)
        ..translate(-54, -dotY)
        ..drawPath(_head, paint)
        ..restore();
    }
    // The middle dot swells briefly as it takes in the head.
    final gulp = math.sin(math.pi * ((progress - .55) / .45).clamp(0.0, 1.0));
    for (final (index, x) in _dotX.indexed) {
      canvas.drawCircle(
        Offset(x, dotY - _hop(index)),
        _dotRadius * (index == 1 ? 1 + .22 * gulp : 1),
        paint,
      );
    }
    canvas.restore();
  }

  double _hop(int index) {
    final wave = this.wave;
    if (wave == null) return 0;
    final phase = (wave - index * .13) % 1;
    if (phase >= .4) return 0;
    final rise = math.sin(math.pi * phase / .4);
    return 4 * rise * rise;
  }

  @override
  bool shouldRepaint(TakoMarkPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.extent != extent ||
      oldDelegate.morph != morph ||
      oldDelegate.wave != wave;
}
