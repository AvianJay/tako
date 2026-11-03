import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Hues for coloured and highlighted text. Replies name a hue; the renderer
/// then moves it far enough from the theme's colours to stay readable, so no
/// colour a reply asks for can hide text in either mode.
const textColors = {
  'red': Color(0xffe5484d),
  'orange': Color(0xfff76b15),
  'yellow': Color(0xffffc53d),
  'green': Color(0xff30a46c),
  'teal': Color(0xff12a594),
  'blue': Color(0xff0090ff),
  'purple': Color(0xff8e4ec6),
  'pink': Color(0xffd6409f),
  'gray': Color(0xff8b8d98),
};

/// CSS names models reach for, folded into the hues above.
const _aliases = {
  'grey': 'gray',
  'silver': 'gray',
  'crimson': 'red',
  'maroon': 'red',
  'brown': 'orange',
  'amber': 'yellow',
  'gold': 'yellow',
  'lime': 'green',
  'olive': 'green',
  'cyan': 'teal',
  'aqua': 'teal',
  'turquoise': 'teal',
  'navy': 'blue',
  'skyblue': 'blue',
  'indigo': 'purple',
  'violet': 'purple',
  'magenta': 'pink',
  'fuchsia': 'pink',
};

/// The colour [value] names: a hue above or a common CSS name (also with a
/// prefix such as light or dark), black, white, `#rgb`, `#rrggbb` or `rgb()`.
/// Null when it is none of these.
Color? parseTextColor(String value) {
  final key = value
      .toLowerCase()
      .replaceAll('!important', '')
      .replaceAll(RegExp(r'[\s_-]'), '');
  if (key == 'black') return const Color(0xff000000);
  if (key == 'white') return const Color(0xffffffff);
  final hex = RegExp(r'^#([0-9a-f]{3,8})$').firstMatch(key)?[1];
  if (hex != null) {
    final digits = switch (hex.length) {
      3 || 4 => hex.substring(0, 3).split('').map((d) => '$d$d').join(),
      6 || 8 => hex.substring(0, 6),
      _ => null,
    };
    return digits == null
        ? null
        : Color(0xff000000 | int.parse(digits, radix: 16));
  }
  final rgb = RegExp(
    r'^rgba?\((\d{1,3}),(\d{1,3}),(\d{1,3})(?:,[\d.]+%?)?\)$',
  ).firstMatch(key);
  if (rgb != null) {
    int channel(int group) => int.parse(rgb[group]!).clamp(0, 255);
    return Color.fromARGB(255, channel(1), channel(2), channel(3));
  }
  final name = key.replaceFirst(
    RegExp(r'^(?:light|dark|pale|deep|hot|medium|bright|neon)'),
    '',
  );
  return textColors[name] ?? textColors[_aliases[name]];
}

/// [color] with its lightness moved just far enough from [background] for
/// 4.5:1 contrast, the WCAG AA level for body text.
Color readableTextColor(Color color, Color background) {
  final darken = background.computeLuminance() > .5;
  var hsl = HSLColor.fromColor(color.withValues(alpha: 1));
  while (contrastRatio(hsl.toColor(), background) < 4.5) {
    final lightness = hsl.lightness + (darken ? -.02 : .02);
    if (lightness < 0 || lightness > 1) break;
    hsl = hsl.withLightness(lightness);
  }
  return hsl.toColor();
}

/// A highlighter stroke of [color] over [background]: as strong as it can be
/// while [ink] keeps 4.5:1 contrast on it.
Color highlightColor(Color color, Color background, Color ink) {
  final dark = background.computeLuminance() < .5;
  for (var alpha = dark ? .45 : .55; alpha > .04; alpha -= .05) {
    final fill = Color.alphaBlend(color.withValues(alpha: alpha), background);
    if (contrastRatio(ink, fill) >= 4.5) return fill;
  }
  return background;
}

double contrastRatio(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return (math.max(x, y) + .05) / (math.min(x, y) + .05);
}
