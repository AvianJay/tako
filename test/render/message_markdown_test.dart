import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/ui/render/message_markdown.dart';
import 'package:tako/ui/render/text_colors.dart';

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

/// The span drawing exactly [text], anywhere on screen.
TextSpan? spanWithText(WidgetTester tester, String text) {
  TextSpan? found;
  void walk(InlineSpan span) {
    if (span is! TextSpan) return;
    if (span.text == text) found = span;
    span.children?.forEach(walk);
  }

  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    walk(rich.text);
  }
  return found;
}

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

  testWidgets('image builder replaces chips only for sources it resolves', (
    tester,
  ) async {
    final seen = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageMarkdown(
            data:
                '<image src="local.png"/>\n\n![Chart](local.png)\n\n'
                '<file path="local.png"/>\n\n<image src="https://example.com/x.png"/>',
            copyLabel: 'Copy code',
            imageLabel: 'Image',
            fileLabel: 'File',
            imageBuilder: (_, source, alt) {
              seen.add('$source|$alt');
              return source == 'local.png'
                  ? const SizedBox(key: ValueKey('local'))
                  : null;
            },
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('local')), findsNWidgets(3));
    expect(find.byType(ActionChip), findsOneWidget);
    expect(seen, [
      'local.png|',
      'local.png|Chart',
      'local.png|',
      'https://example.com/x.png|',
    ]);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('highlights, colours and HTML formatting render as styles', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        '==Key== <mark color="green">go</mark> <span color="red">stop</span> '
        '<u>under</u> <kbd>Ctrl</kbd> H<sub>2</sub>O x<sup>3</sup><br>next',
      ),
    );
    final spans = <String, TextStyle>{};
    void walk(InlineSpan span, TextStyle inherited) {
      if (span is! TextSpan) return;
      final style = inherited.merge(span.style);
      if (span.text case final text?) spans[text] = style;
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child, style);
      }
    }

    for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
      walk(text.text, const TextStyle());
    }
    final theme = Theme.of(tester.element(find.byType(MessageMarkdown)));
    final background = theme.scaffoldBackgroundColor;
    final ink = theme.colorScheme.onSurface;
    expect(
      spans['Key']!.backgroundColor,
      highlightColor(textColors['yellow']!, background, ink),
    );
    expect(
      spans['go']!.backgroundColor,
      highlightColor(textColors['green']!, background, ink),
    );
    expect(
      spans['stop']!.color,
      readableTextColor(textColors['red']!, background),
    );
    expect(spans['stop']!.backgroundColor, isNull);
    expect(spans['under']!.decoration, TextDecoration.underline);
    expect(spans['Ctrl']!.fontFamily, 'monospace');
    final size = spans['under']!.fontSize!;
    expect(spans['2']!.fontSize, lessThan(size));
    expect(spans['3']!.fontSize, lessThan(size));
    expect(spans['\n'], isNotNull);
    expect(find.textContaining('<', findRichText: true), findsNothing);
    expect(find.textContaining('==', findRichText: true), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('footnotes list after the reply and open from their number', (
    tester,
  ) async {
    await tester.pumpWidget(
      app('Claim[^1] and[^2].\n\n[^1]: First **source**\n[^2]: Second'),
    );
    expect(find.textContaining('↩', findRichText: true), findsNothing);
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
    expect(
      find.textContaining('First source', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    expect(find.text('Note 1'), findsOneWidget);
    expect(
      find.textContaining('First source', findRichText: true),
      findsNWidgets(2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('details open on tap, or from the start when marked open', (
    tester,
  ) async {
    await tester.pumpWidget(
      app('<details>\n<summary>More</summary>\n\nHidden part\n</details>'),
    );
    expect(find.text('More', findRichText: true), findsOneWidget);
    expect(find.text('Hidden part', findRichText: true), findsNothing);
    await tester.tap(find.text('More', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('Hidden part', findRichText: true), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app('<details open>\nShown\n</details>'));
    expect(find.text('Details', findRichText: true), findsOneWidget);
    expect(find.text('Shown', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('spoilers hide behind a bar until tapped', (tester) async {
    await tester.pumpWidget(app('Answer: ||<span color="red">42</span>||'));
    var hidden = spanWithText(tester, '42')!;
    expect(hidden.style!.color, hidden.style!.backgroundColor);
    expect(hidden.semanticsLabel, 'Hidden text. Tap to show.');
    (hidden.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pump();
    hidden = spanWithText(tester, '42')!;
    expect(hidden.recognizer, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ruby, badges and aligned table cells', (tester) async {
    await tester.pumpWidget(
      app(
        '<ruby>漢<rt>hàn</rt></ruby> <badge color="green">完成</badge>\n\n'
        '| A | B |\n|:-:|--:|\n| 1 | 2 |',
      ),
    );
    final base = tester.widget<RichText>(find.text('漢', findRichText: true));
    final annotation = tester.widget<RichText>(
      find.text('hàn', findRichText: true),
    );
    expect(
      annotation.text.style!.fontSize!,
      lessThan(base.text.style!.fontSize!),
    );
    expect(find.text('完成', findRichText: true), findsOneWidget);
    expect(
      tester.widget<RichText>(find.text('A', findRichText: true)).textAlign,
      TextAlign.center,
    );
    expect(
      tester.widget<RichText>(find.text('2', findRichText: true)).textAlign,
      TextAlign.right,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('suggested replies send on tap, only when offered', (
    tester,
  ) async {
    String? sent;
    Widget host({ValueChanged<String>? onReply, bool visuals = true}) =>
        MaterialApp(
          home: Scaffold(
            body: MessageMarkdown(
              data: 'Shall I?\n\n```replies\n- Yes please\n- Not now\n```',
              copyLabel: 'Copy code',
              imageLabel: 'Image',
              fileLabel: 'File',
              visuals: visuals,
              onReply: onReply,
            ),
          ),
        );
    await tester.pumpWidget(host(onReply: (text) => sent = text));
    expect(find.byType(ActionChip), findsNWidgets(2));
    await tester.tap(find.text('Not now'));
    expect(sent, 'Not now');
    await tester.pumpWidget(host());
    expect(find.byType(ActionChip), findsNothing);
    expect(find.textContaining('Yes please', findRichText: true), findsNothing);
    // In the user's own messages the block stays code.
    await tester.pumpWidget(host(onReply: (_) {}, visuals: false));
    expect(find.byType(ActionChip), findsNothing);
    expect(
      find.textContaining('Yes please', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('phone and message links open through the host', (tester) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      app(
        '[Call](tel:+886212345678) or [text](sms:+886912345678)',
        onLink: opened.add,
      ),
    );
    for (final text in ['Call', 'text']) {
      (spanWithText(tester, text)!.recognizer! as TapGestureRecognizer)
          .onTap!();
    }
    expect(opened.map((uri) => '$uri'), [
      'tel:+886212345678',
      'sms:+886912345678',
    ]);
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
