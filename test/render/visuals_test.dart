import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tako/ui/render/code_block.dart';
import 'package:tako/ui/render/message_markdown.dart';
import 'package:tako/ui/render/visuals/cards.dart';
import 'package:tako/ui/render/visuals/chart_painter.dart';
import 'package:tako/ui/render/visuals/chart_view.dart';
import 'package:tako/ui/render/visuals/diagram_painter.dart';
import 'package:tako/ui/render/visuals/visual_block.dart';

const chart =
    '```chart\n{"type":"bar","title":"Requests","labels":["Jan","Feb","Mar"],'
    '"series":[{"name":"API","data":[120,210,170]}]}\n```';
const flowchart = '```mermaid\nflowchart TD\n  A[Start] --> B{Ready?}\n```';

Widget app(
  String data, {
  bool streaming = false,
  bool visuals = true,
  double width = 360,
  double textScale = 1,
  bool reduceMotion = false,
  ThemeData? theme,
  ValueChanged<VisualImage>? onShareImage,
}) => MaterialApp(
  theme: theme,
  home: MediaQuery(
    data: MediaQueryData(
      textScaler: TextScaler.linear(textScale),
      disableAnimations: reduceMotion,
    ),
    child: Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(
          width: width,
          child: MessageMarkdown(
            data: data,
            isStreaming: streaming,
            visuals: visuals,
            copyLabel: 'Copy code',
            imageLabel: 'Image',
            fileLabel: 'File',
            onCopy: (_) {},
            onShareImage: onShareImage,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('a chart draws with a summary and opens as a table', (
    tester,
  ) async {
    await tester.pumpWidget(app(chart));
    await tester.pumpAndSettle();
    expect(find.byType(ChartView), findsOneWidget);
    expect(find.text('Requests'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Requests.*Jan: 120.*Mar: 170')),
      findsOneWidget,
    );
    // No share without a host callback.
    expect(find.byTooltip('Share image'), findsNothing);
    await tester.tap(find.byTooltip('Show as table'));
    await tester.pumpAndSettle();
    expect(find.byType(ChartView), findsNothing);
    expect(find.byType(Table), findsOneWidget);
    expect(find.text('210'), findsOneWidget);
    await tester.tap(find.byTooltip('Show chart'));
    await tester.pumpAndSettle();
    expect(find.byType(ChartView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a bar shows its value', (tester) async {
    await tester.pumpWidget(app(chart));
    await tester.pumpAndSettle();
    final paint = find.descendant(
      of: find.byType(ChartView),
      matching: find.byType(CustomPaint),
    );
    final box = tester.getRect(paint.first);
    await tester.tapAt(box.center);
    await tester.pumpAndSettle();
    final painter =
        tester.widget<CustomPaint>(paint.first).painter! as ChartPainter;
    expect(painter.selected, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unreadable sources fall back to code with a note', (
    tester,
  ) async {
    for (final source in [
      '```chart\n{"type":"bar","labels":["a"]}\n```',
      '```mermaid\ngantt\n  title Plan\n```',
      '```mermaid\nsequenceDiagram\n  loop forever\n```',
      '```cards\n{"items": 3}\n```',
    ]) {
      await tester.pumpWidget(app(source));
      await tester.pumpAndSettle();
      expect(find.byType(CodeBlock), findsOneWidget, reason: source);
      expect(
        find.text("Couldn't draw this. Showing the source."),
        findsOneWidget,
        reason: source,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('user messages keep visual blocks as code', (tester) async {
    await tester.pumpWidget(app(chart, visuals: false));
    expect(find.byType(VisualBlock), findsNothing);
    expect(find.byType(CodeBlock), findsOneWidget);
    expect(find.text("Couldn't draw this. Showing the source."), findsNothing);
  });

  testWidgets('a visual still streaming in holds its place', (tester) async {
    for (final pending in [
      'Here:\n\n```mermaid\nflowchart TD\n  A --> B',
      'Here:\n\n~~~chart\n{"data": [1',
      '> Quoted\n> ```cards\n> [',
      '- Item\n  ```chart\n  {',
    ]) {
      await tester.pumpWidget(app(pending, streaming: true));
      await tester.pump();
      expect(find.byType(VisualPlaceholder), findsOneWidget, reason: pending);
      expect(find.text('Drawing…'), findsOneWidget, reason: pending);
    }
    await tester.pumpWidget(
      app('Here:\n\n```dart\nfinal x = 1;', streaming: true),
    );
    expect(find.byType(VisualPlaceholder), findsNothing);
    await tester.pumpWidget(app('Here:\n\n$flowchart', streaming: true));
    await tester.pump();
    expect(find.byType(VisualPlaceholder), findsNothing);
    expect(find.byType(DiagramView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a visual keeps its state while the reply streams on', (
    tester,
  ) async {
    await tester.pumpWidget(app('$chart\n\nMore', streaming: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show as table'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app('$chart\n\nMore text', streaming: true));
    await tester.pumpAndSettle();
    expect(find.byType(Table), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('diagrams switch to code and open full screen', (tester) async {
    await tester.pumpWidget(app(flowchart));
    await tester.pumpAndSettle();
    expect(find.byType(DiagramView), findsOneWidget);
    expect(find.text('Flowchart'), findsOneWidget);
    await tester.tap(find.byTooltip('Full screen'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byType(BackButton).hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    await tester.tap(find.byTooltip('Show code'));
    await tester.pumpAndSettle();
    expect(find.byType(DiagramView), findsNothing);
    expect(find.byType(CodeBlock), findsOneWidget);
    expect(find.textContaining('flowchart TD', findRichText: true), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cards render lists, grids and stat tiles', (tester) async {
    await tester.pumpWidget(
      app(
        '```cards\n[{"icon":"bar_chart","title":"Charts","subtitle":"For data",'
        r'"text":"Bars **and** lines <image src=\"x.png\"/>"},'
        '{"icon":"🧭","title":"Diagrams"}]\n```',
      ),
    );
    expect(find.byType(CardsView), findsOneWidget);
    expect(find.text('Charts'), findsOneWidget);
    expect(find.text('For data'), findsOneWidget);
    expect(find.byIcon(Icons.bar_chart), findsOneWidget);
    expect(
      find.textContaining('<image src="x.png"/>', findRichText: true),
      findsOneWidget,
    );
    expect(find.byType(ActionChip), findsNothing);
    await tester.pumpWidget(
      app(
        '```cards\n[{"title":"Requests","value":"320","delta":"+88%"},'
        '{"title":"Errors","value":"0.6%","delta":"-0.2%"}]\n```',
      ),
    );
    expect(find.text('320'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('callouts show an icon, a title and their content', (
    tester,
  ) async {
    await tester.pumpWidget(
      app('> [!TIP]\n> Tap a bar.\n\n> [!CAUTION] Check sources\n> - one'),
    );
    expect(find.text('Tip'), findsOneWidget);
    expect(find.byIcon(Icons.lightbulb_outline), findsOneWidget);
    expect(find.text('Tap a bar.', findRichText: true), findsOneWidget);
    expect(find.text('Check sources', findRichText: true), findsOneWidget);
    expect(find.byIcon(Icons.report_outlined), findsOneWidget);
    expect(find.text('one', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow, large-text and dark layouts do not overflow', (
    tester,
  ) async {
    const everything =
        '$chart\n\n```chart\n{"type":"donut","labels":["Search","Social",'
        '"Direct"],"data":[50,30,20]}\n```\n\n```chart\n{"type":"line",'
        '"labels":["W1","W2","W3","W4","W5","W6","W7","W8","W9","W10"],'
        '"series":[{"name":"A","data":[1,2,3,4,5,6,7,8,9,10]},'
        '{"name":"B","data":[2,3,4,5,6,7,8,9,10,11]}]}\n```\n\n$flowchart\n\n'
        '```mermaid\nsequenceDiagram\n  A->>B: A rather long message\n'
        '  B-->>A: Reply\n```\n\n```mermaid\nmindmap\n  Root\n    A\n      B\n```';
    for (final (width, scale, dark) in [
      (240.0, 2.0, false),
      (320.0, 1.3, true),
      (700.0, 1.0, false),
    ]) {
      await tester.pumpWidget(
        app(
          everything,
          width: width,
          textScale: scale,
          theme: dark ? ThemeData.dark() : null,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(VisualBlock), findsNWidgets(6));
      expect(tester.takeException(), isNull, reason: '$width $scale');
    }
  });

  testWidgets('charts appearing while streaming grow in unless motion is off', (
    tester,
  ) async {
    await tester.pumpWidget(app(chart, streaming: true));
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    await tester.pumpWidget(app('', streaming: true));
    await tester.pumpWidget(app(chart, streaming: true, reduceMotion: true));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared images are opaque PNGs at a bounded size', (
    tester,
  ) async {
    final shared = <VisualImage>[];
    await tester.pumpWidget(
      app('$chart\n\n$flowchart', onShareImage: shared.add),
    );
    await tester.pumpAndSettle();
    final buttons = find.byTooltip('Share image');
    expect(buttons, findsNWidgets(2));
    await tester.tap(buttons.first);
    await tester.tap(buttons.last);
    expect(shared.map((image) => image.fileName), [
      matches(RegExp(r'^tako-chart-\d{8}-\d{6}\.png$')),
      matches(RegExp(r'^tako-diagram-\d{8}-\d{6}\.png$')),
    ]);
    for (final image in shared) {
      final bytes = (await tester.runAsync(image.toPng))!;
      final decoded = img.decodePng(Uint8List.fromList(bytes))!;
      expect(decoded.width, inInclusiveRange(100, 4096));
      expect(decoded.height, inInclusiveRange(100, 4096));
      expect(decoded.getPixel(0, 0).a, 255);
    }
    expect(tester.takeException(), isNull);
  });
}
