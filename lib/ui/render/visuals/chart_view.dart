import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'chart_layout.dart';
import 'chart_painter.dart';
import 'chart_scale.dart';
import 'chart_spec.dart';
import 'visual_cache.dart';
import 'visual_labels.dart';
import 'visual_palette.dart';
import 'visual_text.dart';

final _layouts =
    LruCache<(ChartSpec, double, String, VisualLabels), ChartLayout>(48);

ChartLayout chartLayout(
  ChartSpec spec,
  double width,
  VisualText text,
  VisualLabels labels,
) => _layouts.putIfAbsent(
  (spec, width, text.signature, labels),
  () => layoutChart(
    spec,
    width,
    text,
    ChartFormat(labels.localeName, spec.unit),
    other: labels.other,
    sourcePrefix: labels.sourcePrefix,
  ),
);

/// A tappable chart. It grows in once when [animate] is set, which the host
/// does only for charts that first appear while a reply streams.
class ChartView extends StatefulWidget {
  const ChartView({
    required this.spec,
    required this.labels,
    required this.fallback,
    this.animate = false,
    super.key,
  });

  final ChartSpec spec;
  final VisualLabels labels;

  /// Shown instead when the chart cannot be laid out.
  final WidgetBuilder fallback;
  final bool animate;

  @override
  State<ChartView> createState() => _ChartViewState();
}

class _ChartViewState extends State<ChartView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _growth = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
    value: widget.animate ? 0 : 1,
  );
  int? _selected;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _growth.value = 1;
    } else if (_growth.value == 0) {
      _growth.forward();
    }
  }

  @override
  void didUpdateWidget(ChartView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spec != widget.spec) _selected = null;
  }

  @override
  void dispose() {
    _growth.dispose();
    super.dispose();
  }

  void _select(ChartLayout layout, Offset position, {bool toggle = true}) {
    final index = layout.form == ChartForm.pie
        ? layout.sliceAt(position)
        : layout.categoryAt(position);
    setState(() {
      _selected = toggle && index == _selected ? null : index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = VisualPalette.of(context);
    final text = VisualText.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 320.0;
        final ChartLayout layout;
        try {
          layout = chartLayout(widget.spec, width, text, widget.labels);
        } on Object {
          return widget.fallback(context);
        }
        final lines = layout.form == ChartForm.lines;
        return Semantics(
          label: chartSummary(widget.spec, widget.labels),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _select(layout, details.localPosition),
            onHorizontalDragUpdate: lines
                ? (details) =>
                      _select(layout, details.localPosition, toggle: false)
                : null,
            child: RepaintBoundary(
              child: CustomPaint(
                size: layout.size,
                painter: ChartPainter(
                  layout: layout,
                  spec: widget.spec,
                  palette: palette,
                  text: text,
                  format: ChartFormat(
                    widget.labels.localeName,
                    widget.spec.unit,
                  ),
                  totalLabel: widget.labels.total,
                  selected: _selected,
                  progress: _growth,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// What a screen reader hears instead of the drawing.
String chartSummary(ChartSpec spec, VisualLabels labels) {
  final format = ChartFormat(labels.localeName, spec.unit);
  final values = <String>[];
  for (var i = 0; i < spec.labels.length && i < 60; i++) {
    final parts = [
      for (final series in spec.series)
        if (series.data[i] case final value?)
          series.name.isEmpty || spec.series.length == 1
              ? format.full(value)
              : '${series.name} ${format.full(value)}',
    ];
    if (parts.isNotEmpty) values.add('${spec.labels[i]}: ${parts.join(', ')}');
  }
  return [?spec.title, labels.chart, values.join('; ')].join('. ');
}

/// The chart's values as a table: always available, so no value depends on
/// colour or on tapping.
class ChartTable extends StatelessWidget {
  const ChartTable({required this.spec, required this.labels, super.key});

  final ChartSpec spec;
  final VisualLabels labels;

  @override
  Widget build(BuildContext context) {
    final format = ChartFormat(labels.localeName, spec.unit);
    final theme = Theme.of(context);
    final numbers = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
    final heading = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    Widget cell(String value, {bool number = false, bool header = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            value,
            textAlign: number ? TextAlign.right : TextAlign.left,
            style: header ? heading : (number ? numbers : null),
          ),
        );
    final List<TableRow> rows;
    if (spec.isPie) {
      final values = spec.series.first.data;
      final total = values.fold<double>(0, (sum, v) => sum + (v ?? 0));
      rows = [
        TableRow(
          children: [
            cell('', header: true),
            cell(spec.series.first.name, header: true, number: true),
            cell('%', header: true, number: true),
          ],
        ),
        for (var i = 0; i < spec.labels.length; i++)
          TableRow(
            children: [
              cell(spec.labels[i]),
              cell(
                values[i] == null ? '—' : format.full(values[i]!),
                number: true,
              ),
              cell(
                values[i] == null ? '—' : format.percent(values[i]! / total),
                number: true,
              ),
            ],
          ),
      ];
    } else {
      rows = [
        TableRow(
          children: [
            cell('', header: true),
            for (final series in spec.series)
              cell(series.name, header: true, number: true),
          ],
        ),
        for (var i = 0; i < spec.labels.length; i++)
          TableRow(
            children: [
              cell(spec.labels[i]),
              for (final series in spec.series)
                cell(
                  series.data[i] == null ? '—' : format.full(series.data[i]!),
                  number: true,
                ),
            ],
          ),
      ];
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder(
          horizontalInside: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        children: rows,
      ),
    );
  }
}
