import 'dart:math' as math;
import 'dart:ui';

import 'layered_layout.dart';
import 'mermaid.dart';
import 'visual_text.dart';

enum NodeShape {
  rect,
  round,
  stadium,
  subroutine,
  cylinder,
  circle,
  doubleCircle,
  asymmetric,
  rhombus,
  hexagon,
  parallelogram,
  parallelogramAlt,
  trapezoid,
  trapezoidAlt,
}

enum LineStyle { solid, dotted, thick, invisible }

enum ArrowHead { none, arrow, circle, cross }

class FlowNode {
  const FlowNode(this.id, this.label, this.shape, this.cluster);
  final String id;
  final String label;
  final NodeShape shape;
  final int? cluster;
}

class FlowEdge {
  const FlowEdge(
    this.from,
    this.to, {
    this.label,
    this.style = LineStyle.solid,
    this.start = ArrowHead.none,
    this.end = ArrowHead.arrow,
    this.length = 1,
  });

  final int from;
  final int to;
  final String? label;
  final LineStyle style;
  final ArrowHead start;
  final ArrowHead end;
  final int length;
}

class FlowCluster {
  const FlowCluster(this.id, this.title, this.parent);
  final String id;
  final String title;
  final int? parent;
}

final class FlowchartDiagram extends MermaidDiagram {
  const FlowchartDiagram({
    required this.direction,
    required this.nodes,
    required this.edges,
    required this.clusters,
    String? title,
  }) : super(title);

  final LayeredDirection direction;
  final List<FlowNode> nodes;
  final List<FlowEdge> edges;
  final List<FlowCluster> clusters;
}

const maxFlowNodes = 120;
const maxFlowEdges = 300;

/// Flowcharts (`flowchart` and `graph`): shapes, links, labels, chains, `&`
/// and subgraphs. Styling and `click` are ignored; Tako's theme colours
/// every chart.
FlowchartDiagram parseFlowchart(
  String header,
  List<String> lines,
  String? title,
) {
  final parts = _statements(header);
  final direction = switch (RegExp(
    r'^\s*\S+\s+(TB|TD|BT|RL|LR)\b',
    caseSensitive: false,
  ).firstMatch(parts.first)?[1]?.toUpperCase()) {
    'BT' => LayeredDirection.up,
    'LR' => LayeredDirection.right,
    'RL' => LayeredDirection.left,
    _ => LayeredDirection.down,
  };
  final parser = _FlowParser();
  for (final statement in parts.skip(1)) {
    parser.statement(statement);
  }
  for (final line in lines) {
    _statements(line).forEach(parser.statement);
  }
  return parser.finish(direction, title);
}

/// Splits on `;` outside quotes, brackets and edge labels.
List<String> _statements(String line) {
  final parts = <String>[];
  var depth = 0;
  var quoted = false;
  var piped = false;
  var start = 0;
  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      quoted = !quoted;
    } else if (!quoted) {
      if ('[({'.contains(char)) {
        depth++;
      } else if (')]}'.contains(char)) {
        depth = math.max(0, depth - 1);
      } else if (char == '|' && depth == 0) {
        piped = !piped;
      } else if (char == ';' && depth == 0 && !piped) {
        parts.add(line.substring(start, i));
        start = i + 1;
      }
    }
  }
  parts.add(line.substring(start));
  return parts;
}

class _NodeDraft {
  _NodeDraft(this.id) : label = id;
  final String id;
  String label;
  NodeShape shape = NodeShape.rect;
  bool explicit = false;
  int? cluster;
}

class _EdgeDraft {
  _EdgeDraft(this.from, this.to, this.link);
  final int from;
  final int to;
  final _Link link;
}

class _Link {
  const _Link(this.style, this.start, this.end, this.length, this.label);
  final LineStyle style;
  final ArrowHead start;
  final ArrowHead end;
  final int length;
  final String? label;
}

const _shapes = <(String, List<(String, NodeShape)>)>[
  ('(((', [(')))', NodeShape.doubleCircle)]),
  ('((', [('))', NodeShape.circle)]),
  ('([', [('])', NodeShape.stadium)]),
  ('(', [(')', NodeShape.round)]),
  ('[[', [(']]', NodeShape.subroutine)]),
  ('[(', [(')]', NodeShape.cylinder)]),
  ('[/', [('/]', NodeShape.parallelogram), (r'\]', NodeShape.trapezoid)]),
  (
    r'[\',
    [(r'\]', NodeShape.parallelogramAlt), ('/]', NodeShape.trapezoidAlt)],
  ),
  ('[', [(']', NodeShape.rect)]),
  ('{{', [('}}', NodeShape.hexagon)]),
  ('{', [('}', NodeShape.rhombus)]),
  ('>', [(']', NodeShape.asymmetric)]),
];

/// Mermaid 11 `A@{ shape: … }` names.
const _namedShapes = <String, NodeShape>{
  'rect': NodeShape.rect,
  'rectangle': NodeShape.rect,
  'proc': NodeShape.rect,
  'process': NodeShape.rect,
  'rounded': NodeShape.round,
  'event': NodeShape.round,
  'stadium': NodeShape.stadium,
  'pill': NodeShape.stadium,
  'terminal': NodeShape.stadium,
  'subproc': NodeShape.subroutine,
  'subroutine': NodeShape.subroutine,
  'cyl': NodeShape.cylinder,
  'cylinder': NodeShape.cylinder,
  'database': NodeShape.cylinder,
  'db': NodeShape.cylinder,
  'circle': NodeShape.circle,
  'circ': NodeShape.circle,
  'start': NodeShape.circle,
  'dbl-circ': NodeShape.doubleCircle,
  'double-circle': NodeShape.doubleCircle,
  'stop': NodeShape.doubleCircle,
  'diam': NodeShape.rhombus,
  'diamond': NodeShape.rhombus,
  'decision': NodeShape.rhombus,
  'question': NodeShape.rhombus,
  'hex': NodeShape.hexagon,
  'hexagon': NodeShape.hexagon,
  'prepare': NodeShape.hexagon,
  'lean-r': NodeShape.parallelogram,
  'in-out': NodeShape.parallelogram,
  'lean-l': NodeShape.parallelogramAlt,
  'out-in': NodeShape.parallelogramAlt,
  'trap-b': NodeShape.trapezoid,
  'priority': NodeShape.trapezoid,
  'trap-t': NodeShape.trapezoidAlt,
  'manual': NodeShape.trapezoidAlt,
};

class _FlowParser {
  final _nodes = <_NodeDraft>[];
  final _ids = <String, int>{};
  final _edges = <_EdgeDraft>[];
  final _clusters = <(String, String, int?)>[];
  final _open = <int>[];

  void statement(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return;
    final word = RegExp(r'^[A-Za-z]+').firstMatch(text)?[0]?.toLowerCase();
    if (word == 'subgraph') {
      _openCluster(text.substring(8).trim());
      return;
    }
    if (word == 'end' && text.length == 3) {
      if (_open.isNotEmpty) _open.removeLast();
      return;
    }
    if (const {
      'direction',
      'classdef',
      'class',
      'style',
      'linkstyle',
      'click',
      'acctitle',
      'accdescr',
    }.contains(word)) {
      return;
    }
    final cursor = _Cursor(text);
    var group = _group(cursor);
    if (group.isEmpty) return;
    while (true) {
      final link = _link(cursor);
      if (link == null) break;
      final next = _group(cursor);
      if (next.isEmpty) break;
      for (final from in group) {
        for (final to in next) {
          _edges.add(_EdgeDraft(from, to, link));
        }
      }
      group = next;
    }
  }

  void _openCluster(String rest) {
    final bracket = RegExp(r'^([^\s\[]+)\s*\[(.*)\]\s*$').firstMatch(rest);
    final String id;
    final String title;
    if (bracket != null) {
      id = bracket[1]!;
      title = cleanMermaidText(bracket[2]!);
    } else if (rest.isEmpty || rest.startsWith('"')) {
      id = '\u0000cluster${_clusters.length}';
      title = cleanMermaidText(rest);
    } else {
      id = rest;
      title = cleanMermaidText(rest);
    }
    _clusters.add((id, title, _open.lastOrNull));
    _open.add(_clusters.length - 1);
  }

  List<int> _group(_Cursor cursor) {
    final nodes = <int>[];
    while (true) {
      final node = _node(cursor);
      if (node == null) break;
      nodes.add(node);
      cursor.skipSpaces();
      if (!cursor.startsWith('&')) break;
      cursor.index++;
    }
    return nodes;
  }

  int? _node(_Cursor cursor) {
    cursor.skipSpaces();
    final start = cursor.index;
    while (!cursor.done && !_endsId(cursor)) {
      cursor.index++;
    }
    final id = cursor.text.substring(start, cursor.index).trim();
    if (id.isEmpty) return null;
    final shape = _shape(cursor);
    if (cursor.startsWith(':::')) {
      cursor.index += 3;
      while (!cursor.done && RegExp(r'[\w-]').hasMatch(cursor.peek)) {
        cursor.index++;
      }
    }
    var index = _ids[id];
    if (index == null) {
      index = _nodes.length;
      _ids[id] = index;
      _nodes.add(_NodeDraft(id));
    }
    final node = _nodes[index];
    if (shape != null) {
      node
        ..shape = shape.$1
        ..label = shape.$2
        ..explicit = true;
    }
    if (_open.isNotEmpty) node.cluster ??= _open.last;
    return index;
  }

  bool _endsId(_Cursor cursor) {
    final char = cursor.peek;
    if (' \t&|"[({>'.contains(char)) return true;
    return const [
      ':::',
      '@{',
      '--',
      '==',
      '-.',
      '~~~',
      '<-',
      '<=',
    ].any(cursor.startsWith);
  }

  (NodeShape, String)? _shape(_Cursor cursor) {
    if (cursor.startsWith('@{')) {
      final end = cursor.text.indexOf('}', cursor.index);
      final body = cursor.text.substring(
        cursor.index + 2,
        end < 0 ? cursor.text.length : end,
      );
      cursor.index = end < 0 ? cursor.text.length : end + 1;
      final name = RegExp(r'shape\s*:\s*([\w-]+)').firstMatch(body)?[1];
      final label = RegExp(
        r'''label\s*:\s*(?:"([^"]*)"|'([^']*)'|([^,]+))''',
      ).firstMatch(body);
      final text = label?[1] ?? label?[2] ?? label?[3];
      if (name == null && text == null) return null;
      return (
        _namedShapes[name?.toLowerCase()] ?? NodeShape.rect,
        cleanMermaidText(text ?? ''),
      );
    }
    for (final (opener, closers) in _shapes) {
      if (!cursor.startsWith(opener)) continue;
      cursor.index += opener.length;
      final text = cursor.text;
      var from = cursor.index;
      var label = '';
      if (cursor.startsWith('"')) {
        final quote = text.indexOf('"', from + 1);
        if (quote >= 0) {
          label = text.substring(from + 1, quote);
          from = quote + 1;
        }
      }
      (int, String, NodeShape)? best;
      for (final (closer, shape) in closers) {
        final at = text.indexOf(closer, from);
        if (at >= 0 && (best == null || at < best.$1)) {
          best = (at, closer, shape);
        }
      }
      if (best == null) {
        cursor.index = text.length;
        return (
          closers.first.$2,
          cleanMermaidText(label + text.substring(from)),
        );
      }
      if (label.isEmpty) label = text.substring(from, best.$1);
      cursor.index = best.$1 + best.$2.length;
      return (best.$3, cleanMermaidText(label));
    }
    return null;
  }

  _Link? _link(_Cursor cursor) {
    cursor.skipSpaces();
    final start = cursor.index;
    var head = ArrowHead.none;
    if (cursor.startsWith('<')) {
      head = ArrowHead.arrow;
      cursor.index++;
    } else if ((cursor.startsWith('o') || cursor.startsWith('x')) &&
        const [
          '--',
          '==',
          '-.',
        ].any((body) => cursor.text.startsWith(body, cursor.index + 1))) {
      head = cursor.peek == 'o' ? ArrowHead.circle : ArrowHead.cross;
      cursor.index++;
    }
    final LineStyle style;
    var run = 0;
    // Only a bare opener (`--`, `==`, `-.`) can be followed by inline text.
    var opener = false;
    if (cursor.startsWith('~~~')) {
      style = LineStyle.invisible;
      while (cursor.startsWith('~')) {
        cursor.index++;
        run++;
      }
    } else if (cursor.startsWith('==')) {
      style = LineStyle.thick;
      while (cursor.startsWith('=')) {
        cursor.index++;
        run++;
      }
      opener = run == 2;
    } else if (cursor.startsWith('-.')) {
      style = LineStyle.dotted;
      cursor.index++;
      while (cursor.startsWith('.')) {
        cursor.index++;
        run++;
      }
      opener = !cursor.startsWith('-');
      if (!opener) cursor.index++;
    } else if (cursor.startsWith('--')) {
      style = LineStyle.solid;
      while (cursor.startsWith('-')) {
        cursor.index++;
        run++;
      }
      opener = run == 2;
    } else {
      cursor.index = start;
      return null;
    }
    var end = _head(cursor);
    String? label;
    // `A -- text --> B`, `A == text ==> B`, `A -. text .-> B`.
    if (opener &&
        end == ArrowHead.none &&
        !cursor.done &&
        (cursor.peek == ' ' || cursor.peek == '\t')) {
      final closer = switch (style) {
        LineStyle.thick => RegExp(r'(={2,})([>ox]?)'),
        LineStyle.dotted => RegExp(r'(\.+)-([>ox]?)'),
        _ => RegExp(r'(-{2,})([>ox]?)'),
      };
      final match = closer.allMatches(cursor.text, cursor.index).firstOrNull;
      if (match != null) {
        label = cleanMermaidText(
          cursor.text.substring(cursor.index, match.start),
        );
        cursor.index = match.end;
        end = switch (match[2]) {
          '>' => ArrowHead.arrow,
          'o' => ArrowHead.circle,
          'x' => ArrowHead.cross,
          _ => ArrowHead.none,
        };
        run = match[1]!.length;
      }
    }
    cursor.skipSpaces();
    if (cursor.startsWith('|')) {
      final close = cursor.text.indexOf('|', cursor.index + 1);
      if (close > 0) {
        label = cleanMermaidText(
          cursor.text.substring(cursor.index + 1, close),
        );
        cursor.index = close + 1;
      }
    }
    final length = switch (style) {
      LineStyle.dotted => run,
      _ => run - (end == ArrowHead.none ? 2 : 1),
    };
    return _Link(
      style,
      head,
      end,
      math.max(1, length),
      label == null || label.isEmpty ? null : label,
    );
  }

  ArrowHead _head(_Cursor cursor) {
    if (cursor.done) return ArrowHead.none;
    final char = cursor.peek;
    final next = cursor.index + 1;
    final separated =
        next >= cursor.text.length ||
        cursor.text[next] == ' ' ||
        cursor.text[next] == '\t' ||
        cursor.text[next] == '|';
    if (char == '>') {
      cursor.index++;
      return ArrowHead.arrow;
    }
    if ((char == 'o' || char == 'x') && separated) {
      cursor.index++;
      return char == 'o' ? ArrowHead.circle : ArrowHead.cross;
    }
    return ArrowHead.none;
  }

  FlowchartDiagram finish(LayeredDirection direction, String? title) {
    // An id used in a link before its `subgraph` is the subgraph itself:
    // link to its first node instead.
    final clusterIds = {
      for (final (index, cluster) in _clusters.indexed) cluster.$1: index,
    };
    int? firstMember(int cluster) {
      for (final (index, node) in _nodes.indexed) {
        for (int? c = node.cluster; c != null; c = _clusters[c].$3) {
          if (c == cluster && !clusterIds.containsKey(node.id)) return index;
        }
      }
      return null;
    }

    final keep = <int, int>{};
    final redirect = <int, int?>{};
    for (final (index, node) in _nodes.indexed) {
      if (!node.explicit && clusterIds.containsKey(node.id)) {
        redirect[index] = firstMember(clusterIds[node.id]!);
      } else {
        keep[index] = keep.length;
      }
    }
    int? resolve(int index) =>
        keep[index] ?? (redirect[index] == null ? null : keep[redirect[index]]);
    final edges = <FlowEdge>[];
    for (final edge in _edges) {
      final from = resolve(edge.from);
      final to = resolve(edge.to);
      if (from == null || to == null) continue;
      edges.add(
        FlowEdge(
          from,
          to,
          label: edge.link.label,
          style: edge.link.style,
          start: edge.link.start,
          end: edge.link.end,
          length: edge.link.length,
        ),
      );
    }
    final nodes = [
      for (final (index, node) in _nodes.indexed)
        if (keep.containsKey(index))
          FlowNode(node.id, node.label, node.shape, node.cluster),
    ];
    if (nodes.isEmpty) throw const FormatException('A flowchart needs nodes');
    if (nodes.length > maxFlowNodes || edges.length > maxFlowEdges) {
      throw const FormatException('Flowchart is too large');
    }
    return FlowchartDiagram(
      direction: direction,
      nodes: List.unmodifiable(nodes),
      edges: List.unmodifiable(edges),
      clusters: [
        for (final (id, title, parent) in _clusters)
          FlowCluster(id, title, parent),
      ],
      title: title,
    );
  }
}

class _Cursor {
  _Cursor(this.text);
  final String text;
  int index = 0;

  bool get done => index >= text.length;
  String get peek => text[index];
  bool startsWith(String value) => text.startsWith(value, index);

  void skipSpaces() {
    while (!done && (text[index] == ' ' || text[index] == '\t')) {
      index++;
    }
  }
}

// Layout

enum PortSide { top, bottom, left, right }

class PlacedNode {
  const PlacedNode(this.rect, this.shape, this.label);
  final Rect rect;
  final NodeShape shape;
  final String label;
}

class PlacedEdge {
  const PlacedEdge(
    this.points, {
    required this.vertical,
    required this.style,
    required this.start,
    required this.end,
    this.label,
    this.labelCenter,
    this.loop = false,
  });

  /// From the source port through every bend point to the target port. A
  /// self-loop is one cubic: start, two control points, end.
  final List<Offset> points;

  /// Segments leave and enter along y when true, along x otherwise.
  final bool vertical;
  final LineStyle style;
  final ArrowHead start;
  final ArrowHead end;
  final String? label;
  final Offset? labelCenter;
  final bool loop;
}

class PlacedCluster {
  const PlacedCluster(this.rect, this.title);
  final Rect rect;
  final String title;
}

class FlowchartLayout {
  const FlowchartLayout(
    this.size,
    this.nodes,
    this.edges,
    this.clusters, {
    this.wrap = 1,
  });

  final Size size;
  final List<PlacedNode> nodes;
  final List<PlacedEdge> edges;
  final List<PlacedCluster> clusters;

  /// Labels wrap at this fraction of [nodeLabelWidth] and [edgeLabelWidth].
  final double wrap;
}

const edgeLabelWidth = 120.0;

double nodeLabelWidth(NodeShape shape) => switch (shape) {
  NodeShape.rhombus => 112,
  NodeShape.circle || NodeShape.doubleCircle => 96,
  _ => 150,
};

Size _nodeSize(NodeShape shape, Size label) {
  const padX = 14.0;
  const padY = 9.0;
  final height = label.height + 2 * padY;
  final diameter = math.max(
    math.sqrt(label.width * label.width + label.height * label.height) +
        (shape == NodeShape.doubleCircle ? 24 : 16),
    44.0,
  );
  // A rhombus contains the label when (w/2)/a + (h/2)/b <= 1 for its half
  // diagonals a and b. Choosing a = w/2 + h + 12 keeps it from growing tall.
  final halfWidth = label.width / 2 + label.height + 12;
  final halfHeight = (label.height / 2) / (1 - (label.width / 2) / halfWidth);
  final size = switch (shape) {
    NodeShape.subroutine => Size(label.width + 2 * padX + 16, height),
    NodeShape.asymmetric => Size(label.width + 2 * padX + 12, height),
    NodeShape.stadium => Size(label.width + height + 6, height),
    NodeShape.circle || NodeShape.doubleCircle => Size(diameter, diameter),
    NodeShape.rhombus => Size(2 * halfWidth, math.max(2 * halfHeight + 12, 44)),
    NodeShape.hexagon ||
    NodeShape.parallelogram ||
    NodeShape.parallelogramAlt ||
    NodeShape.trapezoid ||
    NodeShape.trapezoidAlt => Size(label.width + 2 * padX + height / 2, height),
    NodeShape.cylinder => Size(label.width + 2 * padX, height + 14),
    _ => Size(label.width + 2 * padX, height),
  };
  return Size(math.max(size.width, 48), size.height);
}

/// One way to lay out a flowchart: a direction and how wide labels wrap.
class _Attempt {
  _Attempt(this.diagram, this.text, this.direction, this.wrap) {
    final nodes = diagram.nodes;
    for (final node in nodes) {
      final label = text.measure(
        node.label,
        VisualTextRole.body,
        maxWidth: nodeLabelWidth(node.shape) * wrap,
      );
      sizes.add(_nodeSize(node.shape, label));
    }
    for (final edge in diagram.edges) {
      edgeLabels.add(
        edge.label == null || edge.style == LineStyle.invisible
            ? null
            : text.measure(
                edge.label!,
                VisualTextRole.caption,
                maxWidth: edgeLabelWidth * wrap,
                maxLines: 3,
              ),
      );
    }
    loopRoom.addAll(List.filled(nodes.length, 0));
    for (final (e, edge) in diagram.edges.indexed) {
      if (edge.from != edge.to || edge.style == LineStyle.invisible) continue;
      loopRoom[edge.from] = math.max(
        loopRoom[edge.from],
        30 + (edgeLabels[e] == null ? 0 : edgeLabels[e]!.width + 10),
      );
    }
    final vertical =
        direction == LayeredDirection.down || direction == LayeredDirection.up;
    layout = layoutLayered(
      LayeredGraph(
        sizes: [
          for (final (i, size) in sizes.indexed)
            vertical
                ? Size(size.width + loopRoom[i], size.height)
                : Size(size.width, size.height + loopRoom[i]),
        ],
        edges: [
          for (final (e, edge) in diagram.edges.indexed)
            LayeredEdge(
              edge.from,
              edge.to,
              length: edge.length,
              label: edgeLabels[e] == null
                  ? null
                  : Size(edgeLabels[e]!.width + 12, edgeLabels[e]!.height + 6),
            ),
        ],
        clusters: [
          for (final cluster in diagram.clusters)
            LayeredCluster(
              title: text.measure(
                cluster.title,
                VisualTextRole.captionStrong,
                maxLines: 1,
              ),
              parent: cluster.parent,
            ),
        ],
        membership: [for (final node in nodes) node.cluster],
      ),
      direction,
    );
  }

  final FlowchartDiagram diagram;
  final TextMeasurer text;
  final LayeredDirection direction;

  /// A fraction of the usual label widths.
  final double wrap;
  final sizes = <Size>[];
  final edgeLabels = <Size?>[];

  /// Room beside a node for its self-loops and their labels.
  final loopRoom = <double>[];
  late final LayeredLayout layout;

  /// How far the layout must shrink to fit [width].
  double scale(double? width) =>
      width == null ? 1 : math.min(1, width / layout.size.width);
}

/// Lays out [diagram]. A chart wider than [fitWidth] turns top to bottom, or
/// wraps its labels narrower, when that needs less shrinking.
FlowchartLayout layoutFlowchart(
  FlowchartDiagram diagram,
  TextMeasurer text, {
  double? fitWidth,
}) {
  final nodes = diagram.nodes;
  var best = _Attempt(diagram, text, diagram.direction, 1);
  if (fitWidth != null && !best.layout.vertical && best.scale(fitWidth) < 1) {
    final turned = _Attempt(
      diagram,
      text,
      diagram.direction == LayeredDirection.right
          ? LayeredDirection.down
          : LayeredDirection.up,
      1,
    );
    if (turned.scale(fitWidth) > best.scale(fitWidth)) best = turned;
  }
  if (fitWidth != null && best.scale(fitWidth) < .8) {
    final narrow = _Attempt(diagram, text, best.direction, .7);
    if (narrow.scale(fitWidth) > best.scale(fitWidth)) best = narrow;
  }
  final layout = best.layout;
  final sizes = best.sizes;
  final edgeLabels = best.edgeLabels;
  final loopRoom = best.loopRoom;
  final vertical = layout.vertical;

  final rects = [
    for (final (i, size) in sizes.indexed)
      Rect.fromCenter(
        center:
            layout.centers[i] -
            (vertical
                ? Offset(loopRoom[i] / 2, 0)
                : Offset(0, loopRoom[i] / 2)),
        width: size.width,
        height: size.height,
      ),
  ];

  // Spread the ends of edges meeting one side of a node, ordered by where
  // each edge goes next so they do not cross at the node.
  final ports = <(int, PortSide), List<(int, bool, double)>>{};
  for (final (e, edge) in diagram.edges.indexed) {
    if (edge.from == edge.to || edge.style == LineStyle.invisible) continue;
    final route = layout.routes[e];
    final afterStart = route.isNotEmpty ? route.first : rects[edge.to].center;
    final beforeEnd = route.isNotEmpty ? route.last : rects[edge.from].center;
    final from = rects[edge.from].center;
    final to = rects[edge.to].center;
    final startSide = vertical
        ? (afterStart.dy >= from.dy ? PortSide.bottom : PortSide.top)
        : (afterStart.dx >= from.dx ? PortSide.right : PortSide.left);
    final endSide = vertical
        ? (beforeEnd.dy <= to.dy ? PortSide.top : PortSide.bottom)
        : (beforeEnd.dx <= to.dx ? PortSide.left : PortSide.right);
    (ports[(edge.from, startSide)] ??= []).add((
      e,
      true,
      vertical ? afterStart.dx : afterStart.dy,
    ));
    (ports[(edge.to, endSide)] ??= []).add((
      e,
      false,
      vertical ? beforeEnd.dx : beforeEnd.dy,
    ));
  }
  final starts = <int, Offset>{};
  final ends = <int, Offset>{};
  for (final MapEntry(key: (node, side), value: list) in ports.entries) {
    list.sort((a, b) {
      final compared = a.$3.compareTo(b.$3);
      return compared != 0 ? compared : a.$1.compareTo(b.$1);
    });
    final shape = nodes[node].shape;
    final half = _usableHalf(shape, rects[node], side);
    final step = list.length < 2
        ? 0.0
        : math.min(18.0, 2 * half / (list.length - 1));
    for (final (i, (e, isStart, _)) in list.indexed) {
      final point = _boundary(
        shape,
        rects[node],
        side,
        (i - (list.length - 1) / 2) * step,
      );
      if (isStart) {
        starts[e] = point;
      } else {
        ends[e] = point;
      }
    }
  }

  final edges = <PlacedEdge>[];
  for (final (e, edge) in diagram.edges.indexed) {
    if (edge.style == LineStyle.invisible) continue;
    if (edge.from == edge.to) {
      final rect = rects[edge.from];
      final shape = nodes[edge.from].shape;
      final List<Offset> points;
      final Offset label;
      if (vertical) {
        final quarter = rect.height / 4;
        final a = _boundary(shape, rect, PortSide.right, -quarter);
        final b = _boundary(shape, rect, PortSide.right, quarter);
        points = [a, a + const Offset(30, -10), b + const Offset(30, 10), b];
        label = Offset(
          rect.right + 34 + (edgeLabels[e]?.width ?? 0) / 2,
          rect.center.dy,
        );
      } else {
        final quarter = rect.width / 4;
        final a = _boundary(shape, rect, PortSide.bottom, -quarter);
        final b = _boundary(shape, rect, PortSide.bottom, quarter);
        points = [a, a + const Offset(-10, 30), b + const Offset(10, 30), b];
        label = Offset(
          rect.center.dx,
          rect.bottom + 34 + (edgeLabels[e]?.height ?? 0) / 2,
        );
      }
      edges.add(
        PlacedEdge(
          points,
          vertical: vertical,
          style: edge.style,
          start: edge.start,
          end: edge.end,
          label: edge.label,
          labelCenter: edge.label == null ? null : label,
          loop: true,
        ),
      );
      continue;
    }
    edges.add(
      PlacedEdge(
        [starts[e]!, ...layout.routes[e], ends[e]!],
        vertical: vertical,
        style: edge.style,
        start: edge.start,
        end: edge.end,
        label: edge.label,
        labelCenter: layout.labels[e],
      ),
    );
  }

  return FlowchartLayout(
    layout.size,
    [
      for (final (i, node) in nodes.indexed)
        PlacedNode(rects[i], node.shape, node.label),
    ],
    edges,
    [
      for (final (c, cluster) in diagram.clusters.indexed)
        if (layout.clusters[c] case final rect?)
          PlacedCluster(rect, cluster.title),
    ],
    wrap: best.wrap,
  );
}

/// How far from the centre of a side edge ends may spread.
double _usableHalf(NodeShape shape, Rect rect, PortSide side) {
  final across = side == PortSide.top || side == PortSide.bottom;
  final half = (across ? rect.width : rect.height) / 2;
  final other = (across ? rect.height : rect.width) / 2;
  return math.max(0, switch (shape) {
    NodeShape.rhombus => half * .35,
    NodeShape.circle || NodeShape.doubleCircle => half * .55,
    NodeShape.stadium when across => half - other,
    NodeShape.stadium => half * .5,
    NodeShape.hexagon ||
    NodeShape.parallelogram ||
    NodeShape.parallelogramAlt ||
    NodeShape.trapezoid ||
    NodeShape.trapezoidAlt => across ? half - other / 2 - 4 : half * .5,
    _ => half - 8,
  });
}

/// The point on a side of [shape] at [offset] from that side's centre.
Offset _boundary(NodeShape shape, Rect rect, PortSide side, double offset) {
  final center = rect.center;
  final halfWidth = rect.width / 2;
  final halfHeight = rect.height / 2;
  double arc(double radius, double distance) =>
      math.sqrt(math.max(0, radius * radius - distance * distance));
  if (side == PortSide.top || side == PortSide.bottom) {
    final reach = switch (shape) {
      NodeShape.rhombus =>
        halfHeight * (1 - (offset.abs() / halfWidth).clamp(0.0, 1.0)),
      NodeShape.circle || NodeShape.doubleCircle => arc(halfHeight, offset),
      NodeShape.stadium when offset.abs() > halfWidth - halfHeight => arc(
        halfHeight,
        offset.abs() - (halfWidth - halfHeight),
      ),
      _ => halfHeight,
    };
    return Offset(
      center.dx + offset,
      center.dy + (side == PortSide.bottom ? reach : -reach),
    );
  }
  final reach = switch (shape) {
    NodeShape.rhombus =>
      halfWidth * (1 - (offset.abs() / halfHeight).clamp(0.0, 1.0)),
    NodeShape.circle || NodeShape.doubleCircle => arc(halfWidth, offset),
    NodeShape.stadium => halfWidth - halfHeight + arc(halfHeight, offset),
    NodeShape.hexagon =>
      halfWidth - halfHeight / 2 * (offset.abs() / halfHeight),
    NodeShape.parallelogram ||
    NodeShape.parallelogramAlt ||
    NodeShape.trapezoid ||
    NodeShape.trapezoidAlt => halfWidth - halfHeight / 2,
    _ => halfWidth,
  };
  return Offset(
    center.dx + (side == PortSide.right ? reach : -reach),
    center.dy + offset,
  );
}
