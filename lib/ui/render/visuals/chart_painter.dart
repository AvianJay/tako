import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chart_layout.dart';
import 'chart_scale.dart';
import 'chart_spec.dart';
import 'visual_palette.dart';
import 'visual_text.dart';

/// Paints a [ChartLayout]. [progress] grows the marks from their baseline;
/// [selected] is a category, or a slice for pies, and shows its values.
class ChartPainter extends CustomPainter {
  ChartPainter({
    required this.layout,
    required this.spec,
    required this.palette,
    required this.text,
    required this.format,
    required this.totalLabel,
    this.selected,
    Animation<double>? progress,
  }) : _progress = progress,
       super(repaint: progress);

  final ChartLayout layout;
  final ChartSpec spec;
  final VisualPalette palette;
  final VisualText text;
  final ChartFormat format;
  final String totalLabel;
  final int? selected;
  final Animation<double>? _progress;

  double get _t =>
      Curves.easeOutCubic.transform((_progress?.value ?? 1).clamp(0.0, 1.0));

  bool get _settled => (_progress?.value ?? 1) >= 1;

  @override
  void paint(Canvas canvas, Size size) {
    if (layout.form == ChartForm.pie) {
      _pie(canvas);
    } else {
      _axes(canvas);
    }
    for (final placed in layout.texts) {
      text.paint(
        canvas,
        placed.text,
        placed.role,
        placed.offset,
        color: placed.ink == ChartInk.ink ? palette.ink : palette.mutedInk,
        maxWidth: placed.maxWidth,
        maxLines: placed.maxLines,
        align: placed.align,
      );
    }
    for (final key in layout.keys) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(key.rect, Radius.circular(key.line ? 1 : 2)),
        Paint()..color = palette.seriesColor(key.color),
      );
    }
    if (selected != null && _settled) _tooltip(canvas, size);
  }

  Color _mark(int series, int index) {
    final color = palette.seriesColor(series);
    return selected == null || selected == index
        ? color
        : color.withValues(alpha: .35);
  }

  void _axes(Canvas canvas) {
    final rows = layout.form == ChartForm.rows;
    final plot = layout.plot;
    Offset start(double position) =>
        rows ? Offset(position, plot.top) : Offset(plot.left, position);
    Offset end(double position) =>
        rows ? Offset(position, plot.bottom) : Offset(plot.right, position);
    final grid = Paint()
      ..color = palette.grid
      ..strokeWidth = 1;
    for (final position in layout.grid) {
      if ((position - layout.baseline).abs() < .5) continue;
      canvas.drawLine(start(position), end(position), grid);
    }

    final t = _t;
    final base = layout.baseline;
    for (final bar in layout.bars) {
      final r = bar.rect;
      final rect = rows
          ? Rect.fromLTRB(
              base + (r.left - base) * t,
              r.top,
              base + (r.right - base) * t,
              r.bottom,
            )
          : Rect.fromLTRB(
              r.left,
              base + (r.top - base) * t,
              r.right,
              base + (r.bottom - base) * t,
            );
      if (rect.width <= 0 || rect.height <= 0) continue;
      final radius = Radius.circular(
        math.min(4, math.min(rect.width, rect.height) / 2),
      );
      canvas.drawRRect(switch (bar.end) {
        BarEnd.up => RRect.fromRectAndCorners(
          rect,
          topLeft: radius,
          topRight: radius,
        ),
        BarEnd.down => RRect.fromRectAndCorners(
          rect,
          bottomLeft: radius,
          bottomRight: radius,
        ),
        BarEnd.right => RRect.fromRectAndCorners(
          rect,
          topRight: radius,
          bottomRight: radius,
        ),
        BarEnd.left => RRect.fromRectAndCorners(
          rect,
          topLeft: radius,
          bottomLeft: radius,
        ),
        BarEnd.none => RRect.fromRectAndRadius(rect, Radius.zero),
      }, Paint()..color = _mark(bar.series, bar.index));
    }
    canvas.drawLine(
      start(base),
      end(base),
      Paint()
        ..color = palette.baseline
        ..strokeWidth = 1,
    );
    if (layout.lines.isEmpty) return;

    // Lines draw in from the left.
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(
        0,
        0,
        plot.left + (plot.width + 12) * t,
        layout.size.height,
      ),
    );
    if (layout.area) {
      for (final line in layout.lines) {
        _area(canvas, line);
      }
    }
    if (selected case final index? when index < layout.centers.length) {
      final x = layout.centers[index];
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()
          ..color = palette.baseline
          ..strokeWidth = 1,
      );
    }
    for (final line in layout.lines) {
      final color = palette.seriesColor(line.series);
      final path = Path();
      var open = false;
      for (final point in line.points) {
        if (point == null) {
          open = false;
        } else if (open) {
          path.lineTo(point.dx, point.dy);
        } else {
          path.moveTo(point.dx, point.dy);
          open = true;
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      for (final (index, point) in line.points.indexed) {
        if (point == null) continue;
        // An isolated value has no segment, so it always gets a marker.
        final isolated =
            (index == 0 || line.points[index - 1] == null) &&
            (index == line.points.length - 1 || line.points[index + 1] == null);
        final emphasised = selected == index;
        if (!layout.markers && !isolated && !emphasised) continue;
        final radius = emphasised ? 5.0 : 4.0;
        canvas
          ..drawCircle(point, radius + 2, Paint()..color = palette.surface)
          ..drawCircle(point, radius, Paint()..color = color);
      }
    }
    canvas.restore();
  }

  void _area(Canvas canvas, ChartLine line) {
    final paint = Paint()
      ..color = palette.seriesColor(line.series).withValues(alpha: .1);
    final points = line.points;
    var first = 0;
    while (first < points.length) {
      if (points[first] == null) {
        first++;
        continue;
      }
      var last = first;
      while (last + 1 < points.length && points[last + 1] != null) {
        last++;
      }
      final path = Path()..moveTo(points[first]!.dx, points[first]!.dy);
      for (var i = first + 1; i <= last; i++) {
        path.lineTo(points[i]!.dx, points[i]!.dy);
      }
      for (var i = last; i >= first; i--) {
        final lower = line.lower?[i] ?? Offset(points[i]!.dx, layout.baseline);
        path.lineTo(lower.dx, lower.dy);
      }
      canvas.drawPath(path..close(), paint);
      first = last + 1;
    }
  }

  double get _total =>
      layout.slices.fold<double>(0, (sum, slice) => sum + slice.value);

  void _pie(Canvas canvas) {
    final t = _t;
    final center = layout.center;
    final radius = layout.radius;
    final hole = layout.hole;
    double angle(double start) => -math.pi / 2 + (start + math.pi / 2) * t;
    for (final (index, slice) in layout.slices.indexed) {
      final start = angle(slice.start);
      final sweep = slice.sweep * t;
      if (sweep <= 0) continue;
      final lift = selected == index && layout.slices.length > 1
          ? Offset.fromDirection(start + sweep / 2, 5)
          : Offset.zero;
      final outer = Rect.fromCircle(center: center + lift, radius: radius);
      final inner = Rect.fromCircle(center: center + lift, radius: hole);
      final path = Path();
      if (sweep >= 2 * math.pi - 1e-6) {
        path.addOval(outer);
        if (hole > 0) {
          path
            ..addOval(inner)
            ..fillType = PathFillType.evenOdd;
        }
      } else if (hole > 0) {
        path
          ..arcTo(outer, start, sweep, true)
          ..arcTo(inner, start + sweep, -sweep, false)
          ..close();
      } else {
        path
          ..moveTo(center.dx + lift.dx, center.dy + lift.dy)
          ..arcTo(outer, start, sweep, false)
          ..close();
      }
      canvas.drawPath(path, Paint()..color = _mark(slice.color, index));
    }
    if (layout.slices.length > 1) {
      final gap = Paint()
        ..color = palette.surface
        ..strokeWidth = 2;
      for (final slice in layout.slices) {
        final direction = angle(slice.start);
        canvas.drawLine(
          center + Offset.fromDirection(direction, math.max(0, hole - 1)),
          center + Offset.fromDirection(direction, radius + 6),
          gap,
        );
      }
    }
    if (hole <= 0 || !_settled) return;
    // The donut's centre reads the selected slice, or else the total. Shares
    // already in percent always add up to 100%, so those show the largest.
    final percents = spec.unit == '%';
    final slice = selected != null
        ? layout.slices[selected!]
        : percents
        ? layout.slices.first
        : null;
    final value = format.compact(slice?.value ?? _total);
    final caption = slice == null
        ? totalLabel
        : percents
        ? slice.label
        : '${slice.label} · ${format.percent(slice.value / _total)}';
    final valueSize = text.measure(
      value,
      VisualTextRole.title,
      maxWidth: hole * 1.6,
      maxLines: 1,
    );
    final captionSize = text.measure(
      caption,
      VisualTextRole.caption,
      maxWidth: hole * 1.5,
      maxLines: 2,
    );
    final top = center.dy - (valueSize.height + captionSize.height) / 2;
    text
      ..paint(
        canvas,
        value,
        VisualTextRole.title,
        Offset(center.dx - valueSize.width / 2, top),
        color: palette.ink,
        maxWidth: hole * 1.6,
        maxLines: 1,
      )
      ..paint(
        canvas,
        caption,
        VisualTextRole.caption,
        Offset(center.dx - captionSize.width / 2, top + valueSize.height),
        color: palette.mutedInk,
        maxWidth: hole * 1.5,
        maxLines: 2,
        align: TextAlign.center,
      );
  }

  void _tooltip(Canvas canvas, Size size) {
    final index = selected!;
    final String header;
    // (series key, value, name)
    final rows = <(int?, String, String)>[];
    final Rect target;
    if (layout.form == ChartForm.pie) {
      // A donut already reads the selection in its centre.
      if (layout.hole > 0 || index >= layout.slices.length) return;
      final slice = layout.slices[index];
      header = slice.label;
      rows.add((
        null,
        format.full(slice.value),
        spec.unit == '%' ? '' : format.percent(slice.value / _total),
      ));
      target = Rect.fromCircle(
        center:
            layout.center +
            Offset.fromDirection(
              slice.start + slice.sweep / 2,
              layout.radius * .6,
            ),
        radius: 1,
      );
    } else {
      if (index >= spec.labels.length) return;
      header = spec.labels[index];
      for (final (s, series) in spec.series.indexed) {
        final value = series.data[index];
        if (value == null) continue;
        rows.add((
          spec.series.length > 1 ? s : null,
          format.full(value),
          series.name,
        ));
      }
      if (rows.isEmpty) return;
      final marks = [
        for (final bar in layout.bars)
          if (bar.index == index) bar.rect,
        for (final line in layout.lines)
          if (line.points[index] case final point?)
            Rect.fromCircle(center: point, radius: 6),
      ];
      target = marks.isEmpty
          ? Rect.fromCircle(
              center: Offset(layout.centers[index], layout.plot.top),
              radius: 1,
            )
          : marks.reduce((a, b) => a.expandToInclude(b));
    }

    const padding = EdgeInsets.symmetric(horizontal: 10, vertical: 8);
    final maxWidth = math.min(size.width, 260.0);
    final inner = maxWidth - padding.horizontal;
    final headerSize = text.measure(
      header,
      VisualTextRole.caption,
      maxWidth: inner,
      maxLines: 2,
    );
    final sizes = [
      for (final row in rows)
        (
          text.measure(row.$2, VisualTextRole.captionStrong),
          text.measure(
            row.$3,
            VisualTextRole.caption,
            maxWidth: math.max(inner - 96, 40),
            maxLines: 1,
          ),
        ),
    ];
    double width = headerSize.width;
    var height = headerSize.height + 2;
    for (final (i, row) in rows.indexed) {
      final (value, name) = sizes[i];
      width = math.max(
        width,
        (row.$1 == null ? 0 : 18) +
            value.width +
            (row.$3.isEmpty ? 0 : 6 + name.width),
      );
      height += math.max(value.height, name.height) + 2;
    }
    width = math.min(width + padding.horizontal, maxWidth);
    height += padding.vertical - 2;

    final x = layout.form == ChartForm.rows ? target.right : target.center.dx;
    var top = target.top - 8 - height;
    if (top < 0) top = target.bottom + 8;
    top = math.max(0.0, math.min(top, size.height - height));
    final left = math.max(0.0, math.min(x - width / 2, size.width - width));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, width, height),
        const Radius.circular(8),
      ),
      Paint()..color = palette.tooltip,
    );
    final muted = palette.onTooltip.withValues(alpha: .8);
    var y = top + padding.top;
    text.paint(
      canvas,
      header,
      VisualTextRole.caption,
      Offset(left + padding.left, y),
      color: muted,
      maxWidth: inner,
      maxLines: 2,
    );
    y += headerSize.height + 2;
    for (final (i, row) in rows.indexed) {
      final (value, name) = sizes[i];
      final lineHeight = math.max(value.height, name.height);
      var cursor = left + padding.left;
      if (row.$1 case final series?) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cursor, y + lineHeight / 2 - 1, 12, 2),
            const Radius.circular(1),
          ),
          Paint()..color = palette.seriesColor(series),
        );
        cursor += 18;
      }
      // Values lead; names follow.
      text.paint(
        canvas,
        row.$2,
        VisualTextRole.captionStrong,
        Offset(cursor, y),
        color: palette.onTooltip,
      );
      if (row.$3.isNotEmpty) {
        text.paint(
          canvas,
          row.$3,
          VisualTextRole.caption,
          Offset(cursor + value.width + 6, y),
          color: muted,
          maxWidth: math.max(inner - 96, 40),
          maxLines: 1,
        );
      }
      y += lineHeight + 2;
    }
  }

  @override
  bool shouldRepaint(ChartPainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.selected != selected ||
      oldDelegate.palette != palette ||
      oldDelegate.text != text ||
      oldDelegate._progress != _progress;
}
