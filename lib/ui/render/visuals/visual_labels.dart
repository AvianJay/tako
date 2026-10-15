import 'package:flutter/foundation.dart';

/// Strings for charts, diagrams and callouts. The English defaults keep the
/// renderer usable without app localizations. Compared by value, so a host
/// that rebuilds its labels on every frame does not invalidate rendering.
@immutable
class VisualLabels {
  const VisualLabels({
    this.localeName = 'en',
    this.drawing = 'Drawing…',
    this.failed = "Couldn't draw this. Showing the source.",
    this.showTable = 'Show as table',
    this.showChart = 'Show chart',
    this.showCode = 'Show code',
    this.showDiagram = 'Show diagram',
    this.fullScreen = 'Full screen',
    this.shareImage = 'Share image',
    this.other = 'Other',
    this.total = 'Total',
    this.sourcePrefix = 'Source: ',
    this.chart = 'Chart',
    this.flowchart = 'Flowchart',
    this.sequence = 'Sequence diagram',
    this.mindmap = 'Mind map',
    this.note = 'Note',
    this.tip = 'Tip',
    this.important = 'Important',
    this.warning = 'Warning',
    this.caution = 'Caution',
  });

  /// An intl locale name such as `zh_TW`, used to format numbers.
  final String localeName;
  final String drawing;
  final String failed;
  final String showTable;
  final String showChart;
  final String showCode;
  final String showDiagram;
  final String fullScreen;
  final String shareImage;
  final String other;
  final String total;

  /// Precedes a chart's data source.
  final String sourcePrefix;
  final String chart;
  final String flowchart;
  final String sequence;
  final String mindmap;
  final String note;
  final String tip;
  final String important;
  final String warning;
  final String caution;

  List<String> get _values => [
    localeName,
    drawing,
    failed,
    showTable,
    showChart,
    showCode,
    showDiagram,
    fullScreen,
    shareImage,
    other,
    total,
    sourcePrefix,
    chart,
    flowchart,
    sequence,
    mindmap,
    note,
    tip,
    important,
    warning,
    caution,
  ];

  @override
  bool operator ==(Object other) =>
      other is VisualLabels && listEquals(other._values, _values);

  @override
  int get hashCode => Object.hashAll(_values);
}
