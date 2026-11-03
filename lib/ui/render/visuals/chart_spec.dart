import 'dart:convert';
import 'dart:math' as math;

enum ChartType { bar, line, area, pie, donut, radar, scatter }

class ChartSeries {
  const ChartSeries(this.name, this.data, {this.points = const []});
  final String name;

  /// One value per label; null leaves a gap.
  final List<double?> data;

  /// A scatter series has points instead of [data].
  final List<ChartPoint> points;
}

/// A scatter point, optionally named for its tooltip and table row.
class ChartPoint {
  const ChartPoint(this.x, this.y, [this.label]);
  final double x;
  final double y;
  final String? label;
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
    this.max,
    this.xLabel,
    this.yLabel,
    this.xUnit = '',
  });

  factory ChartSpec.parse(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('A chart is a JSON object');
    }
    final map = decoded.cast<String, Object?>();
    final chartJs = _map(map['data']);
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
      case 'radar' || 'spider' || 'spiderweb' || 'web':
        type = ChartType.radar;
      case 'scatter' || 'scatterplot' || 'xy' || 'xyplot' || 'points':
        return _scatter(map, chartJs);
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
    // A web needs three spokes, few enough to label, and values at or above
    // its centre. Other data reads as the same grouped bars.
    final radar =
        type == ChartType.radar &&
        count >= minAxes &&
        count <= maxAxes &&
        !padded.any((s) => s.data.any((v) => v != null && v < 0));
    final options = _map(map['options']);
    final radial = _map(_map(options['scales'])['r']);
    final legacy = _map(_map(options['scale'])['ticks']);
    final max = _number(
      map['max'] ??
          radial['max'] ??
          radial['suggestedMax'] ??
          legacy['max'] ??
          legacy['suggestedMax'],
    );
    final spec = ChartSpec(
      type: type == ChartType.radar && !radar ? ChartType.bar : type,
      title: _text(map['title']),
      labels: List.unmodifiable(labels),
      series: List.unmodifiable(padded),
      stacked: stacked,
      horizontal: horizontal,
      unit: _text(map['unit'] ?? map['suffix']) ?? '',
      source: _text(map['source']),
      max: radar && max != null && max > 0 ? max : null,
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

  /// Spokes on a radar; past them its labels no longer fit around a phone
  /// sized web.
  static const minAxes = 3;
  static const maxAxes = 12;

  /// Points across all series of a scatter chart.
  static const maxPoints = 500;

  /// Past the eighth categorical slot a chart is shown only as a table.
  static const maxDrawnSeries = 8;

  final ChartType type;
  final String? title;

  /// Categories; empty for scatter charts, whose series hold points.
  final List<String> labels;
  final List<ChartSeries> series;
  final bool stacked;

  /// Null lets the renderer choose.
  final bool? horizontal;

  /// Attached to values; on a scatter chart, to y values.
  final String unit;
  final String? source;

  /// A radar's outer ring, when the data has a natural top such as a
  /// ten-point rating. Null fits the scale to the data.
  final double? max;

  /// Scatter axis titles.
  final String? xLabel;
  final String? yLabel;

  /// Attached to scatter x values.
  final String xUnit;

  bool get isPie => type == ChartType.pie || type == ChartType.donut;
  bool get drawable => series.length <= maxDrawnSeries;
}

/// Points come as `[x, y]`, `{"x": 1, "y": 2, "label": "A"}` or Chart.js
/// datasets of either; series may also give parallel `x` and `y` lists.
/// Plain values pair with numeric labels as x, and other labels name the
/// points. Points without two numbers are dropped.
ChartSpec _scatter(Map<String, Object?> map, Map<String, Object?> chartJs) {
  final labels = _list(map['labels'] ?? map['categories'] ?? chartJs['labels']);
  final numeric = labels.isNotEmpty && labels.every((l) => _number(l) != null);
  final xs = numeric ? labels : _list(map['x']);
  final names = numeric ? const <Object?>[] : labels;
  final series = <ChartSeries>[];
  void addSeries(String name, Object? values, List<Object?> x, Object? text) {
    final own = _list(text);
    series.add(
      ChartSeries(
        name,
        const [],
        points: _points(_list(values), x, own.isEmpty ? names : own),
      ),
    );
  }

  final rawSeries = map['series'] ?? map['datasets'] ?? chartJs['datasets'];
  if (rawSeries is List &&
      rawSeries.isNotEmpty &&
      rawSeries.every((item) => item is Map)) {
    for (final item in rawSeries.cast<Map<dynamic, dynamic>>()) {
      final entry = item.cast<String, Object?>();
      final x = _list(entry['x']);
      addSeries(
        _text(entry['name'] ?? entry['label'] ?? entry['title']) ?? '',
        entry['data'] ??
            entry['points'] ??
            entry['values'] ??
            (x.isEmpty ? null : entry['y']),
        x.isEmpty ? xs : x,
        entry['labels'] ?? entry['text'],
      );
    }
  } else if (rawSeries is List && rawSeries.isNotEmpty) {
    addSeries('', rawSeries, xs, null);
  } else {
    final values = map['data'] is List
        ? map['data']
        : map['points'] ?? map['values'] ?? map['y'];
    if (_list(values).isNotEmpty) addSeries('', values, xs, null);
  }
  if (series.isEmpty) throw const FormatException('A chart needs values');
  if (series.length > ChartSpec.maxSeries) {
    throw const FormatException('Too many series');
  }
  final total = series.fold<int>(0, (sum, s) => sum + s.points.length);
  if (total == 0) throw const FormatException('A chart needs numbers');
  if (total > ChartSpec.maxPoints) {
    throw const FormatException('Too many points');
  }
  return ChartSpec(
    type: ChartType.scatter,
    title: _text(map['title']),
    labels: const [],
    series: List.unmodifiable([
      for (final (index, s) in series.indexed)
        ChartSeries(
          s.name.isNotEmpty || series.length == 1 ? s.name : '#${index + 1}',
          const [],
          points: List.unmodifiable(s.points),
        ),
    ]),
    unit: _text(map['unit'] ?? map['yUnit'] ?? map['suffix']) ?? '',
    xUnit: _text(map['xUnit']) ?? '',
    source: _text(map['source']),
    xLabel: _axisTitle(map, 'x'),
    yLabel: _axisTitle(map, 'y'),
  );
}

List<ChartPoint> _points(
  List<Object?> values,
  List<Object?> xs,
  List<Object?> names,
) {
  final points = <ChartPoint>[];
  for (final (index, value) in values.indexed) {
    final (x, y, label) = switch (value) {
      [final String name, final x, final y, ...] when _number(name) == null => (
        _number(x),
        _number(y),
        _text(name),
      ),
      [final x, final y, final String name, ...] when _number(name) == null => (
        _number(x),
        _number(y),
        _text(name),
      ),
      [final x, final y, ...] => (_number(x), _number(y), null),
      final Map<dynamic, dynamic> point => (
        _number(point['x']),
        _number(point['y']),
        _text(point['label'] ?? point['name'] ?? point['title']),
      ),
      _ => (
        index < xs.length ? _number(xs[index]) : null,
        _number(value),
        null,
      ),
    };
    if (x == null || y == null) continue;
    points.add(
      ChartPoint(
        x,
        y,
        label ?? (index < names.length ? _text(names[index]) : null),
      ),
    );
  }
  return points;
}

/// `xLabel`, `xTitle`, an `xAxis` string or object, or Chart.js scale
/// titles.
String? _axisTitle(Map<String, Object?> map, String axis) {
  final scales = _map(_map(map['options'])['scales']);
  final legacy = _list(scales['${axis}Axes']);
  for (final candidate in [
    map['${axis}Label'],
    map['${axis}Title'],
    map['${axis}Axis'],
    scales[axis],
    if (legacy.isNotEmpty) _map(legacy.first)['scaleLabel'],
  ]) {
    if (_caption(candidate) case final title?) return title;
  }
  return null;
}

String? _caption(Object? value) => switch (value) {
  final Map<dynamic, dynamic> map => _caption(
    map['title'] ?? map['text'] ?? map['labelString'] ?? map['label'],
  ),
  _ => _text(value),
};

Map<String, Object?> _map(Object? value) => switch (value) {
  final Map<dynamic, dynamic> map => map.cast<String, Object?>(),
  _ => const <String, Object?>{},
};

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
