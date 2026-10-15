import 'package:flutter/material.dart';

import '../code_block.dart';
import 'chart_painter.dart';
import 'chart_scale.dart';
import 'chart_spec.dart';
import 'chart_view.dart';
import 'diagram_painter.dart';
import 'mermaid.dart';
import 'mindmap.dart';
import 'sequence.dart';
import 'visual_cache.dart';
import 'visual_image.dart';
import 'visual_labels.dart';
import 'visual_palette.dart';
import 'visual_text.dart';
import 'visual_viewer.dart';

/// Fenced languages drawn by [VisualBlock].
const visualLanguages = {'chart', 'mermaid'};

final _pendingFence = RegExp(
  r'^(?:[ \t]*>[ \t]?)*[ \t]*(?:(?:[-+*]|\d+[.)])[ \t]+)?(?:`{3,}|~{3,})[ \t]*([A-Za-z-]+)',
);

/// The visual language of a fence still streaming in, if any.
String? pendingVisualLanguage(String buffered) {
  final language = _pendingFence.firstMatch(buffered)?[1]?.toLowerCase();
  return language != null &&
          (visualLanguages.contains(language) || language == 'cards')
      ? language
      : null;
}

final class _Parse {
  const _Parse(this.value);

  /// A [ChartSpec] or a drawable [MermaidDiagram]; null when unreadable.
  final Object? value;
}

final _parses = LruCache<(String, String), _Parse>(64);

_Parse _parse(String language, String source) =>
    _parses.putIfAbsent((language, source), () {
      try {
        if (language == 'chart') return _Parse(ChartSpec.parse(source));
        return switch (parseMermaid(source)) {
          final MermaidChart chart => _Parse(chart.spec),
          final diagram => _Parse(diagram),
        };
      } on Object {
        return const _Parse(null);
      }
    });

/// A chart or Mermaid diagram in a titled frame. Anything that cannot be
/// drawn stays readable as its source code.
class VisualBlock extends StatefulWidget {
  const VisualBlock({
    required this.language,
    required this.source,
    required this.labels,
    required this.copyLabel,
    this.streaming = false,
    this.onCopy,
    this.onShareImage,
    super.key,
  });

  final String language;
  final String source;
  final VisualLabels labels;
  final String copyLabel;

  /// Charts that first appear while a reply streams grow in once.
  final bool streaming;
  final ValueChanged<String>? onCopy;
  final ValueChanged<VisualImage>? onShareImage;

  @override
  State<VisualBlock> createState() => _VisualBlockState();
}

class _VisualBlockState extends State<VisualBlock> {
  late _Parse _parsed = _parse(widget.language, widget.source);
  late final bool _animate = widget.streaming;
  bool _alternate = false;

  @override
  void didUpdateWidget(VisualBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language ||
        oldWidget.source != widget.source) {
      _parsed = _parse(widget.language, widget.source);
      _alternate = false;
    }
  }

  Widget _code({String? note, EdgeInsetsGeometry? margin}) => CodeBlock(
    code: widget.source,
    language: widget.language,
    copyLabel: widget.copyLabel,
    onCopy: widget.onCopy,
    note: note,
    margin: margin ?? const EdgeInsets.only(bottom: 8),
  );

  String _kind(MermaidDiagram diagram) => switch (diagram) {
    SequenceDiagram() => widget.labels.sequence,
    MindmapDiagram() => widget.labels.mindmap,
    _ => widget.labels.flowchart,
  };

  void _share({
    required String kind,
    required String title,
    required Size size,
    required void Function(Canvas canvas) paint,
  }) {
    final share = widget.onShareImage;
    if (share == null) return;
    final palette = VisualPalette.of(context);
    final text = VisualText.of(context);
    share(
      VisualImage(
        visualFileName(kind, DateTime.now()),
        () => renderVisualPng(
          size: size,
          paint: paint,
          background: palette.surface,
          text: text,
          titleColor: palette.ink,
          title: title,
        ),
      ),
    );
  }

  void _shareChart(ChartSpec spec, String title) {
    final palette = VisualPalette.of(context);
    final text = VisualText.of(context);
    final layout = chartLayout(spec, 520, text, widget.labels);
    _share(
      kind: 'chart',
      title: title,
      size: layout.size,
      paint: (canvas) => ChartPainter(
        layout: layout,
        spec: spec,
        palette: palette,
        text: text,
        format: ChartFormat(widget.labels.localeName, spec.unit),
        totalLabel: widget.labels.total,
      ).paint(canvas, layout.size),
    );
  }

  void _shareDiagram(DiagramDrawing drawing, String title) {
    final palette = VisualPalette.of(context);
    _share(
      kind: 'diagram',
      title: title,
      size: drawing.size,
      paint: (canvas) => drawing.paint(canvas, palette),
    );
  }

  Future<void> _open(DiagramDrawing drawing, String title) => showVisualViewer(
    context,
    title: title,
    size: drawing.size,
    painter: DiagramPainter(drawing, VisualPalette.of(context)),
    shareLabel: widget.labels.shareImage,
    onShare: widget.onShareImage == null
        ? null
        : () => _shareDiagram(drawing, title),
  );

  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    switch (_parsed.value) {
      case final ChartSpec spec:
        final title = spec.title ?? labels.chart;
        final drawable = spec.drawable;
        return _Frame(
          title: title,
          actions: [
            if (drawable)
              _Action(
                tooltip: _alternate ? labels.showChart : labels.showTable,
                icon: _alternate ? Icons.bar_chart : Icons.table_rows_outlined,
                onPressed: () => setState(() => _alternate = !_alternate),
              ),
            if (drawable && widget.onShareImage != null && !_alternate)
              _Action(
                tooltip: labels.shareImage,
                icon: Icons.ios_share,
                onPressed: () => _shareChart(spec, title),
              ),
          ],
          child: !drawable || _alternate
              ? ChartTable(spec: spec, labels: labels)
              : ChartView(
                  spec: spec,
                  labels: labels,
                  animate: _animate,
                  fallback: (_) =>
                      _code(note: labels.failed, margin: EdgeInsets.zero),
                ),
        );
      case final MermaidDiagram diagram:
        final title = diagram.title ?? _kind(diagram);
        // One layout serves the column, full screen and the shared image.
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite
                ? constraints.maxWidth - _Frame.insetFor(constraints.maxWidth)
                : null;
            final DiagramDrawing drawing;
            try {
              drawing = drawDiagram(
                diagram,
                VisualText.of(context),
                fitWidth: width,
              );
            } on Object {
              return _code(note: labels.failed);
            }
            return _Frame(
              title: title,
              actions: [
                _Action(
                  tooltip: _alternate ? labels.showDiagram : labels.showCode,
                  icon: _alternate ? Icons.account_tree_outlined : Icons.code,
                  onPressed: () => setState(() => _alternate = !_alternate),
                ),
                if (!_alternate)
                  _Action(
                    tooltip: labels.fullScreen,
                    icon: Icons.open_in_full,
                    onPressed: () => _open(drawing, title),
                  ),
                if (widget.onShareImage != null && !_alternate)
                  _Action(
                    tooltip: labels.shareImage,
                    icon: Icons.ios_share,
                    onPressed: () => _shareDiagram(drawing, title),
                  ),
              ],
              child: _alternate
                  ? _code(margin: EdgeInsets.zero)
                  : DiagramView(
                      drawing: drawing,
                      semanticLabel: '$title. ${diagramSummary(diagram)}',
                      onOpen: () => _open(drawing, title),
                    ),
            );
          },
        );
      default:
        return _code(note: labels.failed);
    }
  }
}

class _Action {
  const _Action({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
}

class _Frame extends StatelessWidget {
  const _Frame({
    required this.title,
    required this.actions,
    required this.child,
  });

  /// Horizontal space the border and padding take from a frame [width].
  /// Narrow columns get less padding, which leaves diagrams more room.
  static double insetFor(double width) => width < 320 ? 26 : 34;

  final String title;
  final List<_Action> actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = (insetFor(constraints.maxWidth) - 2) / 2;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(16),
          ),
          child: _content(theme, side),
        );
      },
    );
  }

  Widget _content(ThemeData theme, double side) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: EdgeInsets.fromLTRB(side, 6, 6, 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final action in actions)
              IconButton(
                tooltip: action.tooltip,
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                onPressed: action.onPressed,
                icon: Icon(action.icon),
              ),
          ],
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(side, 4, side, side),
        child: RepaintBoundary(child: child),
      ),
    ],
  );
}

/// Holds the place of a chart, diagram or cards block while it streams in.
/// Static on purpose: no endless animation in a list that settles.
class VisualPlaceholder extends StatelessWidget {
  const VisualPlaceholder({required this.label, super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      height: 96,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_graph, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
