import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/ui/render/visuals/flowchart.dart';
import 'package:tako/ui/render/visuals/layered_layout.dart';
import 'package:tako/ui/render/visuals/mermaid.dart';
import 'package:tako/ui/render/visuals/mindmap.dart';
import 'package:tako/ui/render/visuals/sequence.dart';

import 'fake_measurer.dart';

/// A random graph with cycles, parallel edges, self-loops and labels.
LayeredGraph randomGraph(int seed, {bool clusters = false}) {
  final random = math.Random(seed);
  final count = 4 + random.nextInt(37);
  final edges = <LayeredEdge>[];
  for (var i = 0; i < count * 1.4; i++) {
    final from = random.nextInt(count);
    final to = random.nextInt(count);
    edges.add(
      LayeredEdge(
        from,
        to,
        length: random.nextInt(5) == 0 ? 2 : 1,
        label: random.nextInt(4) == 0 ? const Size(40, 16) : null,
      ),
    );
  }
  return LayeredGraph(
    sizes: [
      for (var i = 0; i < count; i++)
        Size(
          48 + random.nextInt(100).toDouble(),
          30 + random.nextInt(30).toDouble(),
        ),
    ],
    edges: edges,
    clusters: clusters
        ? const [
            LayeredCluster(title: Size(60, 16)),
            LayeredCluster(title: Size(40, 16), parent: 0),
            LayeredCluster(title: Size(50, 16)),
          ]
        : const [],
    membership: clusters
        ? [
            for (var i = 0; i < count; i++) const [null, 0, 1, 2][i % 4],
          ]
        : const [],
  );
}

List<Rect> nodeRects(LayeredGraph graph, LayeredLayout layout) => [
  for (var i = 0; i < graph.sizes.length; i++)
    Rect.fromCenter(
      center: layout.centers[i],
      width: graph.sizes[i].width,
      height: graph.sizes[i].height,
    ),
];

void main() {
  test('random graphs lay out without overlaps, along the flow', () {
    for (var seed = 0; seed < 60; seed++) {
      final graph = randomGraph(seed, clusters: seed.isOdd);
      for (final direction in LayeredDirection.values) {
        final layout = layoutLayered(graph, direction);
        final rects = nodeRects(graph, layout);
        final bounds = Offset.zero & layout.size;
        for (var a = 0; a < rects.length; a++) {
          expect(
            bounds.inflate(.5).contains(rects[a].topLeft) &&
                bounds.inflate(.5).contains(rects[a].bottomRight),
            isTrue,
            reason: 'seed $seed node $a lies outside the canvas',
          );
          for (var b = a + 1; b < rects.length; b++) {
            expect(
              rects[a].deflate(.5).overlaps(rects[b].deflate(.5)),
              isFalse,
              reason: 'seed $seed $direction nodes $a and $b overlap',
            );
          }
        }
        for (final (e, edge) in graph.edges.indexed) {
          if (edge.from == edge.to) {
            expect(layout.routes[e], isEmpty);
            continue;
          }
          // Every edge moves at least one rank along the flow, in the
          // direction it was laid out.
          final source = layout.reversed[e] ? edge.to : edge.from;
          final target = layout.reversed[e] ? edge.from : edge.to;
          expect(
            layout.ranks[target],
            greaterThanOrEqualTo(layout.ranks[source] + edge.length),
            reason: 'seed $seed edge $e',
          );
          double along(Offset point) => switch (direction) {
            LayeredDirection.down => point.dy,
            LayeredDirection.up => -point.dy,
            LayeredDirection.right => point.dx,
            LayeredDirection.left => -point.dx,
          };
          final route = layout.reversed[e]
              ? layout.routes[e].reversed.toList()
              : layout.routes[e];
          final points = [
            layout.centers[source],
            ...route,
            layout.centers[target],
          ];
          for (var i = 0; i + 1 < points.length; i++) {
            expect(
              along(points[i + 1]),
              greaterThan(along(points[i])),
              reason: 'seed $seed edge $e goes backwards',
            );
          }
          if (edge.label != null) {
            final label = Rect.fromCenter(
              center: layout.labels[e]!,
              width: 40,
              height: 16,
            );
            for (final (n, rect) in rects.indexed) {
              expect(
                rect.deflate(.5).overlaps(label.deflate(.5)),
                isFalse,
                reason: 'seed $seed label $e covers node $n',
              );
            }
          }
        }
        for (final (c, box) in layout.clusters.indexed) {
          if (box == null) continue;
          for (var n = 0; n < rects.length; n++) {
            final inside = <int?>{
              for (
                int? m = graph.membership[n];
                m != null;
                m = graph.clusters[m].parent
              )
                m,
            }.contains(c);
            if (inside) {
              expect(
                box.contains(rects[n].center),
                isTrue,
                reason: 'seed $seed cluster $c lost node $n',
              );
            } else {
              expect(
                box.overlaps(rects[n].deflate(1)),
                isFalse,
                reason: 'seed $seed cluster $c covers node $n',
              );
            }
          }
        }
      }
    }
  });

  test('layouts are deterministic', () {
    final graph = randomGraph(7, clusters: true);
    final first = layoutLayered(graph, LayeredDirection.down);
    final second = layoutLayered(graph, LayeredDirection.down);
    expect(second.centers, first.centers);
    expect(second.routes, first.routes);
    expect(second.size, first.size);
  });

  test('a cycle keeps every node and reverses one edge', () {
    const graph = LayeredGraph(
      sizes: [Size(60, 30), Size(60, 30), Size(60, 30)],
      edges: [LayeredEdge(0, 1), LayeredEdge(1, 2), LayeredEdge(2, 0)],
    );
    final layout = layoutLayered(graph, LayeredDirection.down);
    expect(layout.reversed.where((r) => r), hasLength(1));
    expect(layout.ranks, [0, 1, 2]);
  });

  test('a late source sits just above where it is used', () {
    const graph = LayeredGraph(
      sizes: [Size(60, 30), Size(60, 30), Size(60, 30), Size(60, 30)],
      edges: [LayeredEdge(0, 1), LayeredEdge(1, 2), LayeredEdge(3, 2)],
    );
    expect(layoutLayered(graph, LayeredDirection.down).ranks[3], 1);
  });

  test('a single chain stays straight', () {
    const graph = LayeredGraph(
      sizes: [Size(80, 30), Size(60, 30), Size(100, 30)],
      edges: [LayeredEdge(0, 1), LayeredEdge(1, 2)],
    );
    final layout = layoutLayered(graph, LayeredDirection.down);
    expect(layout.centers.map((c) => c.dx).toSet(), hasLength(1));
  });

  test('forty nodes lay out quickly', () {
    final graph = randomGraph(3);
    final watch = Stopwatch()..start();
    for (var i = 0; i < 5; i++) {
      layoutLayered(graph, LayeredDirection.down);
    }
    expect(watch.elapsedMilliseconds / 5, lessThan(200));
  });

  group('diagram layouts', () {
    final text = FakeMeasurer();

    test('flowcharts place ports on node outlines and keep rhombi even', () {
      final diagram =
          parseMermaid('''
flowchart TD
  A([Start]) --> B{Is it ready?}
  B -->|yes| C[Ship]
  B -->|no| D[Wait]
  D --> B
  C --> C
''')!
              as FlowchartDiagram;
      final layout = layoutFlowchart(diagram, text);
      final rhombus = layout.nodes[1];
      expect(rhombus.shape, NodeShape.rhombus);
      final edges = layout.edges.where((e) => !e.loop).toList();
      for (final edge in edges) {
        final start = edge.points.first;
        final end = edge.points.last;
        final from = layout.nodes.firstWhere(
          (n) => n.rect.inflate(1).contains(start),
        );
        final to = layout.nodes.firstWhere(
          (n) => n.rect.inflate(1).contains(end),
        );
        expect(from, isNot(to));
      }
      expect(layout.edges.where((e) => e.loop), hasLength(1));
      expect(layout.edges.where((e) => e.label != null), hasLength(2));
      // Both answers leave the rhombus and the retry comes back to it: three
      // ends spread evenly around its bottom tip, each on the outline.
      final ends = [
        for (final edge in edges)
          for (final point in [edge.points.first, edge.points.last])
            if (rhombus.rect.inflate(1).contains(point) &&
                point.dy > rhombus.rect.center.dy)
              point,
      ]..sort((a, b) => a.dx.compareTo(b.dx));
      expect(ends, hasLength(3));
      final center = rhombus.rect.center;
      expect(ends.first.dx + ends.last.dx - 2 * center.dx, closeTo(0, .01));
      expect(ends[1].dx, closeTo(center.dx, .01));
      for (final point in ends) {
        final halfWidth = rhombus.rect.width / 2;
        final halfHeight = rhombus.rect.height / 2;
        expect(
          (point.dx - center.dx).abs() / halfWidth +
              (point.dy - center.dy).abs() / halfHeight,
          closeTo(1, .01),
        );
      }
    });

    test('a wide left-to-right chart turns down to fit', () {
      final diagram =
          parseMermaid(
                'flowchart LR\n  A[Collect] --> B[Clean] --> C[Analyse] '
                '--> D[Report] --> E[Publish]',
              )!
              as FlowchartDiagram;
      final natural = layoutFlowchart(diagram, text);
      final fitted = layoutFlowchart(diagram, text, fitWidth: 300);
      expect(natural.size.width, greaterThan(300));
      expect(fitted.size.width, lessThanOrEqualTo(300));
      expect(fitted.edges.first.vertical, isTrue);
    });

    test('sequence labels wrap narrower to fit the column', () {
      final diagram =
          parseMermaid(
                'sequenceDiagram\n  A->>B: ${'a long message ' * 4}\n'
                '  B->>C: ${'another long reply ' * 4}',
              )!
              as SequenceDiagram;
      final natural = layoutSequence(diagram, text);
      final fitted = layoutSequence(diagram, text, fitWidth: 300);
      expect(fitted.size.width, lessThan(natural.size.width));
      expect(fitted.messageWidth, lessThan(messageLabelWidth));
      final xs = fitted.participants.map((p) => p.rect.center.dx).toList();
      expect(xs, orderedEquals([...xs]..sort()));
    });

    test('mind maps centre parents on their children', () {
      final diagram =
          parseMermaid('mindmap\n  Root\n    A\n      A1\n      A2\n    B')!
              as MindmapDiagram;
      final layout = layoutMindmap(diagram, text);
      final byLabel = {for (final node in layout.nodes) node.label: node};
      final a = byLabel['A']!.rect.center.dy;
      expect(
        a,
        closeTo(
          (byLabel['A1']!.rect.center.dy + byLabel['A2']!.rect.center.dy) / 2,
          .01,
        ),
      );
      expect(byLabel['B']!.branch, 1);
      expect(byLabel['A2']!.branch, 0);
      expect(layout.links, hasLength(4));
    });
  });
}
