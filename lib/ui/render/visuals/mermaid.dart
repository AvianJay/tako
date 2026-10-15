import 'chart_spec.dart';
import 'flowchart.dart';
import 'mindmap.dart';
import 'sequence.dart';

/// A Mermaid diagram Tako can draw itself.
abstract base class MermaidDiagram {
  const MermaidDiagram(this.title);

  /// From front matter or a `title` statement.
  final String? title;
}

/// `pie` and single-mark `xychart-beta` diagrams, drawn as charts.
final class MermaidChart extends MermaidDiagram {
  MermaidChart(this.spec) : super(spec.title);
  final ChartSpec spec;
}

/// Parses a supported diagram, or returns null for other diagram types, which
/// stay code. Throws [FormatException] for a supported type it cannot read.
MermaidDiagram? parseMermaid(String source) {
  var text = source.replaceAll('\r\n', '\n');
  String? title;
  final front = RegExp(
    r'^\s*---[ \t]*\n([\s\S]*?)\n[ \t]*---[ \t]*(?:\n|$)',
  ).firstMatch(text);
  if (front != null) {
    title = RegExp(
      r'^\s*title\s*:\s*(.+?)\s*$',
      multiLine: true,
    ).firstMatch(front[1]!)?[1];
    if (title != null) title = cleanMermaidText(title);
    text = text.substring(front.end);
  }
  text = text.replaceAll(RegExp(r'%%\{[\s\S]*?\}%%'), '');
  final lines = [
    for (final line in text.split('\n'))
      if (line.trim().isNotEmpty && !line.trimLeft().startsWith('%%')) line,
  ];
  if (lines.isEmpty) return null;
  final header = lines.first.trim();
  final rest = lines.sublist(1);
  final keyword =
      RegExp(r'^[A-Za-z-]+').firstMatch(header)?[0]?.toLowerCase() ?? '';
  if (rest.length > 1500) throw const FormatException('Diagram is too large');
  return switch (keyword) {
    'flowchart' ||
    'graph' ||
    'flowchart-elk' => parseFlowchart(header, rest, title),
    'sequencediagram' => parseSequence(rest, title),
    'mindmap' => parseMindmap(rest, title),
    'pie' => _pie(header, rest, title),
    'xychart-beta' || 'xychart' => _xyChart(header, rest, title),
    _ => null,
  };
}

/// Mermaid label text as plain text: quotes, Markdown strings, line breaks,
/// HTML tags and entity codes resolved.
String cleanMermaidText(String text) {
  var value = text.trim();
  if (value.length >= 2 &&
      (value.startsWith('"') && value.endsWith('"') ||
          value.startsWith("'") && value.endsWith("'"))) {
    value = value.substring(1, value.length - 1).trim();
  }
  if (value.length >= 2 && value.startsWith('`') && value.endsWith('`')) {
    value = value.substring(1, value.length - 1);
  }
  value = value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</?[A-Za-z][^<>]*>'), '')
      .replaceAll(RegExp(r'fa[bsr]?:fa-[\w-]+\s*'), '')
      .replaceAll(r'\n', '\n')
      .replaceAllMapped(RegExp(r'[#&](#?)(\w+);'), (match) {
        final code = match[2]!;
        final number = int.tryParse(code);
        if (number != null && number >= 32 && number <= 0x10ffff) {
          return String.fromCharCode(number);
        }
        return switch (code.toLowerCase()) {
              'quot' => '"',
              'amp' => '&',
              'lt' => '<',
              'gt' => '>',
              'apos' => "'",
              'nbsp' => ' ',
              _ => null,
            } ??
            match[0]!;
      })
      .replaceAll('**', '')
      .replaceAll('__', '');
  return value.split('\n').map((line) => line.trim()).join('\n').trim();
}

MermaidChart _pie(String header, List<String> lines, String? title) {
  var heading =
      RegExp(r'\btitle\s+(.+)$').firstMatch(header)?[1]?.trim() ?? title;
  final labels = <String>[];
  final values = <double?>[];
  final entry = RegExp(
    r'''^\s*(?:"([^"]*)"|'([^']*)'|([^:]+?))\s*:\s*([-+\d.,eE]+)\s*$''',
  );
  for (final line in lines) {
    final trimmed = line.trim();
    if (RegExp(r'^title\s').hasMatch(trimmed)) {
      heading = trimmed.substring(5).trim();
      continue;
    }
    if (trimmed == 'showData') continue;
    final match = entry.firstMatch(trimmed);
    if (match == null) continue;
    labels.add(cleanMermaidText(match[1] ?? match[2] ?? match[3]!));
    values.add(double.tryParse(match[4]!.replaceAll(',', '')));
  }
  if (labels.isEmpty ||
      values.any((v) => v == null || v < 0 || !v.isFinite) ||
      values.fold<double>(0, (sum, v) => sum + v!) <= 0 ||
      labels.length > ChartSpec.maxCategories) {
    throw const FormatException('A pie needs positive values');
  }
  return MermaidChart(
    ChartSpec(
      type: ChartType.pie,
      title: heading == null ? null : cleanMermaidText(heading),
      labels: labels,
      series: [ChartSeries('', values)],
    ),
  );
}

/// Only charts made of bars alone or lines alone; a mixed chart would need a
/// second mark type on one axis, so it stays code.
MermaidChart? _xyChart(String header, List<String> lines, String? title) {
  var heading = title;
  var labels = <String>[];
  final bars = <List<double?>>[];
  final lineSeries = <List<double?>>[];
  List<String> items(String list) => [
    for (final item in list.split(','))
      if (item.trim().isNotEmpty) cleanMermaidText(item),
  ];
  for (final line in lines) {
    final trimmed = line.trim();
    final list = RegExp(r'\[(.*)\]').firstMatch(trimmed)?[1];
    if (RegExp(r'^title\s').hasMatch(trimmed)) {
      heading = cleanMermaidText(trimmed.substring(5));
    } else if (trimmed.startsWith('x-axis') && list != null) {
      labels = items(list);
    } else if (trimmed.startsWith('bar') && list != null) {
      bars.add([for (final v in items(list)) double.tryParse(v)]);
    } else if (trimmed.startsWith('line') && list != null) {
      lineSeries.add([for (final v in items(list)) double.tryParse(v)]);
    }
  }
  if (bars.isNotEmpty == lineSeries.isNotEmpty) return null;
  final data = bars.isNotEmpty ? bars : lineSeries;
  final count = data
      .map((d) => d.length)
      .fold(labels.length, (a, b) => a > b ? a : b);
  if (count == 0 || count > ChartSpec.maxCategories) {
    throw const FormatException('Unsupported chart size');
  }
  return MermaidChart(
    ChartSpec(
      type: bars.isNotEmpty ? ChartType.bar : ChartType.line,
      title: heading,
      labels: [
        for (var i = 0; i < count; i++)
          i < labels.length ? labels[i] : '${i + 1}',
      ],
      series: [
        for (final (index, values) in data.indexed)
          ChartSeries(data.length == 1 ? '' : '#${index + 1}', [
            for (var i = 0; i < count; i++)
              i < values.length ? values[i] : null,
          ]),
      ],
      horizontal: RegExp(r'\bhorizontal\b').hasMatch(header) ? true : null,
    ),
  );
}
