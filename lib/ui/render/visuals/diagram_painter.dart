import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'flowchart.dart';
import 'mermaid.dart';
import 'mindmap.dart';
import 'sequence.dart';
import 'visual_cache.dart';
import 'visual_palette.dart';
import 'visual_text.dart';

/// A diagram laid out at one size, ready to paint on any canvas: on screen,
/// full screen, or into an image.
class DiagramDrawing {
  const DiagramDrawing(this.size, this._paint);
  final Size size;
  final void Function(Canvas canvas, VisualPalette palette) _paint;

  void paint(Canvas canvas, VisualPalette palette) => _paint(canvas, palette);
}

final _drawings = LruCache<(MermaidDiagram, double?, String), DiagramDrawing>(
  48,
);

/// Diagrams adapt to [fitWidth]: flowcharts may turn top-to-bottom, and
/// labels wrap narrower on small screens.
DiagramDrawing drawDiagram(
  MermaidDiagram diagram,
  VisualText text, {
  double? fitWidth,
}) => _drawings.putIfAbsent(
  (diagram, fitWidth, text.signature),
  () => switch (diagram) {
    FlowchartDiagram() => _flowchartDrawing(
      layoutFlowchart(diagram, text, fitWidth: fitWidth),
      text,
    ),
    SequenceDiagram() => _sequenceDrawing(
      layoutSequence(diagram, text, fitWidth: fitWidth),
      text,
    ),
    MindmapDiagram() => _mindmapDrawing(
      layoutMindmap(diagram, text, fitWidth: fitWidth),
      text,
    ),
    _ => throw ArgumentError.value(diagram, 'diagram', 'Not drawable'),
  },
);

DiagramDrawing _flowchartDrawing(FlowchartLayout layout, VisualText text) =>
    DiagramDrawing(
      layout.size,
      (canvas, palette) => _paintFlowchart(canvas, layout, palette, text),
    );

DiagramDrawing _sequenceDrawing(SequenceLayout layout, VisualText text) =>
    DiagramDrawing(
      layout.size,
      (canvas, palette) => _paintSequence(canvas, layout, palette, text),
    );

DiagramDrawing _mindmapDrawing(MindmapLayout layout, VisualText text) =>
    DiagramDrawing(
      layout.size,
      (canvas, palette) => _paintMindmap(canvas, layout, palette, text),
    );

class DiagramPainter extends CustomPainter {
  const DiagramPainter(this.drawing, this.palette);
  final DiagramDrawing drawing;
  final VisualPalette palette;

  @override
  void paint(Canvas canvas, Size size) => drawing.paint(canvas, palette);

  @override
  bool shouldRepaint(DiagramPainter oldDelegate) =>
      oldDelegate.drawing != drawing || oldDelegate.palette != palette;
}

/// A diagram that fits the column: drawn as is, shrunk a little, or
/// scrolled sideways when shrinking would make it unreadable. Tapping opens
/// it full screen.
class DiagramView extends StatelessWidget {
  const DiagramView({
    required this.drawing,
    required this.semanticLabel,
    this.onOpen,
    super.key,
  });

  final DiagramDrawing drawing;
  final String semanticLabel;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = VisualPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : drawing.size.width;
        final size = drawing.size;
        Widget child = CustomPaint(
          size: size,
          painter: DiagramPainter(drawing, palette),
        );
        final scale = width / size.width;
        if (scale >= 1) {
          child = Center(child: child);
        } else if (scale >= .8) {
          child = SizedBox(
            width: width,
            height: size.height * scale,
            child: FittedBox(alignment: Alignment.topLeft, child: child),
          );
        } else {
          child = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: child,
          );
        }
        return Semantics(
          label: semanticLabel,
          button: onOpen != null,
          child: GestureDetector(onTap: onOpen, child: child),
        );
      },
    );
  }
}

/// What a screen reader hears instead of the drawing.
String diagramSummary(MermaidDiagram diagram) => switch (diagram) {
  FlowchartDiagram(:final nodes, :final edges) => [
    for (final edge in edges.take(60))
      '${nodes[edge.from].label} → ${nodes[edge.to].label}'
          '${edge.label == null ? '' : ' (${edge.label})'}',
    for (final (i, node) in nodes.indexed)
      if (!edges.any((e) => e.from == i || e.to == i)) node.label,
  ].join('; '),
  SequenceDiagram(:final participants, :final events) => [
    for (final event in events.take(60))
      if (event is SequenceMessage)
        '${participants[event.from].label} → '
            '${participants[event.to].label}: ${event.text}',
  ].join('; '),
  MindmapDiagram(:final root) => _outline(root),
  _ => '',
};

String _outline(MindmapNode node) => node.children.isEmpty
    ? node.label
    : '${node.label} (${node.children.map(_outline).join(', ')})';

/// Draws [path] dashed when [dash] is set.
void _stroke(Canvas canvas, Path path, Paint paint, {double? dash}) {
  if (dash == null) {
    canvas.drawPath(path, paint);
    return;
  }
  for (final metric in path.computeMetrics()) {
    for (var d = 0.0; d < metric.length; d += dash * 2) {
      canvas.drawPath(
        metric.extractPath(d, math.min(d + dash, metric.length)),
        paint,
      );
    }
  }
}

/// A head at [tip], pointing along [direction].
void _head(
  Canvas canvas,
  Offset tip,
  Offset direction,
  ArrowHead head,
  Color color,
  Color surface,
) {
  final unit = direction / direction.distance;
  final normal = Offset(-unit.dy, unit.dx);
  switch (head) {
    case ArrowHead.arrow:
      final base = tip - unit * 9;
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(base.dx + normal.dx * 4.5, base.dy + normal.dy * 4.5)
          ..lineTo(base.dx - normal.dx * 4.5, base.dy - normal.dy * 4.5)
          ..close(),
        Paint()..color = color,
      );
    case ArrowHead.circle:
      final center = tip - unit * 4;
      canvas
        ..drawCircle(center, 4, Paint()..color = surface)
        ..drawCircle(
          center,
          4,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
    case ArrowHead.cross:
      final center = tip - unit * 5;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      for (final sign in const [1.0, -1.0]) {
        final a = (unit + normal * sign) * 3.5;
        canvas.drawLine(center - a, center + a, paint);
      }
    case ArrowHead.none:
  }
}

double _inset(ArrowHead head) => switch (head) {
  ArrowHead.arrow => 8,
  ArrowHead.circle => 8,
  ArrowHead.cross => 0,
  ArrowHead.none => 0,
};

void _paintFlowchart(
  Canvas canvas,
  FlowchartLayout layout,
  VisualPalette palette,
  VisualText text,
) {
  for (final cluster in layout.clusters) {
    final rect = RRect.fromRectAndRadius(
      cluster.rect,
      const Radius.circular(12),
    );
    canvas
      ..drawRRect(rect, Paint()..color = palette.clusterFill)
      ..drawRRect(
        rect,
        Paint()
          ..color = palette.nodeStroke
          ..style = PaintingStyle.stroke,
      );
    text.paint(
      canvas,
      cluster.title,
      VisualTextRole.captionStrong,
      cluster.rect.topLeft + const Offset(10, 6),
      color: palette.mutedInk,
      maxWidth: math.max(cluster.rect.width - 20, 20),
      maxLines: 1,
    );
  }

  for (final edge in layout.edges) {
    final points = [...edge.points];
    final last = points.length - 1;
    // Lines stop at the base of their heads.
    Offset along(Offset from, Offset to) {
      if (edge.loop) return to - from;
      return edge.vertical
          ? Offset(0, (to.dy - from.dy).sign)
          : Offset((to.dx - from.dx).sign, 0);
    }

    final endDirection = along(points[last - 1], points[last]);
    final startDirection = along(points[1], points[0]);
    final endTip = points[last];
    final startTip = points[0];
    if (endDirection != Offset.zero) {
      points[last] -= endDirection / endDirection.distance * _inset(edge.end);
    }
    if (startDirection != Offset.zero) {
      points[0] -=
          startDirection / startDirection.distance * _inset(edge.start);
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    if (edge.loop) {
      path.cubicTo(
        points[1].dx,
        points[1].dy,
        points[2].dx,
        points[2].dy,
        points[3].dx,
        points[3].dy,
      );
    } else {
      for (var i = 0; i + 1 < points.length; i++) {
        final a = points[i];
        final b = points[i + 1];
        if (edge.vertical) {
          final middle = (b.dy - a.dy) / 2;
          path.cubicTo(a.dx, a.dy + middle, b.dx, b.dy - middle, b.dx, b.dy);
        } else {
          final middle = (b.dx - a.dx) / 2;
          path.cubicTo(a.dx + middle, a.dy, b.dx - middle, b.dy, b.dx, b.dy);
        }
      }
    }
    final paint = Paint()
      ..color = palette.edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = edge.style == LineStyle.thick ? 3 : 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    _stroke(
      canvas,
      path,
      paint,
      dash: edge.style == LineStyle.dotted ? 4 : null,
    );
    if (endDirection != Offset.zero) {
      _head(
        canvas,
        endTip,
        endDirection,
        edge.end,
        palette.edge,
        palette.surface,
      );
    }
    if (startDirection != Offset.zero) {
      _head(
        canvas,
        startTip,
        startDirection,
        edge.start,
        palette.edge,
        palette.surface,
      );
    }
  }

  for (final edge in layout.edges) {
    final label = edge.label;
    final center = edge.labelCenter;
    if (label == null || center == null) continue;
    final size = text.measure(
      label,
      VisualTextRole.caption,
      maxWidth: edgeLabelWidth * layout.wrap,
      maxLines: 3,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center,
          width: size.width + 10,
          height: size.height + 4,
        ),
        const Radius.circular(6),
      ),
      Paint()..color = palette.surface,
    );
    text.paintCentered(
      canvas,
      label,
      VisualTextRole.caption,
      center,
      color: palette.ink,
      maxWidth: edgeLabelWidth * layout.wrap,
      maxLines: 3,
    );
  }

  for (final node in layout.nodes) {
    final (fill, ink) = switch (node.shape) {
      NodeShape.rhombus => (palette.decisionFill, palette.onDecision),
      NodeShape.stadium ||
      NodeShape.circle ||
      NodeShape.doubleCircle => (palette.terminalFill, palette.onTerminal),
      _ => (palette.nodeFill, palette.ink),
    };
    final rect = node.rect;
    final path = _nodePath(node.shape, rect);
    final stroke = Paint()
      ..color = palette.nodeStroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(path, Paint()..color = fill)
      ..drawPath(path, stroke);
    switch (node.shape) {
      case NodeShape.subroutine:
        canvas
          ..drawLine(
            Offset(rect.left + 8, rect.top),
            Offset(rect.left + 8, rect.bottom),
            stroke,
          )
          ..drawLine(
            Offset(rect.right - 8, rect.top),
            Offset(rect.right - 8, rect.bottom),
            stroke,
          );
      case NodeShape.doubleCircle:
        canvas.drawOval(rect.deflate(4), stroke);
      case NodeShape.cylinder:
        canvas.drawArc(
          Rect.fromLTWH(rect.left, rect.top, rect.width, 14),
          0,
          math.pi,
          false,
          stroke,
        );
      default:
    }
    text.paintCentered(
      canvas,
      node.label,
      VisualTextRole.body,
      rect.center + Offset(0, node.shape == NodeShape.cylinder ? 4 : 0),
      color: ink,
      maxWidth: nodeLabelWidth(node.shape) * layout.wrap,
    );
  }
}

Path _nodePath(NodeShape shape, Rect rect) {
  final l = rect.left;
  final t = rect.top;
  final r = rect.right;
  final b = rect.bottom;
  final h = rect.height;
  final cy = rect.center.dy;
  Path polygon(List<Offset> points) => Path()..addPolygon(points, true);
  return switch (shape) {
    NodeShape.round =>
      Path()..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(math.min(12, h / 2))),
      ),
    NodeShape.stadium =>
      Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(h / 2))),
    NodeShape.circle || NodeShape.doubleCircle => Path()..addOval(rect),
    NodeShape.rhombus => polygon([
      Offset(rect.center.dx, t),
      Offset(r, cy),
      Offset(rect.center.dx, b),
      Offset(l, cy),
    ]),
    NodeShape.hexagon => polygon([
      Offset(l + h / 4, t),
      Offset(r - h / 4, t),
      Offset(r, cy),
      Offset(r - h / 4, b),
      Offset(l + h / 4, b),
      Offset(l, cy),
    ]),
    NodeShape.asymmetric => polygon([
      Offset(l, t),
      Offset(r, t),
      Offset(r, b),
      Offset(l, b),
      Offset(l + 12, cy),
    ]),
    NodeShape.parallelogram => polygon([
      Offset(l + h / 2, t),
      Offset(r, t),
      Offset(r - h / 2, b),
      Offset(l, b),
    ]),
    NodeShape.parallelogramAlt => polygon([
      Offset(l, t),
      Offset(r - h / 2, t),
      Offset(r, b),
      Offset(l + h / 2, b),
    ]),
    NodeShape.trapezoid => polygon([
      Offset(l + h / 2, t),
      Offset(r - h / 2, t),
      Offset(r, b),
      Offset(l, b),
    ]),
    NodeShape.trapezoidAlt => polygon([
      Offset(l, t),
      Offset(r, t),
      Offset(r - h / 2, b),
      Offset(l + h / 2, b),
    ]),
    NodeShape.cylinder =>
      Path()
        ..moveTo(l, t + 7)
        ..arcTo(Rect.fromLTWH(l, t, rect.width, 14), math.pi, math.pi, false)
        ..lineTo(r, b - 7)
        ..arcTo(Rect.fromLTWH(l, b - 14, rect.width, 14), 0, math.pi, false)
        ..close(),
    _ =>
      Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4))),
  };
}

void _paintSequence(
  Canvas canvas,
  SequenceLayout layout,
  VisualPalette palette,
  VisualText text,
) {
  final hairline = Paint()
    ..color = palette.nodeStroke
    ..style = PaintingStyle.stroke;
  for (final frame in layout.frames) {
    final rect = RRect.fromRectAndRadius(frame.rect, const Radius.circular(8));
    if (frame.kind == 'rect') {
      canvas.drawRRect(rect, Paint()..color = palette.clusterFill);
      continue;
    }
    canvas.drawRRect(rect, hairline);
    final tag = text.measure(frame.kind, VisualTextRole.captionStrong);
    final tagRect = Rect.fromLTWH(
      frame.rect.left,
      frame.rect.top,
      tag.width + 16,
      tag.height + 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        tagRect,
        topLeft: const Radius.circular(8),
        bottomRight: const Radius.circular(8),
      ),
      Paint()..color = palette.nodeFill,
    );
    text.paint(
      canvas,
      frame.kind,
      VisualTextRole.captionStrong,
      tagRect.topLeft + const Offset(8, 3),
      color: palette.ink,
    );
    if (frame.label.isNotEmpty) {
      text.paint(
        canvas,
        '[${frame.label}]',
        VisualTextRole.caption,
        Offset(tagRect.right + 8, tagRect.top + 3),
        color: palette.mutedInk,
        maxWidth: math.max(frame.rect.right - tagRect.right - 16, 24),
        maxLines: 1,
      );
    }
    for (final (y, label) in frame.dividers) {
      _stroke(
        canvas,
        Path()
          ..moveTo(frame.rect.left, y)
          ..lineTo(frame.rect.right, y),
        hairline,
        dash: 4,
      );
      if (label.isNotEmpty) {
        text.paint(
          canvas,
          '[$label]',
          VisualTextRole.caption,
          Offset(frame.rect.left + 10, y + 3),
          color: palette.mutedInk,
          maxWidth: math.max(frame.rect.width - 20, 24),
          maxLines: 1,
        );
      }
    }
  }

  final lifeline = Paint()
    ..color = palette.baseline
    ..strokeWidth = 1;
  for (final participant in layout.participants) {
    final x = participant.rect.center.dx;
    canvas.drawLine(
      Offset(x, layout.lifelineTop),
      Offset(x, layout.lifelineBottom),
      lifeline,
    );
  }
  for (final participant in layout.participants) {
    final rect = RRect.fromRectAndRadius(
      participant.rect,
      const Radius.circular(8),
    );
    canvas
      ..drawRRect(rect, Paint()..color = palette.nodeFill)
      ..drawRRect(rect, hairline);
    text.paintCentered(
      canvas,
      participant.label,
      VisualTextRole.bodyStrong,
      participant.rect.center,
      color: palette.ink,
      maxWidth: layout.participantWidth,
    );
    if (participant.actor) {
      final x = participant.rect.center.dx;
      final top = participant.rect.top;
      final figure = Paint()
        ..color = palette.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      canvas
        ..drawCircle(Offset(x, top - 20), 4.5, figure)
        ..drawLine(Offset(x, top - 15.5), Offset(x, top - 8), figure)
        ..drawLine(Offset(x - 7, top - 12.5), Offset(x + 7, top - 12.5), figure)
        ..drawLine(Offset(x, top - 8), Offset(x - 6, top - 2), figure)
        ..drawLine(Offset(x, top - 8), Offset(x + 6, top - 2), figure);
    }
  }

  for (final note in layout.notes) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(note.rect, const Radius.circular(6)),
      Paint()..color = palette.noteFill,
    );
    text.paint(
      canvas,
      note.text,
      VisualTextRole.caption,
      note.rect.topLeft + const Offset(10, 6),
      color: palette.onNote,
      maxWidth: layout.noteWidth,
    );
  }

  for (final message in layout.messages) {
    final paint = Paint()
      ..color = palette.edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final head = switch (message.head) {
      MessageHead.arrow => ArrowHead.arrow,
      MessageHead.cross => ArrowHead.cross,
      _ => ArrowHead.none,
    };
    final y = message.y;
    if (message.self) {
      final x = message.from;
      final path = Path()
        ..moveTo(x, y)
        ..lineTo(x + 24, y)
        ..arcToPoint(Offset(x + 30, y + 6), radius: const Radius.circular(6))
        ..lineTo(x + 30, y + 16)
        ..arcToPoint(Offset(x + 24, y + 22), radius: const Radius.circular(6))
        ..lineTo(x + _inset(head), y + 22);
      _stroke(canvas, path, paint, dash: message.dashed ? 4 : null);
      _messageHead(
        canvas,
        Offset(x, y + 22),
        const Offset(-1, 0),
        message,
        palette,
      );
    } else {
      final direction = Offset((message.to - message.from).sign, 0);
      final start = Offset(
        message.from + (message.both ? direction.dx * _inset(head) : 0),
        y,
      );
      final end = Offset(message.to - direction.dx * _inset(head), y);
      _stroke(
        canvas,
        Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(end.dx, end.dy),
        paint,
        dash: message.dashed ? 4 : null,
      );
      _messageHead(canvas, Offset(message.to, y), direction, message, palette);
      if (message.both) {
        _messageHead(
          canvas,
          Offset(message.from, y),
          -direction,
          message,
          palette,
        );
      }
    }
    if (message.text.isNotEmpty) {
      text.paint(
        canvas,
        message.text,
        VisualTextRole.caption,
        message.textTopLeft,
        color: palette.ink,
        maxWidth: layout.messageWidth,
        align: message.self ? TextAlign.left : TextAlign.center,
      );
    }
    if (message.number case final number?) {
      final center = Offset(message.from, y);
      canvas.drawCircle(center, 8.5, Paint()..color = palette.ink);
      text.paintCentered(
        canvas,
        '$number',
        VisualTextRole.tiny,
        center,
        color: palette.surface,
      );
    }
  }
}

void _messageHead(
  Canvas canvas,
  Offset tip,
  Offset direction,
  PlacedMessage message,
  VisualPalette palette,
) {
  switch (message.head) {
    case MessageHead.arrow:
      _head(
        canvas,
        tip,
        direction,
        ArrowHead.arrow,
        palette.edge,
        palette.surface,
      );
    case MessageHead.cross:
      _head(
        canvas,
        tip,
        direction,
        ArrowHead.cross,
        palette.edge,
        palette.surface,
      );
    case MessageHead.open:
      // An asynchronous message: an open chevron.
      final back = tip - direction * 8;
      final normal = Offset(-direction.dy, direction.dx) * 5;
      final paint = Paint()
        ..color = palette.edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      canvas
        ..drawLine(tip, back + normal, paint)
        ..drawLine(tip, back - normal, paint);
    case MessageHead.none:
  }
}

void _paintMindmap(
  Canvas canvas,
  MindmapLayout layout,
  VisualPalette palette,
  VisualText text,
) {
  for (final link in layout.links) {
    final dx = (link.to.dx - link.from.dx) / 2;
    canvas.drawPath(
      Path()
        ..moveTo(link.from.dx, link.from.dy)
        ..cubicTo(
          link.from.dx + dx,
          link.from.dy,
          link.to.dx - dx,
          link.to.dy,
          link.to.dx,
          link.to.dy,
        ),
      Paint()
        ..color = palette.seriesColor(link.branch)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = switch (link.depth) {
          1 => 3,
          2 => 2,
          _ => 1.5,
        },
    );
  }
  for (final node in layout.nodes) {
    final padding = mindPadding(node.depth);
    final rect = node.rect;
    final color = palette.seriesColor(node.branch);
    switch (node.depth) {
      case 0:
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
          Paint()..color = palette.terminalFill,
        );
      case 1:
        final rounded = RRect.fromRectAndRadius(
          rect,
          const Radius.circular(10),
        );
        canvas
          ..drawRRect(rounded, Paint()..color = palette.surface)
          ..drawRRect(
            rounded,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
      default:
        canvas.drawLine(
          rect.bottomLeft,
          rect.bottomRight,
          Paint()
            ..color = color
            ..strokeWidth = node.depth == 2 ? 2 : 1.5
            ..strokeCap = StrokeCap.round,
        );
    }
    final inner = padding.deflateRect(rect);
    text.paint(
      canvas,
      node.label,
      mindTextRole(node.depth),
      inner.topLeft,
      color: node.depth == 0 ? palette.onTerminal : palette.ink,
      maxWidth: node.depth == 0 ? layout.rootWidth : layout.labelWidth,
      align: node.depth <= 1 ? TextAlign.center : TextAlign.left,
    );
  }
}
