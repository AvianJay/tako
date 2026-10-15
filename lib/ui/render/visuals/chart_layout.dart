import 'dart:math' as math;
import 'dart:ui';

import 'chart_scale.dart';
import 'chart_spec.dart';
import 'visual_text.dart';

enum ChartForm { columns, rows, lines, pie }

enum ChartInk { ink, muted }

/// The end of a bar that carries the value: it gets the rounded corners.
/// Inner segments of a stack have none.
enum BarEnd { up, down, right, left, none }

class PlacedText {
  const PlacedText(
    this.text,
    this.role,
    this.offset, {
    this.ink = ChartInk.muted,
    this.maxWidth = double.infinity,
    this.maxLines,
    this.align = TextAlign.left,
  });

  final String text;
  final VisualTextRole role;

  /// Top-left corner.
  final Offset offset;
  final ChartInk ink;
  final double maxWidth;
  final int? maxLines;
  final TextAlign align;
}

class ChartBar {
  const ChartBar(this.series, this.index, this.rect, this.end);
  final int series;
  final int index;
  final Rect rect;
  final BarEnd end;
}

class ChartLine {
  const ChartLine(this.series, this.points, {this.lower});
  final int series;
  final List<Offset?> points;

  /// A stacked area fills down to the series below it.
  final List<Offset?>? lower;
}

class ChartSlice {
  const ChartSlice(
    this.color,
    this.label,
    this.value,
    this.start,
    this.sweep,
    this.categories,
  );

  final int color;
  final String label;
  final double value;
  final double start;
  final double sweep;

  /// Spec indices; "Other" holds several.
  final List<int> categories;
}

class LegendKey {
  const LegendKey(this.color, this.rect, {this.line = false});
  final int color;
  final Rect rect;
  final bool line;
}

/// Geometry for one chart at one width. Painting, hit testing and image
/// export all read it, so they agree to the pixel.
class ChartLayout {
  const ChartLayout({
    required this.form,
    required this.size,
    required this.plot,
    this.grid = const [],
    this.baseline = 0,
    this.texts = const [],
    this.keys = const [],
    this.bars = const [],
    this.lines = const [],
    this.area = false,
    this.markers = false,
    this.centers = const [],
    this.band = 0,
    this.slices = const [],
    this.center = Offset.zero,
    this.radius = 0,
    this.hole = 0,
  });

  final ChartForm form;
  final Size size;
  final Rect plot;

  /// Gridline positions on the value axis: y for columns and lines, x for
  /// rows.
  final List<double> grid;
  final double baseline;
  final List<PlacedText> texts;
  final List<LegendKey> keys;
  final List<ChartBar> bars;
  final List<ChartLine> lines;
  final bool area;
  final bool markers;

  /// Category positions: x for columns and lines, y for rows.
  final List<double> centers;
  final double band;
  final List<ChartSlice> slices;
  final Offset center;
  final double radius;
  final double hole;

  /// The category under [point], for tooltips.
  int? categoryAt(Offset point) {
    if (centers.isEmpty) return null;
    final inside = plot.inflate(12);
    if (form == ChartForm.rows) {
      if (point.dy < inside.top || point.dy > inside.bottom) return null;
      return _nearest(point.dy);
    }
    if (point.dx < inside.left || point.dx > inside.right) return null;
    return _nearest(point.dx);
  }

  int _nearest(double position) {
    var best = 0;
    for (var i = 1; i < centers.length; i++) {
      if ((centers[i] - position).abs() < (centers[best] - position).abs()) {
        best = i;
      }
    }
    return best;
  }

  /// The slice under [point], allowing a margin around the ring.
  int? sliceAt(Offset point) {
    final offset = point - center;
    final distance = offset.distance;
    if (distance > radius + 12 || distance < math.max(0, hole - 12)) {
      return null;
    }
    final angle = math.atan2(offset.dy, offset.dx);
    for (final (index, slice) in slices.indexed) {
      if ((angle - slice.start) % (2 * math.pi) <= slice.sweep) return index;
    }
    return null;
  }
}

const _barMax = 24.0;
const _gap = 2.0;

ChartLayout layoutChart(
  ChartSpec spec,
  double width,
  TextMeasurer text,
  ChartFormat format, {
  required String other,
  required String sourcePrefix,
}) {
  final layout = spec.isPie
      ? _pie(spec, width, text, format, other)
      : spec.type == ChartType.bar && _rows(spec, width, text)
      ? _rowsLayout(spec, width, text, format)
      : _axes(spec, width, text, format);
  final source = spec.source;
  if (source == null) return layout;
  final caption = '$sourcePrefix$source';
  final size = text.measure(
    caption,
    VisualTextRole.caption,
    maxWidth: width,
    maxLines: 2,
  );
  final top = layout.size.height + 10;
  return ChartLayout(
    form: layout.form,
    size: Size(width, top + size.height),
    plot: layout.plot,
    grid: layout.grid,
    baseline: layout.baseline,
    texts: [
      ...layout.texts,
      PlacedText(
        caption,
        VisualTextRole.caption,
        Offset(0, top),
        maxWidth: width,
        maxLines: 2,
      ),
    ],
    keys: layout.keys,
    bars: layout.bars,
    lines: layout.lines,
    area: layout.area,
    markers: layout.markers,
    centers: layout.centers,
    band: layout.band,
    slices: layout.slices,
    center: layout.center,
    radius: layout.radius,
    hole: layout.hole,
  );
}

bool _rows(ChartSpec spec, double width, TextMeasurer text) {
  if (spec.horizontal case final horizontal?) return horizontal;
  if (looksTemporal(spec.labels)) return false;
  final count = spec.labels.length;
  if (count > 12) return true;
  final band = (width - 48) / count;
  return spec.labels.any(
    (label) => text.measure(label, VisualTextRole.caption).width > band - 6,
  );
}

double _lineHeight(TextMeasurer text, VisualTextRole role) =>
    text.measure('Ag', role).height;

/// Series keys in wrapped rows above the plot. One series needs no legend:
/// the title already names it.
(List<LegendKey>, List<PlacedText>, double) _legend(
  ChartSpec spec,
  double width,
  TextMeasurer text, {
  required bool lines,
}) {
  if (spec.series.length < 2) return (const [], const [], 0);
  final keys = <LegendKey>[];
  final texts = <PlacedText>[];
  final rowHeight = _lineHeight(text, VisualTextRole.caption);
  final keyWidth = lines ? 14.0 : 10.0;
  var x = 0.0;
  var y = 0.0;
  for (final (index, series) in spec.series.indexed) {
    final maxWidth = width - keyWidth - 6;
    final label = text.measure(
      series.name,
      VisualTextRole.caption,
      maxWidth: maxWidth,
      maxLines: 1,
    );
    final itemWidth = keyWidth + 6 + label.width;
    if (x > 0 && x + itemWidth > width) {
      x = 0;
      y += rowHeight + 4;
    }
    keys.add(
      LegendKey(
        index,
        lines
            ? Rect.fromLTWH(x, y + rowHeight / 2 - 1, keyWidth, 2)
            : Rect.fromLTWH(x, y + rowHeight / 2 - 5, keyWidth, 10),
        line: lines,
      ),
    );
    texts.add(
      PlacedText(
        series.name,
        VisualTextRole.caption,
        Offset(x + keyWidth + 6, y),
        maxWidth: maxWidth,
        maxLines: 1,
      ),
    );
    x += itemWidth + 16;
  }
  return (keys, texts, y + rowHeight + 12);
}

/// Labels that fit every [stride] categories.
int _stride(List<double> widths, double spacing) {
  var stride = 1;
  while (stride < widths.length &&
      widths.indexed.any(
        (entry) => entry.$1 % stride == 0 && entry.$2 > spacing * stride - 6,
      )) {
    stride++;
  }
  return stride;
}

ChartLayout _axes(
  ChartSpec spec,
  double width,
  TextMeasurer text,
  ChartFormat format,
) {
  final columns = spec.type == ChartType.bar;
  final area = spec.type == ChartType.area;
  final count = spec.labels.length;
  final seriesCount = spec.series.length;
  final (keys, legendTexts, legendHeight) = _legend(
    spec,
    width,
    text,
    lines: !columns,
  );

  // Value range. Stacks add up per category.
  final stacked = spec.stacked && seriesCount > 1;
  var low = double.infinity;
  var high = double.negativeInfinity;
  final totals = List<double>.filled(count, 0);
  final positive = List<double>.filled(count, 0);
  final negative = List<double>.filled(count, 0);
  for (var i = 0; i < count; i++) {
    for (final series in spec.series) {
      final value = series.data[i];
      if (value == null) continue;
      if (value >= 0) {
        positive[i] += value;
      } else {
        negative[i] += value;
      }
      if (!stacked) {
        low = math.min(low, value);
        high = math.max(high, value);
      }
    }
    totals[i] = positive[i] + negative[i];
    if (stacked) {
      low = math.min(low, negative[i]);
      high = math.max(high, positive[i]);
    }
  }
  if (!low.isFinite) low = high = 0;
  // Bars and areas encode length, so they start at zero. Lines may zoom in
  // unless zero is close to the data anyway.
  final includeZero =
      columns ||
      area ||
      (low >= 0 && low <= high * .5) ||
      (high <= 0 && high >= low * .5);
  final scale = NiceScale.of(low, high, includeZero: includeZero);
  final ticks = scale.ticks;
  final tickTexts = [for (final tick in ticks) format.axis(tick)];
  final tickWidth = tickTexts
      .map((t) => text.measure(t, VisualTextRole.tabular).width)
      .fold(0.0, math.max);
  final lineHeight = _lineHeight(text, VisualTextRole.caption);
  final valueHeight = _lineHeight(text, VisualTextRole.captionStrong);
  final labelWidths = [
    for (final label in spec.labels)
      text.measure(label, VisualTextRole.caption).width,
  ];

  var left = tickWidth + 8;
  var right = width - 2;
  if (!columns && count > 1) {
    left = math.max(left, labelWidths.first / 2);
    right = width - math.max(2, labelWidths.last / 2);
  }
  final plotWidth = right - left;
  final band = columns ? plotWidth / count : 0.0;
  final single = columns && (seriesCount == 1 || stacked);
  final valueTexts = [for (final total in totals) format.compact(total)];
  final showValues =
      single &&
      count <= 12 &&
      valueTexts.every(
        (t) => text.measure(t, VisualTextRole.captionStrong).width <= band - 2,
      );
  final top =
      legendHeight + (showValues ? valueHeight + 4 : lineHeight / 2 + 2);
  final plotHeight = (width * .5).clamp(150.0, 230.0);
  final plot = Rect.fromLTWH(left, top, plotWidth, plotHeight);
  double y(double value) => plot.bottom - scale.fraction(value) * plot.height;
  final baseline = y(includeZero ? 0 : scale.min);

  final texts = <PlacedText>[...legendTexts];
  for (final (index, tick) in ticks.indexed) {
    final size = text.measure(tickTexts[index], VisualTextRole.tabular);
    texts.add(
      PlacedText(
        tickTexts[index],
        VisualTextRole.tabular,
        Offset(left - 8 - size.width, y(tick) - size.height / 2),
      ),
    );
  }

  final centers = [
    for (var i = 0; i < count; i++)
      columns
          ? left + band * (i + .5)
          : count == 1
          ? plot.center.dx
          : left + plotWidth * i / (count - 1),
  ];
  final spacing = columns
      ? band
      : count > 1
      ? plotWidth / (count - 1)
      : plotWidth;
  final stride = _stride(labelWidths, spacing);
  final shown = <int>{for (var i = 0; i < count; i += stride) i};
  // Lines also label their last point when it does not collide.
  final previous = shown.last;
  if (!columns &&
      previous != count - 1 &&
      centers[count - 1] - centers[previous] >=
          (labelWidths[previous] + labelWidths[count - 1]) / 2 + 6) {
    shown.add(count - 1);
  }
  for (final index in shown) {
    final maxWidth = math.max(spacing * stride - 6, 24.0);
    final size = text.measure(
      spec.labels[index],
      VisualTextRole.caption,
      maxWidth: maxWidth,
      maxLines: 1,
    );
    texts.add(
      PlacedText(
        spec.labels[index],
        VisualTextRole.caption,
        Offset(centers[index] - size.width / 2, plot.bottom + 6),
        maxWidth: maxWidth,
        maxLines: 1,
        align: TextAlign.center,
      ),
    );
  }

  final bars = <ChartBar>[];
  final lines = <ChartLine>[];
  if (columns) {
    for (var i = 0; i < count; i++) {
      if (stacked) {
        final barWidth = math.min(band * .62, _barMax);
        final x = centers[i] - barWidth / 2;
        bars.addAll(
          _stack(spec, i, BarEnd.up, BarEnd.down, (from, to) {
            final gap = from == 0 ? 0.0 : _gap;
            return to > from
                ? Rect.fromLTRB(x, y(to), x + barWidth, y(from) - gap)
                : Rect.fromLTRB(x, y(from) + gap, x + barWidth, y(to));
          }),
        );
      } else {
        final groupWidth = math.min(
          band * .72,
          seriesCount * _barMax + (seriesCount - 1) * _gap,
        );
        final barWidth = (groupWidth - (seriesCount - 1) * _gap) / seriesCount;
        for (final (s, series) in spec.series.indexed) {
          final value = series.data[i];
          if (value == null) continue;
          final x = centers[i] - groupWidth / 2 + s * (barWidth + _gap);
          bars.add(
            ChartBar(
              s,
              i,
              value >= 0
                  ? Rect.fromLTRB(x, y(value), x + barWidth, baseline)
                  : Rect.fromLTRB(x, baseline, x + barWidth, y(value)),
              value >= 0 ? BarEnd.up : BarEnd.down,
            ),
          );
        }
      }
      if (showValues && spec.series.any((s) => s.data[i] != null)) {
        final label = valueTexts[i];
        final size = text.measure(label, VisualTextRole.captionStrong);
        final end = totals[i] >= 0
            ? y(stacked ? positive[i] : totals[i]) - 4 - size.height
            : y(stacked ? negative[i] : totals[i]) + 4;
        texts.add(
          PlacedText(
            label,
            VisualTextRole.captionStrong,
            Offset(centers[i] - size.width / 2, end),
            ink: ChartInk.ink,
          ),
        );
      }
    }
  } else {
    List<Offset?>? below;
    final running = List<double>.filled(count, 0);
    for (final (s, series) in spec.series.indexed) {
      final points = <Offset?>[];
      for (var i = 0; i < count; i++) {
        final value = series.data[i];
        if (stacked) {
          running[i] += value ?? 0;
          points.add(Offset(centers[i], y(running[i])));
        } else {
          points.add(value == null ? null : Offset(centers[i], y(value)));
        }
      }
      lines.add(ChartLine(s, points, lower: stacked && area ? below : null));
      below = points;
    }
  }

  final bottom = plot.bottom + 6 + lineHeight;
  return ChartLayout(
    form: columns ? ChartForm.columns : ChartForm.lines,
    size: Size(width, bottom),
    plot: plot,
    grid: [for (final tick in ticks) y(tick)],
    baseline: baseline,
    texts: texts,
    keys: keys,
    bars: bars,
    lines: lines,
    area: area,
    markers: count <= 24,
    centers: centers,
    band: spacing,
  );
}

/// Stacks one category from the baseline: positive values one way, negative
/// values the other. [segment] maps a value range to its rectangle, leaving
/// the surface gap between neighbours. Only the outermost segment on each
/// side carries the rounded data end.
List<ChartBar> _stack(
  ChartSpec spec,
  int index,
  BarEnd positiveEnd,
  BarEnd negativeEnd,
  Rect Function(double from, double to) segment,
) {
  final ups = <ChartBar>[];
  final downs = <ChartBar>[];
  var up = 0.0;
  var down = 0.0;
  for (final (s, series) in spec.series.indexed) {
    final value = series.data[index];
    if (value == null || value == 0) continue;
    if (value > 0) {
      ups.add(ChartBar(s, index, segment(up, up + value), BarEnd.none));
      up += value;
    } else {
      downs.add(ChartBar(s, index, segment(down, down + value), BarEnd.none));
      down += value;
    }
  }
  List<ChartBar> capped(List<ChartBar> bars, BarEnd end) => [
    for (final (i, bar) in bars.indexed)
      i == bars.length - 1
          ? ChartBar(bar.series, bar.index, bar.rect, end)
          : bar,
  ];
  return [...capped(ups, positiveEnd), ...capped(downs, negativeEnd)];
}

ChartLayout _rowsLayout(
  ChartSpec spec,
  double width,
  TextMeasurer text,
  ChartFormat format,
) {
  final count = spec.labels.length;
  final seriesCount = spec.series.length;
  final stacked = spec.stacked && seriesCount > 1;
  final (keys, legendTexts, legendHeight) = _legend(
    spec,
    width,
    text,
    lines: false,
  );
  var low = double.infinity;
  var high = double.negativeInfinity;
  final totals = List<double>.filled(count, 0);
  final positive = List<double>.filled(count, 0);
  final negative = List<double>.filled(count, 0);
  for (var i = 0; i < count; i++) {
    for (final series in spec.series) {
      final value = series.data[i];
      if (value == null) continue;
      if (value >= 0) {
        positive[i] += value;
      } else {
        negative[i] += value;
      }
      if (!stacked) {
        low = math.min(low, value);
        high = math.max(high, value);
      }
    }
    totals[i] = positive[i] + negative[i];
    if (stacked) {
      low = math.min(low, negative[i]);
      high = math.max(high, positive[i]);
    }
  }
  if (!low.isFinite) low = high = 0;
  final scale = NiceScale.of(low, high, includeZero: true);
  final ticks = scale.ticks;
  final tickTexts = [for (final tick in ticks) format.axis(tick)];
  final tickHeight = _lineHeight(text, VisualTextRole.tabular);
  final labelColumn = math.min(
    spec.labels
        .map((label) => text.measure(label, VisualTextRole.caption).width)
        .fold(0.0, math.max),
    width * .38,
  );
  final labelSizes = [
    for (final label in spec.labels)
      text.measure(
        label,
        VisualTextRole.caption,
        maxWidth: labelColumn,
        maxLines: 2,
      ),
  ];
  final single = seriesCount == 1 || stacked;
  final valueTexts = [for (final total in totals) format.compact(total)];
  final valueWidth = single
      ? valueTexts
            .map((t) => text.measure(t, VisualTextRole.captionStrong).width)
            .fold(0.0, math.max)
      : 0.0;
  final lastTick = text.measure(tickTexts.last, VisualTextRole.tabular).width;
  final thickness = single ? 18.0 : 12.0;
  final block = stacked
      ? thickness
      : seriesCount * thickness + (seriesCount - 1) * _gap;
  final rowHeight =
      math.max(labelSizes.map((s) => s.height).fold(0.0, math.max), block) + 12;
  final left = labelColumn + 10;
  final right = width - math.max(single ? valueWidth + 6 : 2, lastTick / 2 + 2);
  final plot = Rect.fromLTRB(
    left,
    legendHeight,
    right,
    legendHeight + count * rowHeight,
  );
  double x(double value) => plot.left + scale.fraction(value) * plot.width;
  final baseline = x(0);
  final texts = <PlacedText>[...legendTexts];
  // Side by side, tick labels can collide: label every other one, or fewer.
  final tickWidths = [
    for (final tick in tickTexts)
      text.measure(tick, VisualTextRole.tabular).width,
  ];
  final tickSpacing = ticks.length > 1 ? x(ticks[1]) - x(ticks[0]) : width;
  final tickStride = _stride(tickWidths, tickSpacing);
  for (final (index, tick) in ticks.indexed) {
    if (index % tickStride != 0) continue;
    texts.add(
      PlacedText(
        tickTexts[index],
        VisualTextRole.tabular,
        Offset(
          (x(tick) - tickWidths[index] / 2).clamp(
            0.0,
            width - tickWidths[index],
          ),
          plot.bottom + 6,
        ),
      ),
    );
  }
  final centers = <double>[];
  final bars = <ChartBar>[];
  for (var i = 0; i < count; i++) {
    final center = plot.top + rowHeight * (i + .5);
    centers.add(center);
    texts.add(
      PlacedText(
        spec.labels[i],
        VisualTextRole.caption,
        Offset(
          labelColumn - labelSizes[i].width,
          center - labelSizes[i].height / 2,
        ),
        maxWidth: labelColumn,
        maxLines: 2,
        align: TextAlign.right,
      ),
    );
    if (stacked) {
      final top = center - thickness / 2;
      bars.addAll(
        _stack(spec, i, BarEnd.right, BarEnd.left, (from, to) {
          final gap = from == 0 ? 0.0 : _gap;
          return to > from
              ? Rect.fromLTRB(x(from) + gap, top, x(to), top + thickness)
              : Rect.fromLTRB(x(to), top, x(from) - gap, top + thickness);
        }),
      );
    } else {
      for (final (s, series) in spec.series.indexed) {
        final value = series.data[i];
        if (value == null) continue;
        final top = center - block / 2 + s * (thickness + _gap);
        bars.add(
          ChartBar(
            s,
            i,
            value >= 0
                ? Rect.fromLTRB(baseline, top, x(value), top + thickness)
                : Rect.fromLTRB(x(value), top, baseline, top + thickness),
            value >= 0 ? BarEnd.right : BarEnd.left,
          ),
        );
      }
    }
    if (single && spec.series.any((s) => s.data[i] != null)) {
      final label = valueTexts[i];
      final size = text.measure(label, VisualTextRole.captionStrong);
      final end = totals[i] >= 0
          ? x(stacked ? positive[i] : totals[i]) + 6
          : x(stacked ? negative[i] : totals[i]) - 6 - size.width;
      if (end >= plot.left - 2 || totals[i] >= 0) {
        texts.add(
          PlacedText(
            label,
            VisualTextRole.captionStrong,
            Offset(end, center - size.height / 2),
            ink: ChartInk.ink,
          ),
        );
      }
    }
  }
  return ChartLayout(
    form: ChartForm.rows,
    size: Size(width, plot.bottom + 6 + tickHeight),
    plot: plot,
    grid: [for (final tick in ticks) x(tick)],
    baseline: baseline,
    texts: texts,
    keys: keys,
    bars: bars,
    centers: centers,
    band: rowHeight,
  );
}

ChartLayout _pie(
  ChartSpec spec,
  double width,
  TextMeasurer text,
  ChartFormat format,
  String other,
) {
  final values = spec.series.first.data;
  final entries = [
    for (var i = 0; i < spec.labels.length; i++)
      if ((values[i] ?? 0) > 0) (i, spec.labels[i], values[i]!),
  ]..sort((a, b) => b.$3.compareTo(a.$3));
  final kept = entries.length > 6 ? entries.sublist(0, 5) : entries;
  final rest = entries.length > 6
      ? entries.sublist(5)
      : const <(int, String, double)>[];
  final parts = <(String, double, List<int>)>[
    for (final entry in kept) (entry.$2, entry.$3, [entry.$1]),
    if (rest.isNotEmpty)
      (
        other,
        rest.fold<double>(0, (sum, entry) => sum + entry.$3),
        [for (final entry in rest) entry.$1],
      ),
  ];
  final total = parts.fold<double>(0, (sum, part) => sum + part.$2);
  final wide = width >= 440;
  final diameter = wide
      ? math.min(200.0, width * .42)
      : math.min(width * .66, 230.0);
  final radius = diameter / 2;
  final lineHeight = _lineHeight(text, VisualTextRole.caption);
  final rowHeight = lineHeight + 8;
  // Values that are already percentages need no second share.
  final details = [
    for (final part in parts)
      spec.unit == '%'
          ? format.compact(part.$2)
          : '${format.compact(part.$2)} · ${format.percent(part.$2 / total)}',
  ];
  final detailWidth = details
      .map((d) => text.measure(d, VisualTextRole.caption).width)
      .fold(0.0, math.max);
  final legendLeft = wide ? diameter + 28 : 0.0;
  final legendWidth = width - legendLeft;
  final legendHeight = parts.length * rowHeight;
  final height = wide
      ? math.max(diameter, legendHeight) + 8
      : diameter + 20 + legendHeight;
  final center = wide
      ? Offset(radius, height / 2)
      : Offset(width / 2, radius + 4);
  final legendTop = wide ? (height - legendHeight) / 2 : diameter + 20;
  final keys = <LegendKey>[];
  final texts = <PlacedText>[];
  final slices = <ChartSlice>[];
  var start = -math.pi / 2;
  for (final (index, part) in parts.indexed) {
    final sweep = 2 * math.pi * part.$2 / total;
    slices.add(
      ChartSlice(
        part.$3.length > 1 ? -1 : index,
        part.$1,
        part.$2,
        start,
        sweep,
        part.$3,
      ),
    );
    start += sweep;
    final top = legendTop + index * rowHeight;
    keys.add(
      LegendKey(
        part.$3.length > 1 ? -1 : index,
        Rect.fromLTWH(legendLeft, top + (rowHeight - 10) / 2, 10, 10),
      ),
    );
    final detail = text.measure(details[index], VisualTextRole.caption);
    texts.add(
      PlacedText(
        part.$1,
        VisualTextRole.caption,
        Offset(legendLeft + 18, top + 4),
        ink: ChartInk.ink,
        maxWidth: math.max(legendWidth - 18 - detailWidth - 12, 24),
        maxLines: 1,
      ),
    );
    texts.add(
      PlacedText(
        details[index],
        VisualTextRole.caption,
        Offset(legendLeft + legendWidth - detail.width, top + 4),
      ),
    );
  }
  return ChartLayout(
    form: ChartForm.pie,
    size: Size(width, height),
    plot: Rect.fromCircle(center: center, radius: radius),
    texts: texts,
    keys: keys,
    slices: slices,
    center: center,
    radius: radius,
    hole: spec.type == ChartType.donut ? radius * .6 : 0,
  );
}
