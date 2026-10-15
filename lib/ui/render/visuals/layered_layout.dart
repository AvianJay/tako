import 'dart:math' as math;
import 'dart:ui';

/// Where edges point: down for top-to-bottom charts, right for left-to-right.
enum LayeredDirection { down, up, right, left }

class LayeredEdge {
  const LayeredEdge(this.from, this.to, {this.length = 1, this.label});
  final int from;
  final int to;

  /// The minimum number of ranks the edge spans.
  final int length;

  /// Room reserved for a label halfway along the edge.
  final Size? label;
}

class LayeredCluster {
  const LayeredCluster({required this.title, this.parent});
  final Size title;
  final int? parent;
}

class LayeredGraph {
  const LayeredGraph({
    required this.sizes,
    required this.edges,
    this.clusters = const [],
    this.membership = const [],
  });

  final List<Size> sizes;
  final List<LayeredEdge> edges;
  final List<LayeredCluster> clusters;

  /// The innermost cluster of each node, if any.
  final List<int?> membership;
}

class LayeredLayout {
  const LayeredLayout({
    required this.size,
    required this.direction,
    required this.centers,
    required this.routes,
    required this.labels,
    required this.clusters,
    required this.ranks,
    required this.reversed,
  });

  final Size size;
  final LayeredDirection direction;
  final List<Offset> centers;

  /// Bend points of each edge, from its source to its target. Self-loops have
  /// none.
  final List<List<Offset>> routes;
  final List<Offset?> labels;

  /// A box per cluster, or null where one would overlap other nodes.
  final List<Rect?> clusters;
  final List<int> ranks;

  /// Edges laid out against their direction to break a cycle.
  final List<bool> reversed;

  bool get vertical =>
      direction == LayeredDirection.down || direction == LayeredDirection.up;
}

const _rankGap = 44.0;
const _nodeGap = 26.0;
const _dummyGap = 12.0;
const _clusterPad = 14.0;
const _margin = 6.0;

class _Vertex {
  _Vertex({
    required this.cross,
    required this.main,
    required this.rank,
    this.real = -1,
    this.cluster,
  });

  /// Size across the flow and along it.
  final double cross;
  final double main;
  final int rank;
  final int real;
  final int? cluster;
  bool get dummy => real < 0;

  final up = <int>[];
  final upWeights = <double>[];
  final down = <int>[];
  final downWeights = <double>[];
  int order = 0;
  double position = 0;
  double x = 0;
  double y = 0;
}

/// A layered (Sugiyama-style) layout for small directed graphs: cycles are
/// broken, nodes are ranked along the flow, long edges get bend points, and
/// orderings that cross less are kept. Clusters stay contiguous in every
/// rank. The result is deterministic.
LayeredLayout layoutLayered(LayeredGraph graph, LayeredDirection direction) {
  final vertical =
      direction == LayeredDirection.down || direction == LayeredDirection.up;
  final count = graph.sizes.length;
  final edges = graph.edges;
  int? clusterOf(int node) =>
      node < graph.membership.length ? graph.membership[node] : null;

  // Break cycles by reversing the back edges of a depth-first search that
  // starts from nodes without incoming edges, in declaration order.
  final reversed = List<bool>.filled(edges.length, false);
  final outgoing = List.generate(count, (_) => <int>[]);
  final indegree = List<int>.filled(count, 0);
  for (final (e, edge) in edges.indexed) {
    if (edge.from == edge.to) continue;
    outgoing[edge.from].add(e);
    indegree[edge.to]++;
  }
  final state = List<int>.filled(count, 0);
  for (final root in [
    for (var v = 0; v < count; v++)
      if (indegree[v] == 0) v,
    for (var v = 0; v < count; v++)
      if (indegree[v] > 0) v,
  ]) {
    if (state[root] != 0) continue;
    state[root] = 1;
    final stack = [(root, 0)];
    while (stack.isNotEmpty) {
      final (v, next) = stack.last;
      if (next < outgoing[v].length) {
        stack.last = (v, next + 1);
        final e = outgoing[v][next];
        final w = edges[e].to;
        if (state[w] == 1) {
          reversed[e] = true;
        } else if (state[w] == 0) {
          state[w] = 1;
          stack.add((w, 0));
        }
      } else {
        state[v] = 2;
        stack.removeLast();
      }
    }
  }
  int source(int e) => reversed[e] ? edges[e].to : edges[e].from;
  int target(int e) => reversed[e] ? edges[e].from : edges[e].to;

  // Rank by longest path. Labelled edges get a rank of their own for the
  // label, so all spans double when any edge has one.
  final doubled = edges.any((e) => e.label != null && e.from != e.to);
  int span(int e) => math.max(1, edges[e].length) * (doubled ? 2 : 1);
  final successors = List.generate(count, (_) => <int>[]);
  final predecessors = List.generate(count, (_) => <int>[]);
  for (final (e, edge) in edges.indexed) {
    if (edge.from == edge.to) continue;
    successors[source(e)].add(e);
    predecessors[target(e)].add(e);
  }
  final waiting = [for (var v = 0; v < count; v++) predecessors[v].length];
  final order = [
    for (var v = 0; v < count; v++)
      if (waiting[v] == 0) v,
  ];
  for (var head = 0; head < order.length; head++) {
    for (final e in successors[order[head]]) {
      if (--waiting[target(e)] == 0) order.add(target(e));
    }
  }
  final rank = List<int>.filled(count, 0);
  for (final v in order) {
    for (final e in predecessors[v]) {
      rank[v] = math.max(rank[v], rank[source(e)] + span(e));
    }
  }
  // Move nodes toward the side with more edges: a source used late sits just
  // above its use instead of at the top.
  for (final v in order.reversed) {
    if (successors[v].length > predecessors[v].length) {
      final limit = successors[v]
          .map((e) => rank[target(e)] - span(e))
          .reduce(math.min);
      if (limit > rank[v]) rank[v] = limit;
    }
  }
  for (final v in order) {
    if (predecessors[v].length > successors[v].length) {
      rank[v] = predecessors[v]
          .map((e) => rank[source(e)] + span(e))
          .reduce(math.max);
    }
  }
  if (count > 0) {
    final lowest = rank.reduce(math.min);
    for (var v = 0; v < count; v++) {
      rank[v] -= lowest;
    }
  }

  // Long edges become chains of dummy vertices, one per rank.
  Size oriented(Size size) => vertical ? size : Size(size.height, size.width);
  final vertices = [
    for (var v = 0; v < count; v++)
      _Vertex(
        cross: oriented(graph.sizes[v]).width,
        main: oriented(graph.sizes[v]).height,
        rank: rank[v],
        real: v,
        cluster: clusterOf(v),
      ),
  ];
  final chains = List.generate(edges.length, (_) => <int>[]);
  final labelVertices = List<int?>.filled(edges.length, null);
  void connect(int upper, int lower) {
    final dummies =
        (vertices[upper].dummy ? 1 : 0) + (vertices[lower].dummy ? 1 : 0);
    // Edges inside a cluster pull harder, which keeps the cluster compact
    // enough for its box.
    final cluster = vertices[upper].cluster;
    final weight =
        const [1.0, 2.0, 8.0][dummies] *
        (cluster != null && cluster == vertices[lower].cluster ? 4 : 1);
    vertices[upper].down.add(lower);
    vertices[upper].downWeights.add(weight);
    vertices[lower].up.add(upper);
    vertices[lower].upWeights.add(weight);
  }

  for (final (e, edge) in edges.indexed) {
    if (edge.from == edge.to) continue;
    final from = source(e);
    final to = target(e);
    final labelRank = edge.label == null
        ? null
        : rank[from] + (rank[to] - rank[from]) ~/ 2;
    final cluster = _commonCluster(
      clusterOf(from),
      clusterOf(to),
      graph.clusters,
    );
    var previous = from;
    for (var r = rank[from] + 1; r < rank[to]; r++) {
      final size = r == labelRank ? oriented(edge.label!) : Size.zero;
      vertices.add(
        _Vertex(
          cross: size.width,
          main: size.height,
          rank: r,
          cluster: cluster,
        ),
      );
      final dummy = vertices.length - 1;
      chains[e].add(dummy);
      if (r == labelRank) labelVertices[e] = dummy;
      connect(previous, dummy);
      previous = dummy;
    }
    connect(previous, to);
  }

  final paths = [
    for (final vertex in vertices) _path(vertex.cluster, graph.clusters),
  ];
  final rankCount = vertices.isEmpty
      ? 0
      : vertices.map((v) => v.rank).reduce(math.max) + 1;
  var layers = List.generate(rankCount, (_) => <int>[]);

  // Initial order: depth-first from the sources, so children start near
  // their parents.
  final seen = List<bool>.filled(vertices.length, false);
  void visit(int start) {
    final stack = [start];
    while (stack.isNotEmpty) {
      final v = stack.removeLast();
      if (seen[v]) continue;
      seen[v] = true;
      layers[vertices[v].rank].add(v);
      for (final w in vertices[v].down.reversed) {
        if (!seen[w]) stack.add(w);
      }
    }
  }

  for (var v = 0; v < count; v++) {
    if (vertices[v].up.isEmpty) visit(v);
  }
  for (var v = 0; v < vertices.length; v++) {
    visit(v);
  }

  void index(List<int> layer) {
    for (final (i, v) in layer.indexed) {
      vertices[v].order = i;
      vertices[v].position = (i + .5) / layer.length;
    }
  }

  layers.forEach(index);

  int crossings() {
    var total = 0;
    for (var r = 0; r + 1 < layers.length; r++) {
      final sequence = <int>[];
      for (final v in layers[r]) {
        sequence.addAll(
          [for (final w in vertices[v].down) vertices[w].order]..sort(),
        );
      }
      total += _inversions(sequence, layers[r + 1].length);
    }
    return total;
  }

  // Clusters sort as blocks: every member of a cluster shares the cluster's
  // key at that depth, so nothing else can land between them.
  List<double> clusterKeys() {
    final sums = List<double>.filled(graph.clusters.length, 0);
    final counts = List<int>.filled(graph.clusters.length, 0);
    for (final (v, path) in paths.indexed) {
      for (final c in path) {
        sums[c] += vertices[v].position;
        counts[c]++;
      }
    }
    return [
      for (var c = 0; c < sums.length; c++)
        counts[c] == 0 ? 0 : sums[c] / counts[c],
    ];
  }

  double barycenter(int v, bool downward) {
    final neighbours = downward ? vertices[v].up : vertices[v].down;
    if (neighbours.isEmpty) return vertices[v].position;
    return neighbours.map((w) => vertices[w].position).reduce((a, b) => a + b) /
        neighbours.length;
  }

  void sortLayer(List<int> layer, bool downward, List<double> keys) {
    final sortKeys = {
      for (final v in layer)
        v: [for (final c in paths[v]) keys[c], barycenter(v, downward)],
    };
    final previous = {for (final v in layer) v: vertices[v].order};
    layer.sort((a, b) {
      final ka = sortKeys[a]!;
      final kb = sortKeys[b]!;
      for (var i = 0; i < ka.length && i < kb.length; i++) {
        final compared = ka[i].compareTo(kb[i]);
        if (compared != 0) return compared;
      }
      return previous[a]!.compareTo(previous[b]!);
    });
    index(layer);
  }

  int pairCrossings(int left, int right) {
    var total = 0;
    for (final side in [
      (vertices[left].up, vertices[right].up),
      (vertices[left].down, vertices[right].down),
    ]) {
      for (final a in side.$1) {
        for (final b in side.$2) {
          if (vertices[a].order > vertices[b].order) total++;
        }
      }
    }
    return total;
  }

  bool samePath(int a, int b) {
    final pa = paths[a];
    final pb = paths[b];
    if (pa.length != pb.length) return false;
    for (var i = 0; i < pa.length; i++) {
      if (pa[i] != pb[i]) return false;
    }
    return true;
  }

  void transpose() {
    for (var pass = 0; pass < 4; pass++) {
      var improved = false;
      for (final layer in layers) {
        for (var i = 0; i + 1 < layer.length; i++) {
          final a = layer[i];
          final b = layer[i + 1];
          if (!samePath(a, b)) continue;
          if (pairCrossings(b, a) < pairCrossings(a, b)) {
            layer[i] = b;
            layer[i + 1] = a;
            index(layer);
            improved = true;
          }
        }
      }
      if (!improved) break;
    }
  }

  var best = [for (final layer in layers) List.of(layer)];
  var fewest = crossings();
  var stale = 0;
  for (var sweep = 0; sweep < 24 && fewest > 0 && stale < 4; sweep++) {
    final downward = sweep.isEven;
    final keys = clusterKeys();
    if (downward) {
      for (var r = 1; r < layers.length; r++) {
        sortLayer(layers[r], true, keys);
      }
    } else {
      for (var r = layers.length - 2; r >= 0; r--) {
        sortLayer(layers[r], false, keys);
      }
    }
    transpose();
    final current = crossings();
    if (current < fewest) {
      fewest = current;
      best = [for (final layer in layers) List.of(layer)];
      stale = 0;
    } else {
      stale++;
    }
  }
  layers = best;
  layers.forEach(index);

  // Positions across the flow: each vertex moves toward the weighted median
  // of its neighbours, solved exactly per rank under the ordering and the
  // minimum gaps. Dummy chains weigh more, which keeps long edges straight.
  final titleBand = graph.clusters.isEmpty
      ? 0.0
      : graph.clusters.map((c) => c.title.height).reduce(math.max) + 10;
  final clusterSide = vertical ? _clusterPad : math.max(_clusterPad, titleBand);
  double separation(int a, int b) {
    final va = vertices[a];
    final vb = vertices[b];
    final gap = va.dummy && vb.dummy
        ? _dummyGap * .7
        : va.dummy || vb.dummy
        ? _dummyGap
        : _nodeGap;
    final pa = paths[a];
    final pb = paths[b];
    var shared = 0;
    while (shared < pa.length &&
        shared < pb.length &&
        pa[shared] == pb[shared]) {
      shared++;
    }
    final boundaries = pa.length + pb.length - 2 * shared;
    return (va.cross + vb.cross) / 2 + gap + boundaries * clusterSide;
  }

  for (final layer in layers) {
    var x = 0.0;
    for (final (i, v) in layer.indexed) {
      if (i > 0) x += separation(layer[i - 1], v);
      vertices[v].x = x;
    }
    final middle = layer.isEmpty
        ? 0.0
        : (vertices[layer.first].x + vertices[layer.last].x) / 2;
    for (final v in layer) {
      vertices[v].x -= middle;
    }
  }

  void place(List<int> layer, {required bool up, required bool down}) {
    final targets = <double>[];
    final weights = <double>[];
    final gaps = <double>[];
    for (final (i, v) in layer.indexed) {
      final vertex = vertices[v];
      final neighbours = [if (up) ...vertex.up, if (down) ...vertex.down];
      final neighbourWeights = [
        if (up) ...vertex.upWeights,
        if (down) ...vertex.downWeights,
      ];
      if (neighbours.isEmpty) {
        targets.add(vertex.x);
        weights.add(.25);
      } else {
        targets.add(
          _weightedMedian([
            for (final w in neighbours) vertices[w].x,
          ], neighbourWeights),
        );
        weights.add(neighbourWeights.reduce((a, b) => a + b));
      }
      if (i > 0) gaps.add(separation(layer[i - 1], v));
    }
    final xs = _isotonic(targets, weights, gaps);
    for (final (i, v) in layer.indexed) {
      vertices[v].x = xs[i];
    }
  }

  for (var pass = 0; pass < 8; pass++) {
    if (pass.isEven) {
      for (var r = 1; r < layers.length; r++) {
        place(layers[r], up: true, down: false);
      }
    } else {
      for (var r = layers.length - 2; r >= 0; r--) {
        place(layers[r], up: false, down: true);
      }
    }
  }
  for (final layer in layers) {
    place(layer, up: true, down: true);
  }

  // Positions along the flow. A cluster that starts at a rank needs room
  // above it for its title.
  final heights = List<double>.filled(rankCount, 0);
  for (final vertex in vertices) {
    heights[vertex.rank] = math.max(heights[vertex.rank], vertex.main);
  }
  final firstRank = List<int?>.filled(graph.clusters.length, null);
  final lastRank = List<int?>.filled(graph.clusters.length, null);
  for (var v = 0; v < count; v++) {
    for (final c in paths[v]) {
      firstRank[c] = math.min(firstRank[c] ?? rank[v], rank[v]);
      lastRank[c] = math.max(lastRank[c] ?? rank[v], rank[v]);
    }
  }
  final above = List<double>.filled(rankCount, 0);
  final below = List<double>.filled(rankCount, 0);
  for (var c = 0; c < graph.clusters.length; c++) {
    if (firstRank[c] case final first?) {
      above[first] += vertical ? graph.clusters[c].title.height + 12 : 12;
    }
    if (lastRank[c] case final last?) below[last] += 12;
  }
  final gap = doubled ? _rankGap / 2 : _rankGap;
  final rankY = List<double>.filled(rankCount, 0);
  for (var r = 0; r < rankCount; r++) {
    rankY[r] = r == 0
        ? above[0] + heights[0] / 2
        : rankY[r - 1] +
              heights[r - 1] / 2 +
              gap +
              below[r - 1] +
              above[r] +
              heights[r] / 2;
  }
  for (final vertex in vertices) {
    vertex.y = rankY[vertex.rank];
  }

  Rect vertexRect(int v) => Rect.fromCenter(
    center: Offset(vertices[v].x, vertices[v].y),
    width: vertices[v].cross,
    height: vertices[v].main,
  );

  // Cluster boxes, innermost first. A box that would cover a node outside
  // the cluster, or another box, is dropped; its nodes keep their places.
  final boxes = List<Rect?>.filled(graph.clusters.length, null);
  final byDepth = List.generate(graph.clusters.length, (c) => c)
    ..sort(
      (a, b) => _path(
        b,
        graph.clusters,
      ).length.compareTo(_path(a, graph.clusters).length),
    );
  for (final c in byDepth) {
    Rect? box;
    for (var v = 0; v < count; v++) {
      if (!paths[v].contains(c)) continue;
      box = box?.expandToInclude(vertexRect(v)) ?? vertexRect(v);
    }
    for (var child = 0; child < graph.clusters.length; child++) {
      if (graph.clusters[child].parent == c && boxes[child] != null) {
        box = box?.expandToInclude(boxes[child]!) ?? boxes[child];
      }
    }
    if (box == null) continue;
    final title = graph.clusters[c].title.height + 10;
    box = vertical
        ? Rect.fromLTRB(
            box.left - _clusterPad + 2,
            box.top - title,
            box.right + _clusterPad - 2,
            box.bottom + 10,
          )
        : Rect.fromLTRB(
            box.left - title,
            box.top - 10,
            box.right + _clusterPad - 2,
            box.bottom + 10,
          );
    var clear = true;
    for (var v = 0; v < count && clear; v++) {
      if (!paths[v].contains(c) && vertexRect(v).inflate(1).overlaps(box)) {
        clear = false;
      }
    }
    boxes[c] = clear ? box : null;
  }
  for (var a = 0; a < boxes.length; a++) {
    for (var b = a + 1; b < boxes.length; b++) {
      final first = boxes[a];
      final second = boxes[b];
      if (first == null || second == null) continue;
      final nested =
          _path(a, graph.clusters).contains(b) ||
          _path(b, graph.clusters).contains(a);
      if (!nested && first.overlaps(second)) boxes[b] = null;
    }
  }

  // Into the requested direction, then onto a canvas with a small margin.
  Offset turn(Offset point) => switch (direction) {
    LayeredDirection.down => point,
    LayeredDirection.up => Offset(point.dx, -point.dy),
    LayeredDirection.right => Offset(point.dy, point.dx),
    LayeredDirection.left => Offset(-point.dy, point.dx),
  };
  Rect turnRect(Rect rect) =>
      Rect.fromPoints(turn(rect.topLeft), turn(rect.bottomRight));
  final realRects = [
    for (var v = 0; v < count; v++)
      Rect.fromCenter(
        center: turn(Offset(vertices[v].x, vertices[v].y)),
        width: graph.sizes[v].width,
        height: graph.sizes[v].height,
      ),
  ];
  final labelRects = [
    for (final v in labelVertices)
      if (v != null) turnRect(vertexRect(v)),
  ];
  final realBoxes = [
    for (final box in boxes) box == null ? null : turnRect(box),
  ];
  final routesRaw = <List<Offset>>[];
  for (final (e, chain) in chains.indexed) {
    final points = [
      for (final v in chain) turn(Offset(vertices[v].x, vertices[v].y)),
    ];
    routesRaw.add(reversed[e] ? points.reversed.toList() : points);
  }
  var bounds = realRects.isEmpty ? Rect.zero : realRects.first;
  for (final rect in [...realRects, ...labelRects, ...realBoxes.nonNulls]) {
    bounds = bounds.expandToInclude(rect);
  }
  for (final route in routesRaw) {
    for (final point in route) {
      bounds = bounds.expandToInclude(
        Rect.fromCircle(center: point, radius: 1),
      );
    }
  }
  final shift = Offset(_margin - bounds.left, _margin - bounds.top);
  return LayeredLayout(
    size: Size(bounds.width + 2 * _margin, bounds.height + 2 * _margin),
    direction: direction,
    centers: [for (final rect in realRects) rect.center + shift],
    routes: [
      for (final route in routesRaw) [for (final point in route) point + shift],
    ],
    labels: [
      for (final v in labelVertices)
        v == null ? null : turn(Offset(vertices[v].x, vertices[v].y)) + shift,
    ],
    clusters: [for (final box in realBoxes) box?.shift(shift)],
    ranks: rank,
    reversed: reversed,
  );
}

List<int> _path(int? cluster, List<LayeredCluster> clusters) {
  final path = <int>[];
  for (int? c = cluster; c != null; c = clusters[c].parent) {
    path.insert(0, c);
  }
  return path;
}

int? _commonCluster(int? a, int? b, List<LayeredCluster> clusters) {
  final ancestors = _path(a, clusters).toSet();
  for (int? c = b; c != null; c = clusters[c].parent) {
    if (ancestors.contains(c)) return c;
  }
  return null;
}

/// Pairs out of order in [sequence], whose values lie below [size].
int _inversions(List<int> sequence, int size) {
  final tree = List<int>.filled(size + 1, 0);
  var inversions = 0;
  for (final (seen, value) in sequence.indexed) {
    var smallerOrEqual = 0;
    for (var i = value + 1; i > 0; i -= i & -i) {
      smallerOrEqual += tree[i];
    }
    inversions += seen - smallerOrEqual;
    for (var i = value + 1; i <= size; i += i & -i) {
      tree[i]++;
    }
  }
  return inversions;
}

double _weightedMedian(List<double> values, List<double> weights) {
  final order = List.generate(values.length, (i) => i)
    ..sort((a, b) => values[a].compareTo(values[b]));
  final half = weights.reduce((a, b) => a + b) / 2;
  var cumulative = 0.0;
  for (var k = 0; k < order.length; k++) {
    cumulative += weights[order[k]];
    if ((cumulative - half).abs() < 1e-9 && k + 1 < order.length) {
      return (values[order[k]] + values[order[k + 1]]) / 2;
    }
    if (cumulative > half) return values[order[k]];
  }
  return values[order.last];
}

/// Least-squares positions closest to [targets] that keep their order and at
/// least [gaps] between neighbours (pool-adjacent-violators).
List<double> _isotonic(
  List<double> targets,
  List<double> weights,
  List<double> gaps,
) {
  final offsets = List<double>.filled(targets.length, 0);
  for (var i = 1; i < targets.length; i++) {
    offsets[i] = offsets[i - 1] + gaps[i - 1];
  }
  final values = <double>[];
  final blockWeights = <double>[];
  final sizes = <int>[];
  for (var i = 0; i < targets.length; i++) {
    values.add(targets[i] - offsets[i]);
    blockWeights.add(math.max(weights[i], .01));
    sizes.add(1);
    while (values.length > 1 && values[values.length - 2] > values.last) {
      final weight = blockWeights.removeLast();
      final value = values.removeLast();
      final size = sizes.removeLast();
      final total = blockWeights.last + weight;
      values.last = (values.last * blockWeights.last + value * weight) / total;
      blockWeights.last = total;
      sizes.last += size;
    }
  }
  final result = <double>[];
  for (final (block, value) in values.indexed) {
    for (var k = 0; k < sizes[block]; k++) {
      result.add(value + offsets[result.length]);
    }
  }
  return result;
}
