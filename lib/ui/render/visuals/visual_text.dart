import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'visual_cache.dart';

enum VisualTextRole {
  /// Diagram node labels.
  body,

  /// Participants, first-level mind map branches.
  bodyStrong,

  /// Axis labels, legends, edge labels, notes.
  caption,

  /// Tooltip values and frame tags.
  captionStrong,

  /// Axis ticks: digits share one width so columns align.
  tabular,

  /// Sequence numbers.
  tiny,

  /// Mind map roots, donut totals, exported titles.
  title,
}

/// Measures text for layouts. Layouts only keep geometry, so tests can use a
/// deterministic measurer instead of real fonts.
abstract interface class TextMeasurer {
  /// The size of [text] wrapped at [maxWidth]. Lines past [maxLines] end in
  /// an ellipsis.
  Size measure(
    String text,
    VisualTextRole role, {
    double maxWidth = double.infinity,
    int? maxLines,
  });
}

typedef _PainterKey = (String, VisualTextRole, double, int?, Color?, TextAlign);

/// Theme-aware text for painters. Measuring and painting share one cache of
/// laid-out paragraphs, so a measured label paints exactly as measured.
class VisualText implements TextMeasurer {
  VisualText._(this._styles, this._scaler, this.signature);

  /// Shared by every visual with the same fonts, text scale and bold-text
  /// setting.
  factory VisualText.of(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final base = DefaultTextStyle.of(context).style;
    final bold = MediaQuery.boldTextOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    TextStyle shape(TextStyle? style, {FontWeight? weight}) {
      final merged = base.merge(style);
      return TextStyle(
        fontFamily: merged.fontFamily,
        fontFamilyFallback: merged.fontFamilyFallback,
        fontSize: merged.fontSize,
        fontWeight: bold ? FontWeight.bold : weight ?? merged.fontWeight,
        fontStyle: merged.fontStyle,
        letterSpacing: merged.letterSpacing,
        height: merged.height,
        leadingDistribution: merged.leadingDistribution,
        locale: merged.locale,
      );
    }

    final styles = {
      VisualTextRole.body: shape(textTheme.bodyMedium),
      VisualTextRole.bodyStrong: shape(
        textTheme.bodyMedium,
        weight: FontWeight.w600,
      ),
      VisualTextRole.caption: shape(textTheme.bodySmall),
      VisualTextRole.captionStrong: shape(
        textTheme.bodySmall,
        weight: FontWeight.w600,
      ),
      VisualTextRole.tabular: shape(
        textTheme.bodySmall,
      ).copyWith(fontFeatures: const [ui.FontFeature.tabularFigures()]),
      VisualTextRole.tiny: shape(textTheme.labelSmall, weight: FontWeight.w600),
      VisualTextRole.title: shape(
        textTheme.titleSmall,
        weight: FontWeight.w600,
      ),
    };
    final signature = [
      scaler.scale(100).toStringAsFixed(2),
      for (final style in styles.values)
        '${style.fontFamily},${style.fontSize},${style.fontWeight?.value},'
            '${style.height},${style.letterSpacing}',
    ].join('|');
    return _instances.putIfAbsent(
      signature,
      () => VisualText._(styles, scaler, signature),
    );
  }

  static final _instances = LruCache<String, VisualText>(
    6,
    onEvict: (text) => text._painters.clear(),
  );

  final Map<VisualTextRole, TextStyle> _styles;
  final TextScaler _scaler;

  /// Identifies fonts and scale, so cached layouts never mix them.
  final String signature;

  final _painters = LruCache<_PainterKey, TextPainter>(
    600,
    onEvict: (painter) => painter.dispose(),
  );

  TextPainter _painter(
    String text,
    VisualTextRole role,
    double maxWidth,
    int? maxLines,
    Color? color,
    TextAlign align,
  ) => _painters.putIfAbsent(
    (text, role, maxWidth, maxLines, color, align),
    () => TextPainter(
      text: TextSpan(
        text: text,
        style: color == null
            ? _styles[role]
            : _styles[role]!.copyWith(color: color),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
      textScaler: _scaler,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
      textWidthBasis: TextWidthBasis.longestLine,
    )..layout(maxWidth: maxWidth),
  );

  @override
  Size measure(
    String text,
    VisualTextRole role, {
    double maxWidth = double.infinity,
    int? maxLines,
  }) => _painter(text, role, maxWidth, maxLines, null, TextAlign.left).size;

  /// Paints [text] with its top-left corner at [offset].
  void paint(
    Canvas canvas,
    String text,
    VisualTextRole role,
    Offset offset, {
    required Color color,
    double maxWidth = double.infinity,
    int? maxLines,
    TextAlign align = TextAlign.left,
  }) => _painter(
    text,
    role,
    maxWidth,
    maxLines,
    color,
    align,
  ).paint(canvas, offset);

  /// Paints [text] centred on [center], each line centred.
  void paintCentered(
    Canvas canvas,
    String text,
    VisualTextRole role,
    Offset center, {
    required Color color,
    double maxWidth = double.infinity,
    int? maxLines,
  }) {
    final painter = _painter(
      text,
      role,
      maxWidth,
      maxLines,
      color,
      TextAlign.center,
    );
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }
}
