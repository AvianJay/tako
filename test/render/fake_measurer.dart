import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:tako/ui/render/visuals/visual_text.dart';

/// Seven pixels per character and sixteen per line, wrapped at maxWidth, so
/// layouts can be checked without fonts.
class FakeMeasurer implements TextMeasurer {
  @override
  Size measure(
    String text,
    VisualTextRole role, {
    double maxWidth = double.infinity,
    int? maxLines,
  }) {
    var width = 0.0;
    var lines = 0;
    for (final line in text.split('\n')) {
      final length = line.length * 7.0;
      lines += maxWidth.isFinite && length > maxWidth
          ? (length / maxWidth).ceil()
          : 1;
      width = math.max(width, math.min(length, maxWidth));
    }
    if (maxLines != null) lines = math.min(lines, maxLines);
    return Size(width, 16.0 * lines);
  }
}
