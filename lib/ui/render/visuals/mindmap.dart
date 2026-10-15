import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'mermaid.dart';
import 'visual_text.dart';

class MindmapNode {
  MindmapNode(this.label);
  final String label;
  final children = <MindmapNode>[];
}

final class MindmapDiagram extends MermaidDiagram {
  const MindmapDiagram(this.root, {String? title}) : super(title);
  final MindmapNode root;
}

const maxMindmapNodes = 200;

final _shaped = RegExp(
  r'^[\w-]*\s*(\(\(|\)\)|\{\{|\(|\)|\[)([\s\S]*?)(\)\)|\(\(|\}\}|\)|\(|\])$',
);

/// One root, then children by indentation. Shapes, icons and classes are
/// dropped; every branch is drawn in its own colour instead.
MindmapDiagram parseMindmap(List<String> lines, String? title) {
  MindmapNode? root;
  final stack = <(int, MindmapNode)>[];
  var count = 0;
  for (final line in lines) {
    final indent = line
        .substring(0, line.length - line.trimLeft().length)
        .replaceAll('\t', '    ')
        .length;
    var text = line
        .trim()
        .replaceAll(RegExp(r'::icon\([^)]*\)'), '')
        .replaceAll(RegExp(r':::[\w\s-]*$'), '')
        .trim();
    if (text.isEmpty) continue;
    if (_shaped.firstMatch(text) case final match?) text = match[2]!;
    final node = MindmapNode(cleanMermaidText(text));
    if (node.label.isEmpty) continue;
    if (++count > maxMindmapNodes) {
      throw const FormatException('Mind map is too large');
    }
    if (root == null) {
      root = node;
      stack.add((indent, node));
      continue;
    }
    while (stack.isNotEmpty && stack.last.$1 >= indent) {
      stack.removeLast();
    }
    if (stack.isEmpty) throw const FormatException('A mind map has one root');
    stack.last.$2.children.add(node);
    stack.add((indent, node));
  }
  if (root == null) throw const FormatException('A mind map needs a root');
  return MindmapDiagram(root, title: title);
}

class PlacedMindNode {
  const PlacedMindNode(this.rect, this.label, this.depth, this.branch);
  final Rect rect;
  final String label;
  final int depth;

  /// The first-level branch this node belongs to, or -1 for the root.
  final int branch;
}

class MindLink {
  const MindLink(this.from, this.to, this.depth, this.branch);
  final Offset from;
  final Offset to;

  /// The depth of the child end.
  final int depth;
  final int branch;
}

class MindmapLayout {
  const MindmapLayout(
    this.size,
    this.nodes,
    this.links, {
    this.rootWidth = mindRootWidth,
    this.labelWidth = mindLabelWidth,
  });

  final Size size;
  final List<PlacedMindNode> nodes;
  final List<MindLink> links;

  /// Wrap widths for the root and for every other label.
  final double rootWidth;
  final double labelWidth;
}

VisualTextRole mindTextRole(int depth) => switch (depth) {
  0 => VisualTextRole.title,
  1 => VisualTextRole.bodyStrong,
  2 => VisualTextRole.body,
  _ => VisualTextRole.caption,
};

const mindRootWidth = 160.0;
const mindLabelWidth = 140.0;

/// Padding around a label: the root and first level are boxes, deeper levels
/// are underlined text.
EdgeInsets mindPadding(int depth) => switch (depth) {
  0 => const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
  1 => const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
  _ => const EdgeInsets.fromLTRB(2, 3, 2, 5),
};

/// A left-to-right tree: columns by depth, each parent centred on its
/// children. Labels wrap narrower when [fitWidth] is small.
MindmapLayout layoutMindmap(
  MindmapDiagram diagram,
  TextMeasurer text, {
  double? fitWidth,
}) {
  int depthOf(MindmapNode node) => node.children.isEmpty
      ? 1
      : 1 + node.children.map(depthOf).reduce(math.max);
  final depths = depthOf(diagram.root);
  final gap = fitWidth != null && fitWidth < 360 ? 28.0 : 36.0;
  final labelWidth = fitWidth == null
      ? mindLabelWidth
      : ((fitWidth - (depths - 1) * gap) / depths - 24).clamp(
          64.0,
          mindLabelWidth,
        );
  final rootWidth = fitWidth == null
      ? mindRootWidth
      : (labelWidth + 16).clamp(80.0, mindRootWidth);
  final entries = <(MindmapNode, int, int, Size)>[];
  final sizes = <MindmapNode, Size>{};
  final columns = <double>[];
  void measure(MindmapNode node, int depth, int branch) {
    final label = text.measure(
      node.label,
      mindTextRole(depth),
      maxWidth: depth == 0 ? rootWidth : labelWidth,
    );
    final size = mindPadding(depth).inflateSize(label);
    sizes[node] = size;
    entries.add((node, depth, branch, size));
    if (columns.length <= depth) columns.add(0);
    columns[depth] = math.max(columns[depth], size.width);
    for (final (index, child) in node.children.indexed) {
      measure(child, depth + 1, depth == 0 ? index : branch);
    }
  }

  measure(diagram.root, 0, -1);
  final columnX = <double>[0];
  for (var depth = 1; depth < columns.length; depth++) {
    columnX.add(columnX.last + columns[depth - 1] + gap);
  }

  final tops = <MindmapNode, double>{};
  var cursor = 0.0;
  void shift(MindmapNode node, double by) {
    tops[node] = tops[node]! + by;
    for (final child in node.children) {
      shift(child, by);
    }
  }

  void place(MindmapNode node, int depth) {
    final size = sizes[node]!;
    if (node.children.isEmpty) {
      tops[node] = cursor;
      cursor += size.height + (depth <= 1 ? 14 : 6);
      return;
    }
    final start = cursor;
    for (final child in node.children) {
      place(child, depth + 1);
    }
    final first = node.children.first;
    final last = node.children.last;
    final center =
        (tops[first]! +
            sizes[first]!.height / 2 +
            tops[last]! +
            sizes[last]!.height / 2) /
        2;
    tops[node] = center - size.height / 2;
    // A parent taller than its children pushes them, and itself, down.
    if (tops[node]! < start) shift(node, start - tops[node]!);
    final bottom = tops[node]! + size.height + (depth <= 1 ? 14 : 6);
    if (bottom > cursor) cursor = bottom;
  }

  place(diagram.root, 0);
  final nodes = <PlacedMindNode>[];
  final rects = <MindmapNode, Rect>{};
  for (final (node, depth, branch, size) in entries) {
    final rect = Rect.fromLTWH(
      columnX[depth],
      tops[node]!,
      size.width,
      size.height,
    );
    rects[node] = rect;
    nodes.add(PlacedMindNode(rect, node.label, depth, branch));
  }
  final links = <MindLink>[];
  for (final (node, depth, branch, _) in entries) {
    final parent = rects[node]!;
    for (final child in node.children) {
      final rect = rects[child]!;
      links.add(
        MindLink(
          depth <= 1
              ? Offset(parent.right, parent.center.dy)
              : Offset(parent.right, parent.bottom),
          depth + 1 <= 1
              ? Offset(rect.left, rect.center.dy)
              : Offset(rect.left, rect.bottom),
          depth + 1,
          depth == 0 ? node.children.indexOf(child) : branch,
        ),
      );
    }
  }
  var width = 0.0;
  var height = 0.0;
  for (final node in nodes) {
    width = math.max(width, node.rect.right);
    height = math.max(height, node.rect.bottom);
  }
  return MindmapLayout(
    Size(width + 4, height + 4),
    nodes,
    links,
    rootWidth: rootWidth,
    labelWidth: labelWidth,
  );
}
