import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/ui/render/message_markdown.dart';

Widget app(
  String data, {
  bool streaming = false,
  ValueChanged<String>? onCopy,
  ValueChanged<Uri>? onLink,
  ValueChanged<String>? onFile,
  ValueChanged<String>? onImage,
  Map<String, CustomTagBuilder> builders = const {},
}) => MaterialApp(
  home: Scaffold(
    body: SelectionArea(
      child: SingleChildScrollView(
        child: SizedBox(
          width: 340,
          child: MessageMarkdown(
            data: data,
            isStreaming: streaming,
            copyLabel: 'Copy code',
            imageLabel: 'Image',
            fileLabel: 'File',
            onCopy: onCopy,
            onLink: onLink,
            onFile: onFile,
            onImage: onImage,
            tagBuilders: builders,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'cached content uses current callbacks and disables removed actions',
    (tester) async {
      const data =
          '```dart\nhello\n```\n\n<file path="note.txt"/>\n\n[Link](https://example.com)';
      var oldCalls = 0;
      var newCalls = 0;
      await tester.pumpWidget(
        app(
          data,
          onCopy: (_) => oldCalls++,
          onFile: (_) => oldCalls++,
          onLink: (_) => oldCalls++,
        ),
      );
      await tester.pumpWidget(
        app(
          data,
          onCopy: (_) => newCalls++,
          onFile: (_) => newCalls++,
          onLink: (_) => newCalls++,
        ),
      );
      await tester.tap(find.byTooltip('Copy code'));
      await tester.tap(find.text('File · note.txt'));
      await tester.tap(find.text('Link', findRichText: true));
      expect(oldCalls, 0);
      expect(newCalls, 3);
      await tester.pumpWidget(app(data));
      await tester.tap(find.byTooltip('Copy code'));
      await tester.tap(find.text('Link', findRichText: true));
      expect(newCalls, 3);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('renders table, nested lists, math and highlighted copyable code', (
    tester,
  ) async {
    String? copied;
    await tester.pumpWidget(
      app(
        '| A | B |\n|---|---|\n| 1 | 2 |\n\n- one\n  - two\n\n\$x^2\$\n\n```dart\nfinal x = 2;\n```',
        onCopy: (text) => copied = text,
      ),
    );
    expect(find.byType(Table), findsOneWidget);
    expect(find.byType(Math), findsOneWidget);
    expect(find.text('one', findRichText: true), findsOneWidget);
    expect(find.text('two', findRichText: true), findsOneWidget);
    await tester.tap(find.byTooltip('Copy code'));
    expect(copied, 'final x = 2;\n');
    expect(tester.takeException(), isNull);
  });

  testWidgets('incomplete syntax never produces a partial custom widget', (
    tester,
  ) async {
    await tester.pumpWidget(
      app('Text <image src="https://example.com/image', streaming: true),
    );
    expect(find.byType(ActionChip), findsNothing);
    expect(find.text('Text', findRichText: true), findsOneWidget);
    await tester.pumpWidget(
      app('Text <image src="https://example.com/image"/>', streaming: true),
    );
    expect(find.byType(ActionChip), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    await tester.pumpWidget(app(r'Text $x', streaming: true));
    expect(find.byType(Math), findsNothing);
    await tester.pumpWidget(app(r'Text $x$', streaming: true));
    expect(find.byType(Math), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'image/file actions and custom registry dispatch without loading images',
    (tester) async {
      String? file;
      String? image;
      await tester.pumpWidget(
        app(
          '<file path="attachments/report.pdf"/>\n\n![Chart](https://example.com/chart.png)\n\n<badge value="ready"/>',
          onFile: (value) => file = value,
          onImage: (value) => image = value,
          builders: {'badge': (_, tag) => Text(tag.attributes['value']!)},
        ),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.text('ready'), findsOneWidget);
      await tester.tap(find.text('File · report.pdf'));
      await tester.tap(find.text('Chart'));
      expect(file, 'attachments/report.pdf');
      expect(image, 'https://example.com/chart.png');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('link callback opens only supported explicit links', (
    tester,
  ) async {
    Uri? target;
    await tester.pumpWidget(
      app('[Example](https://example.com)', onLink: (uri) => target = uri),
    );
    await tester.tap(find.text('Example', findRichText: true));
    expect(target.toString(), 'https://example.com');
    target = null;
    await tester.pumpWidget(
      app('[Unsafe](javascript:alert)', onLink: (uri) => target = uri),
    );
    await tester.tap(find.text('Unsafe', findRichText: true));
    expect(target, isNull);
  });

  testWidgets('unknown HTML and invalid math display as text', (tester) async {
    await tester.pumpWidget(
      app(r'<unknown>safe</unknown> $$\unknowncommand{x}$$'),
    );
    expect(
      find.textContaining('<unknown>safe</unknown>', findRichText: true),
      findsOneWidget,
    );
    expect(find.text(r'$$\unknowncommand{x}$$'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
