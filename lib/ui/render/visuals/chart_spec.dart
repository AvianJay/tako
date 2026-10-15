import 'dart:convert';
import 'dart:math' as math;

enum ChartType { bar, line, area, pie, donut }

class ChartSeries {
  const ChartSeries(this.name, this.data);
  final String name;

  /// One value per label; null leaves a gap.
  final List<double?> data;
}

/// A model-authored chart. Parsing is lenient about shape, because models
/// also write Chart.js configurations and plain value lists, but strict about
/// size and about having real numbers to draw.
class ChartSpec {
  const ChartSpec({
    required this.type,
    required this.labels,
    required this.series,
    this.title,
    this.stacked = false,
    this.horizontal,
    this.unit = '',
    this.source,
  });

  factory ChartSpec.parse(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('A chart is a JSON object');
    }
    final map = decoded.cast<String, Object?>();
    final chartJs = switch (map['data']) {
      final Map<dynamic, dynamic> data => data.cast<String, Object?>(),
      _ => const <String, Object?>{},
    };
    var stacked = _flag(map['stacked']) ?? false;
    var horizontal = _flag(map['horizontal']);
    final name = (_text(map['type']) ?? '').toLowerCase().replaceAll(
      RegExp(r'[\s_-]'),
      '',
    );
    final ChartType type;
    switch (name) {
      case '' || 'bar' || 'bars' || 'column' || 'columns' || 'histogram':
        type = ChartType.bar;
      case 'hbar' || 'horizontalbar' || 'barh' || 'row' || 'rows':
        type = ChartType.bar;
        horizontal ??= true;
      case 'stackedbar' || 'stackedcolumn':
        type = ChartType.bar;
        stacked = true;
      case 'line' || 'lines' || 'spline':
        type = ChartType.line;
      case 'area':
        type = ChartType.area;
      case 'stackedarea':
        type = ChartType.area;
        stacked = true;
      case 'pie':
        type = ChartType.pie;
      case 'donut' || 'doughnut' || 'ring':
        type = ChartType.donut;
      default:
        throw FormatException('Unsupported chart type: $name');
    }

    var labels = [
      for (final label in _list(
        map['labels'] ?? map['categories'] ?? map['x'] ?? chartJs['labels'],
      ))
        _label(label),
    ];
    final series = <ChartSeries>[];
    void addSeries(String name, Object? values) {
      series.add(
        ChartSeries(name, [for (final v in _list(values)) _number(v)]),
      );
    }

    final rawSeries = map['series'] ?? map['datasets'] ?? chartJs['datasets'];
    if (rawSeries is List && rawSeries.isNotEmpty) {
      if (rawSeries.every((item) => item is Map)) {
        for (final item in rawSeries.cast<Map<dynamic, dynamic>>()) {
          final entry = item.cast<String, Object?>();
          addSeries(
            _text(entry['name'] ?? entry['label'] ?? entry['title']) ?? '',
            entry['data'] ?? entry['values'] ?? entry['y'],
          );
        }
      } else {
        addSeries('', rawSeries);
      }
    } else {
      final values = map['data'] is List ? map['data'] : map['values'];
      final list = _list(values);
      if (list.isNotEmpty && list.every((item) => item is Map)) {
        // [{"label": "A", "value": 3}, ...], the usual pie shape.
        final items = [
          for (final item in list.cast<Map<dynamic, dynamic>>())
            item.cast<String, Object?>(),
        ];
        if (labels.isEmpty) {
          labels = [
            for (final item in items)
              _label(item['label'] ?? item['name'] ?? item['x']),
          ];
        }
        series.add(
          ChartSeries('', [
            for (final item in items)
              _number(item['value'] ?? item['y'] ?? item['count']),
          ]),
        );
      } else if (list.isNotEmpty) {
        addSeries('', list);
      }
    }
    if (series.isEmpty) throw const FormatException('A chart needs values');
    if (series.length > maxSeries) {
      throw const FormatException('Too many series');
    }
    final count = math.max(
      labels.length,
      series.map((s) => s.data.length).reduce(math.max),
    );
    if (count == 0 || count > maxCategories) {
      throw const FormatException('Unsupported number of categories');
    }
    labels = [
      for (var i = 0; i < count; i++)
        i < labels.length && labels[i].isNotEmpty ? labels[i] : '${i + 1}',
    ];
    final padded = [
      for (final (index, s) in series.indexed)
        ChartSeries(
          s.name.isNotEmpty || series.length == 1 ? s.name : '#${index + 1}',
          [
            for (var i = 0; i < count; i++)
              i < s.data.length ? s.data[i] : null,
          ],
        ),
    ];
    if (!padded.any((s) => s.data.any((v) => v != null))) {
      throw const FormatException('A chart needs numbers');
    }
    final spec = ChartSpec(
      type: type,
      title: _text(map['title']),
      labels: List.unmodifiable(labels),
      series: List.unmodifiable(padded),
      stacked: stacked,
      horizontal: horizontal,
      unit: _text(map['unit'] ?? map['suffix']) ?? '',
      source: _text(map['source']),
    );
    if (spec.isPie) {
      final values = padded.first.data;
      if (values.any((v) => v != null && v < 0)) {
        throw const FormatException('A pie cannot show negative values');
      }
      if (values.fold<double>(0, (sum, v) => sum + (v ?? 0)) <= 0) {
        throw const FormatException('A pie needs a positive total');
      }
    }
    return spec;
  }

  static const maxCategories = 200;
  static const maxSeries = 24;

  /// Past the eighth categorical slot a chart is shown only as a table.
  static const maxDrawnSeries = 8;

  final ChartType type;
  final String? title;
  final List<String> labels;
  final List<ChartSeries> series;
  final bool stacked;

  /// Null lets the renderer choose.
  final bool? horizontal;
  final String unit;
  final String? source;

  bool get isPie => type == ChartType.pie || type == ChartType.donut;
  bool get drawable => series.length <= maxDrawnSeries;
}

List<Object?> _list(Object? value) =>
    value is List ? value.cast<Object?>() : const [];

String? _text(Object? value) {
  final text = switch (value) {
    final String text => text.trim(),
    final num number => _label(number),
    _ => null,
  };
  return text == null || text.isEmpty ? null : text;
}

bool? _flag(Object? value) => switch (value) {
  final bool flag => flag,
  'true' => true,
  'false' => false,
  _ => null,
};

String _label(Object? value) => switch (value) {
  final String text => text.trim(),
  final int number => '$number',
  final num number when number == number.roundToDouble() =>
    number.toInt().toString(),
  final num number => '$number',
  _ => '',
};

double? _number(Object? value) {
  final number = switch (value) {
    final num number => number.toDouble(),
    final String text => double.tryParse(
      text.replaceAll(RegExp(r'[\s,%$€£¥]'), ''),
    ),
    final Map<dynamic, dynamic> point => _number(point['y'] ?? point['value']),
    _ => null,
  };
  return number != null && number.isFinite ? number : null;
}
