import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tako/ui/render/code_block.dart';
import 'package:tako/ui/render/visuals/diagram_painter.dart';
import 'package:tako/ui/render/visuals/gantt.dart';
import 'package:tako/ui/render/visuals/mermaid.dart';
import 'package:tako/ui/render/visuals/timeline.dart';
import 'package:tako/ui/render/visuals/visual_block.dart';
import 'package:tako/ui/render/visuals/visual_image.dart';
import 'package:tako/ui/render/visuals/visual_labels.dart';

import 'fake_measurer.dart';

GanttDiagram gantt(String body) =>
    parseMermaid('gantt\n$body')! as GanttDiagram;

const plan = '''
gantt
  title Website relaunch
  dateFormat YYYY-MM-DD
  axisFormat %b %d
  excludes weekends
  todayMarker off
  Kick-off      :milestone, k1, 2026-11-02, 0d
  section Research
  Interviews    :done, r1, 2026-11-02, 5d
  Review        :done, r2, after r1, 3d
  section Design
  Wireframes    :active, d1, after r2, 1w
  Sign-off      :milestone, after d1, 0d
  section Build
  Front end     :crit, b1, after d1 r2, 12d
  Content       :b2, after b1, 2026-12-20
''';

const history = '''
timeline
  title Social media
  section Early days
    2002 : LinkedIn
    2004 : Facebook : Google
  section Growth
    2006 : Twitter
         : Spotify
    09:30 : Standup at 10:00
''';

Widget host(
  Widget child, {
  double width = 360,
  double textScale = 1,
  bool dark = false,
}) => MaterialApp(
  theme: dark ? ThemeData.dark() : null,
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(width: width, child: child),
      ),
    ),
  ),
);

Widget block(String source, {ValueChanged<VisualImage>? onShareImage}) =>
    VisualBlock(
      language: 'mermaid',
      source: source,
      labels: const VisualLabels(),
      copyLabel: 'Copy code',
      onShareImage: onShareImage,
    );

TimelineView view(TimelineSpec spec) => TimelineView(
  title: spec.title == null ? null : TextSpan(text: spec.title),
  items: [
    for (final item in spec.items)
      TimelineContent(
        time: item.time,
        icon: item.icon,
        title: item.title == null
            ? null
            : TextSpan(
                children: [
                  TextSpan(text: item.title),
                  const TextSpan(
                    text: ' ✓',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
        text: item.text == null ? null : TextSpan(text: item.text),
        status: item.status,
        section: item.section,
      ),
  ],
);

void main() {
  group('timeline JSON', () {
    test('reads an array of events with aliases', () {
      final spec = TimelineSpec.parse('''
[
  {"time": "09:00", "title": "Breakfast", "text": "At the hotel", "icon": "coffee", "status": "done"},
  {"date": "2026-11-03", "name": "Museum", "description": "Tickets online", "state": "In progress"},
  {"when": 2027, "label": "Launch", "status": "todo"},
  {"start": "13:00", "end": "14:30", "heading": "Lunch", "done": true},
  {"title": "Rest", "active": true},
  "Fly home"
]''');
      expect(spec.title, isNull);
      expect(spec.items.map((i) => i.time), [
        '09:00',
        '2026-11-03',
        '2027',
        '13:00–14:30',
        null,
        null,
      ]);
      expect(spec.items.map((i) => i.title), [
        'Breakfast',
        'Museum',
        'Launch',
        'Lunch',
        'Rest',
        'Fly home',
      ]);
      expect(spec.items[1].text, 'Tickets online');
      expect(spec.items.first.icon, 'coffee');
      expect(spec.items.map((i) => i.status), [
        TimelineStatus.done,
        TimelineStatus.current,
        TimelineStatus.upcoming,
        TimelineStatus.done,
        TimelineStatus.current,
        null,
      ]);
    });

    test('reads a titled object, nested sections and section fields', () {
      final spec = TimelineSpec.parse('''
{"title": "Kyoto", "items": [
  {"day": "Day 1", "events": [{"time": "09:00", "title": "Train"}, "Hotel"]},
  {"title": "Day 2", "items": [{"title": "Temple", "status": "unknown"}]},
  {"title": "Dinner", "section": "Extras"},
  42
]}''');
      expect(spec.title, 'Kyoto');
      expect(spec.items.map((i) => (i.section, i.title)), [
        ('Day 1', 'Train'),
        ('Day 1', 'Hotel'),
        ('Day 2', 'Temple'),
        ('Extras', 'Dinner'),
      ]);
      expect(spec.items[2].status, isNull);
      expect(
        TimelineSpec.parse('{"steps": ["Boil", "Serve"]}').items,
        hasLength(2),
      );
    });

    test('refuses what is not a timeline', () {
      for (final source in [
        '{"items": 3}',
        '[]',
        '{"title": "Empty"}',
        '[{"time": "09:00"}]',
        '[1, 2]',
        'not json',
        '[${List.filled(61, '"Step"').join(',')}]',
      ]) {
        expect(
          () => TimelineSpec.parse(source),
          throwsFormatException,
          reason: source,
        );
      }
    });
  });

  group('Mermaid timeline', () {
    test('reads periods, events, continuations and sections', () {
      final diagram = parseMermaid(history)! as TimelineDiagram;
      expect(diagram.title, 'Social media');
      expect(diagram.items.map((i) => (i.section, i.time, i.title)), [
        ('Early days', '2002', 'LinkedIn'),
        ('Early days', '2004', 'Facebook\nGoogle'),
        ('Growth', '2006', 'Twitter\nSpotify'),
        ('Growth', '09:30', 'Standup at 10:00'),
      ]);
    });

    test('a period without events is its own title', () {
      final diagram =
          parseMermaid('timeline\n  Kick-off\n  2026 : Launch')!
              as TimelineDiagram;
      expect(diagram.items.first.time, isNull);
      expect(diagram.items.first.title, 'Kick-off');
    });

    test('broken timelines are refused', () {
      for (final source in [
        'timeline\n  title Only a title',
        'timeline\n  : orphan event',
      ]) {
        expect(() => parseMermaid(source), throwsFormatException);
      }
    });
  });

  group('Mermaid gantt', () {
    test('resolves dates, after, durations, tags and sections', () {
      final diagram = parseMermaid(plan)! as GanttDiagram;
      expect(diagram.title, 'Website relaunch');
      expect(diagram.clockOnly, isFalse);
      expect(diagram.sections, ['', 'Research', 'Design', 'Build']);
      final tasks = {for (final task in diagram.tasks) task.label: task};
      expect(tasks['Kick-off']!.milestone, isTrue);
      expect(tasks['Kick-off']!.section, 0);
      expect(tasks['Interviews']!.done, isTrue);
      expect(tasks['Interviews']!.end, DateTime.utc(2026, 11, 7));
      expect(tasks['Review']!.start, DateTime.utc(2026, 11, 7));
      expect(tasks['Review']!.end, DateTime.utc(2026, 11, 10));
      expect(tasks['Wireframes']!.active, isTrue);
      expect(tasks['Wireframes']!.end, DateTime.utc(2026, 11, 17));
      expect(tasks['Sign-off']!.start, DateTime.utc(2026, 11, 17));
      expect(tasks['Sign-off']!.end, tasks['Sign-off']!.start);
      expect(tasks['Front end']!.critical, isTrue);
      // `after` several ids starts at the latest of them.
      expect(tasks['Front end']!.start, DateTime.utc(2026, 11, 17));
      expect(tasks['Front end']!.section, 3);
      expect(tasks['Content']!.end, DateTime.utc(2026, 12, 20));
    });

    test('reads durations, implicit starts and forward references', () {
      final diagram = gantt('''
  A :a, 2026-01-31, 1M
  B :2w
  C :after d, 30m
  D :d, after a, 5h
  E :2026-03-10, until a
  F :b, 2026-01-01 10:00, 1.5d
''');
      final [a, b, c, d, e, f] = diagram.tasks;
      // A month from the 31st lands on the last day of February.
      expect(a.end, DateTime.utc(2026, 2, 28));
      expect(b.start, a.end);
      expect(b.end, DateTime.utc(2026, 3, 14));
      expect(d.end, DateTime.utc(2026, 2, 28, 5));
      expect(c.start, d.end);
      expect(c.end, DateTime.utc(2026, 2, 28, 5, 30));
      // An `until` before the start shrinks to nothing.
      expect(e.end, e.start);
      expect(f.start, DateTime.utc(2026, 1, 1, 10));
      expect(f.end, DateTime.utc(2026, 1, 2, 22));
    });

    test('reads custom date formats and times of day', () {
      final clock = gantt('''
  dateFormat HH:mm
  Talk : 09:00, 45m
  Q&A : 15m
''');
      expect(clock.clockOnly, isTrue);
      expect(clock.tasks.last.end, DateTime.utc(1970, 1, 1, 10));
      final european = gantt('''
  dateFormat DD.MM.YYYY
  inclusiveEndDates
  Trip : 03.11.2026, 05.11.2026
''');
      expect(european.tasks.single.start, DateTime.utc(2026, 11, 3));
      expect(european.tasks.single.end, DateTime.utc(2026, 11, 6));
      // An unknown format still reads ISO dates.
      final unknown = gantt('''
  dateFormat Qo [week] w
  Task : 2026-11-03, 2d
''');
      expect(unknown.tasks.single.end, DateTime.utc(2026, 11, 5));
    });

    test('an unknown id follows the task above', () {
      final diagram = gantt('  A :2026-01-01, 1d\n  B :after nope, 1d');
      expect(diagram.tasks.last.start, DateTime.utc(2026, 1, 2));
    });

    test('broken charts are refused', () {
      for (final body in [
        '  title Plan',
        '  A : 3d',
        '  A :2026-01-01, soon',
        '  A :someday, 3d, 4d',
        '  A :a, after b, 1d\n  B :b, after a, 1d',
        '  A :1900-01-01, 2100-01-01\n  B :2300-01-01, 1d',
        [for (var i = 0; i < 101; i++) '  T$i :2026-01-01, 1d'].join('\n'),
      ]) {
        expect(() => gantt(body), throwsFormatException, reason: body);
      }
    });

    test('lays out one row per task with ticks that fit', () {
      final diagram = parseMermaid(plan)! as GanttDiagram;
      for (final width in [280.0, 640.0]) {
        final layout = layoutGantt(diagram, FakeMeasurer(), fitWidth: width);
        expect(layout.size.width, width);
        expect(layout.tasks, hasLength(diagram.tasks.length));
        expect(layout.sections.map((s) => s.title), diagram.sections);
        for (final task in layout.tasks) {
          expect(task.bar.left, greaterThanOrEqualTo(0));
          expect(task.bar.right, lessThanOrEqualTo(width));
          expect(task.labelOffset.dx, greaterThanOrEqualTo(0));
        }
        final bars = layout.tasks.map((t) => t.bar.top).toList();
        expect(bars, orderedEquals([...bars]..sort()));
        final labels = [
          for (final tick in layout.ticks)
            if (tick.labelLeft != null) tick.label,
        ];
        expect(labels, contains('Nov 16'));
        expect(labels.length, greaterThanOrEqualTo(3));
      }
      // Wide charts keep names in a column left of the bars, and have room
      // for weekly ticks.
      final wide = layoutGantt(diagram, FakeMeasurer(), fitWidth: 640);
      expect(wide.tasks.every((t) => t.bar.left > wide.labelWidth), isTrue);
      expect(wide.ticks.map((t) => t.label), contains('Nov 9'));
    });

    test('screen readers hear tasks, dates and statuses', () {
      final summary = diagramSummary(parseMermaid(plan)!);
      expect(summary, contains('Kick-off, Nov 2, 2026, Milestone'));
      expect(summary, contains('Research: Interviews, Nov 2, 2026 – '));
      expect(summary, contains('Done'));
      expect(summary, contains('In progress'));
      expect(summary, contains('Critical'));
    });
  });

  testWidgets('a timeline shows times, statuses, sections and spans', (
    tester,
  ) async {
    final spec = TimelineSpec.parse('''
{"title": "Trip", "items": [
  {"section": "Day 1", "items": [
    {"time": "09:00", "title": "Train", "icon": "train", "status": "done"},
    {"time": "11:00", "title": "Lunch", "text": "Market", "status": "current"},
    {"time": "15:00", "title": "Temple", "icon": "🏯", "status": "upcoming"}
  ]},
  {"section": "Day 2", "items": [{"title": "Home"}]}
]}''');
    await tester.pumpWidget(host(view(spec)));
    expect(find.text('Trip'), findsOneWidget);
    expect(find.text('Day 1'), findsOneWidget);
    expect(find.text('Day 2'), findsOneWidget);
    expect(find.text('09:00'), findsOneWidget);
    expect(find.text('Train ✓', findRichText: true), findsOneWidget);
    expect(find.text('Market', findRichText: true), findsOneWidget);
    expect(find.byIcon(Icons.train_outlined), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('In progress')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long times move above their titles', (tester) async {
    final spec = TimelineSpec.parse(
      '[{"time": "Saturday 9 November, morning", "title": "Hike"},'
      '{"time": "09:00", "title": "Coffee"}]',
    );
    await tester.pumpWidget(host(view(spec)));
    final time = tester.getRect(find.text('Saturday 9 November, morning'));
    final title = tester.getRect(find.text('Hike ✓', findRichText: true));
    expect(time.bottom, lessThanOrEqualTo(title.top + 1));
    expect(time.left, closeTo(title.left, 1));
  });

  testWidgets('timelines fit narrow, large-text and dark layouts', (
    tester,
  ) async {
    final spec = TimelineSpec.parse('''
[
  {"time": "09:00", "title": "A rather long title that has to wrap", "text": "And a description that wraps as well", "icon": "flight", "status": "done"},
  {"time": "2026-11-03 14:00", "title": "Meeting", "status": "current"},
  {"title": "No time at all", "icon": "unknown_icon"}
]''');
    for (final (width, scale, dark) in [
      (240.0, 2.0, false),
      (320.0, 1.4, true),
      (700.0, 1.0, false),
    ]) {
      await tester.pumpWidget(
        host(view(spec), width: width, textScale: scale, dark: dark),
      );
      expect(tester.takeException(), isNull, reason: '$width $scale');
      await tester.pumpWidget(
        host(
          Column(children: [block(history), block(plan)]),
          width: width,
          textScale: scale,
          dark: dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TimelineView), findsOneWidget);
      expect(find.byType(DiagramView), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$width $scale');
    }
  });

  testWidgets('Mermaid timelines and Gantt charts draw in frames', (
    tester,
  ) async {
    final shared = <VisualImage>[];
    await tester.pumpWidget(
      host(
        Column(
          children: [
            block(history, onShareImage: shared.add),
            block(plan, onShareImage: shared.add),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Social media'), findsOneWidget);
    expect(find.text('Early days'), findsOneWidget);
    expect(find.text('Facebook\nGoogle', findRichText: true), findsOneWidget);
    expect(find.text('Website relaunch'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Website relaunch.*Wireframes')),
      findsOneWidget,
    );
    // Only the Gantt chart, a drawing, opens full screen.
    expect(find.byTooltip('Full screen'), findsOneWidget);
    final shares = find.byTooltip('Share image');
    expect(shares, findsNWidgets(2));
    await tester.tap(shares.first);
    await tester.tap(shares.last);
    expect(shared.map((image) => image.fileName), [
      matches(RegExp(r'^tako-timeline-\d{8}-\d{6}\.png$')),
      matches(RegExp(r'^tako-diagram-\d{8}-\d{6}\.png$')),
    ]);
    for (final image in shared) {
      final bytes = (await tester.runAsync(image.toPng))!;
      final decoded = img.decodePng(Uint8List.fromList(bytes))!;
      expect(decoded.width, inInclusiveRange(100, 4096));
      expect(decoded.getPixel(0, 0).a, 255);
    }
    await tester.tap(find.byTooltip('Show code').first);
    await tester.pumpAndSettle();
    expect(find.byType(TimelineView), findsNothing);
    expect(find.byType(CodeBlock), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('broken Gantt charts show their source', (tester) async {
    await tester.pumpWidget(host(block('gantt\n  A :2026-01-01, soon')));
    expect(find.byType(CodeBlock), findsOneWidget);
    expect(
      find.text("Couldn't draw this. Showing the source."),
      findsOneWidget,
    );
  });

  test('a streaming timeline fence holds its place', () {
    expect(pendingVisualLanguage('```timeline\n[{"time":'), 'timeline');
    expect(pendingVisualLanguage('> ~~~Timeline\n'), 'timeline');
    expect(pendingVisualLanguage('```timelines\n'), isNull);
  });
}
