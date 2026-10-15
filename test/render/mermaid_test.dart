import 'package:flutter_test/flutter_test.dart';
import 'package:tako/ui/render/visuals/chart_spec.dart';
import 'package:tako/ui/render/visuals/flowchart.dart';
import 'package:tako/ui/render/visuals/layered_layout.dart';
import 'package:tako/ui/render/visuals/mermaid.dart';
import 'package:tako/ui/render/visuals/mindmap.dart';
import 'package:tako/ui/render/visuals/sequence.dart';

FlowchartDiagram flow(String source) =>
    parseMermaid(source)! as FlowchartDiagram;

void main() {
  group('detection', () {
    test('skips front matter, directives and comments', () {
      final diagram = parseMermaid('''
---
title: "Sign-in"
config:
  theme: dark
---
%%{init: {"flowchart": {"curve": "basis"}}}%%
%% a comment
graph LR;
  A --> B
''')!;
      expect(diagram, isA<FlowchartDiagram>());
      expect(diagram.title, 'Sign-in');
      expect((diagram as FlowchartDiagram).direction, LayeredDirection.right);
    });

    test('unsupported diagram types stay code', () {
      for (final source in [
        'gantt\n  title A',
        'classDiagram\n  A <|-- B',
        'erDiagram\n  A ||--o{ B : has',
        '',
      ]) {
        expect(parseMermaid(source), isNull, reason: source);
      }
    });
  });

  group('flowchart', () {
    test('reads shapes, labels and entities', () {
      final diagram = flow('''
flowchart TD
  a[Rect] --> b(Round) --> c([Stadium]) --> d[[Sub]] --> e[(Database)]
  e --> f((Circle)) --> g{Decision} --> h{{Hex}} --> i[/Lean/] --> j[\\Back\\]
  j --> k[/Trap\\] --> l>Flag] --> m(((Stop)))
  n["Quoted (with) [brackets]"] --> o["Line<br/>break #quot;q#quot;"]
  p@{ shape: cyl, label: "Store" }
''');
      final shapes = {for (final node in diagram.nodes) node.id: node.shape};
      expect(shapes, {
        'a': NodeShape.rect,
        'b': NodeShape.round,
        'c': NodeShape.stadium,
        'd': NodeShape.subroutine,
        'e': NodeShape.cylinder,
        'f': NodeShape.circle,
        'g': NodeShape.rhombus,
        'h': NodeShape.hexagon,
        'i': NodeShape.parallelogram,
        'j': NodeShape.parallelogramAlt,
        'k': NodeShape.trapezoid,
        'l': NodeShape.asymmetric,
        'm': NodeShape.doubleCircle,
        'n': NodeShape.rect,
        'o': NodeShape.rect,
        'p': NodeShape.cylinder,
      });
      final labels = {for (final node in diagram.nodes) node.id: node.label};
      expect(labels['n'], 'Quoted (with) [brackets]');
      expect(labels['o'], 'Line\nbreak "q"');
      expect(labels['p'], 'Store');
    });

    test('reads link styles, heads, labels, chains and groups', () {
      final diagram = flow('''
graph TD
  A -->|yes| B
  A -- no --> C
  B -.-> D
  C ==> D
  D --- E
  E <--> F
  F --o G
  G --x H
  H ~~~ I
  I ---> J
  J -. maybe .-> K
  K & L --> M & N
''');
      final edges = diagram.edges;
      String id(int index) => diagram.nodes[index].id;
      expect(edges.first.label, 'yes');
      expect(edges[1].label, 'no');
      expect(edges[1].end, ArrowHead.arrow);
      expect(edges[2].style, LineStyle.dotted);
      expect(edges[3].style, LineStyle.thick);
      expect(edges[4].end, ArrowHead.none);
      expect(
        (edges[5].start, edges[5].end),
        (ArrowHead.arrow, ArrowHead.arrow),
      );
      expect(edges[6].end, ArrowHead.circle);
      expect(edges[7].end, ArrowHead.cross);
      expect(edges[8].style, LineStyle.invisible);
      expect(edges[9].length, 2);
      expect(edges[10].label, 'maybe');
      expect(edges[10].style, LineStyle.dotted);
      expect(
        [for (final edge in edges.skip(11)) '${id(edge.from)}${id(edge.to)}'],
        ['KM', 'KN', 'LM', 'LN'],
      );
    });

    test('an open link continues a chain instead of eating a node', () {
      final diagram = flow('graph LR\n  A --- B --> C');
      expect(diagram.edges, hasLength(2));
      expect(diagram.edges.first.label, isNull);
      expect(diagram.nodes.map((node) => node.id), ['A', 'B', 'C']);
    });

    test('subgraphs nest, and links to them reach their first node', () {
      final diagram = flow('''
flowchart LR
  Client --> API
  subgraph backend [Back end]
    API --> Worker
    subgraph data
      DB[(Postgres)]
    end
    Worker --> DB
  end
  Client --> data
''');
      final byId = {for (final node in diagram.nodes) node.id: node};
      expect(diagram.clusters.map((c) => c.title), ['Back end', 'data']);
      expect(diagram.clusters[1].parent, 0);
      expect(byId['API']!.cluster, 0);
      expect(byId['DB']!.cluster, 1);
      expect(byId['Client']!.cluster, isNull);
      expect(byId.containsKey('data'), isFalse);
      final last = diagram.edges.last;
      expect(diagram.nodes[last.to].id, 'DB');
    });

    test('styling and click handlers are ignored', () {
      final diagram = flow('''
flowchart TD
  A:::warm --> B
  classDef warm fill:#f96
  class B warm
  style A fill:#bbf,stroke:#333
  linkStyle 0 stroke:red
  click A "https://example.com" "Open"
''');
      expect(diagram.nodes.map((n) => n.id), ['A', 'B']);
      expect(diagram.edges, hasLength(1));
    });

    test('oversized charts are refused', () {
      final lines = [for (var i = 0; i < 130; i++) '  N$i --> N${i + 1}'];
      expect(
        () => parseMermaid('graph TD\n${lines.join('\n')}'),
        throwsFormatException,
      );
    });
  });

  group('sequence diagram', () {
    test('reads participants, messages, notes and blocks', () {
      final diagram =
          parseMermaid('''
sequenceDiagram
  title Checkout
  autonumber
  actor U as User
  participant A as App
  U->>+A: Pay
  A-->>-U: Receipt
  A-)Bank: Charge
  Bank--xA: Declined
  A->>A: Retry
  Note right of A: Logs the attempt
  Note over U,A: Both wait
  loop Every minute
    A->>Bank: Poll
  end
  alt Paid
    Bank->>A: OK
  else Failed
    Bank->>A: Error
  end
  activate A
''')!
              as SequenceDiagram;
      expect(diagram.title, 'Checkout');
      expect(diagram.autonumber, isTrue);
      expect(diagram.participants.map((p) => p.label), ['User', 'App', 'Bank']);
      expect(diagram.participants.first.actor, isTrue);
      final messages = diagram.events.whereType<SequenceMessage>().toList();
      expect(messages.first.text, 'Pay');
      expect(messages[1].dashed, isTrue);
      expect(messages[2].head, MessageHead.open);
      expect(messages[3].head, MessageHead.cross);
      expect(messages[4].from, messages[4].to);
      final notes = diagram.events.whereType<SequenceNote>().toList();
      expect(notes.first.placement, NotePlacement.right);
      expect((notes.last.first, notes.last.last), (0, 1));
      expect(
        diagram.events.whereType<SequenceBlockStart>().map((b) => b.kind),
        ['loop', 'alt'],
      );
      expect(
        diagram.events.whereType<SequenceBlockDivider>().single.label,
        'Failed',
      );
      expect(diagram.events.whereType<SequenceBlockEnd>(), hasLength(2));
    });

    test('unbalanced blocks are refused', () {
      expect(
        () => parseMermaid('sequenceDiagram\n  loop x\n  A->>B: hi'),
        throwsFormatException,
      );
      expect(
        () => parseMermaid('sequenceDiagram\n  A->>B: hi\n  end'),
        throwsFormatException,
      );
    });
  });

  group('mind map', () {
    test('builds the tree from indentation and drops decorations', () {
      final diagram =
          parseMermaid('''
mindmap
  root((Plan))
    Research
      ::icon(fa fa-book)
      Papers
      id1[Interviews]
    Build:::urgent
      Prototype
''')!
              as MindmapDiagram;
      final root = diagram.root;
      expect(root.label, 'Plan');
      expect(root.children.map((c) => c.label), ['Research', 'Build']);
      expect(root.children.first.children.map((c) => c.label), [
        'Papers',
        'Interviews',
      ]);
      expect(root.children.last.children.single.label, 'Prototype');
    });

    test('a second root is refused', () {
      expect(
        () => parseMermaid('mindmap\n  A\n    B\n  C'),
        throwsFormatException,
      );
    });
  });

  group('charts in Mermaid', () {
    test('pie becomes a chart spec', () {
      final chart =
          parseMermaid('''
pie showData title Pets
  "Dogs" : 386
  "Cats" : 85.5
''')!
              as MermaidChart;
      expect(chart.spec.type, ChartType.pie);
      expect(chart.spec.title, 'Pets');
      expect(chart.spec.labels, ['Dogs', 'Cats']);
      expect(chart.spec.series.single.data, [386, 85.5]);
    });

    test('xychart with one kind of mark becomes a chart spec', () {
      final chart =
          parseMermaid('''
xychart-beta horizontal
  title "Sales"
  x-axis [jan, feb, mar]
  y-axis "Revenue" 0 --> 100
  bar [10, 20, 30]
''')!
              as MermaidChart;
      expect(chart.spec.type, ChartType.bar);
      expect(chart.spec.horizontal, isTrue);
      expect(chart.spec.title, 'Sales');
      expect(chart.spec.labels, ['jan', 'feb', 'mar']);
      expect(parseMermaid('xychart-beta\n  bar [1, 2]\n  line [2, 3]'), isNull);
    });
  });

  test('labels resolve quotes, markdown strings, breaks and entities', () {
    expect(cleanMermaidText('"a <b>bold</b> #35; tag"'), 'a bold # tag');
    expect(cleanMermaidText('`**Markdown** text`'), 'Markdown text');
    expect(cleanMermaidText('one<br>two<br/>three'), 'one\ntwo\nthree');
    expect(cleanMermaidText('fa:fa-car Drive'), 'Drive');
    expect(cleanMermaidText('a &amp; b &lt;c&gt;'), 'a & b <c>');
  });
}
