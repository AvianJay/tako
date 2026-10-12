import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/ui/chat/thinking_section.dart';
import 'package:tako/ui/render/revealing_text.dart';

void main() {
  testWidgets(
    'streaming fades only appended text and settles on the full answer',
    (tester) async {
      Widget view(String text, {bool streaming = true, bool reduced = false}) =>
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(
                body: RevealingText(
                  span: TextSpan(text: text),
                  streaming: streaming,
                ),
              ),
            ),
          );
      await tester.pumpWidget(view('Hello'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(view('Hello world'));
      final rich = tester.widget<Text>(
        find.descendant(
          of: find.byType(RevealingText),
          matching: find.byType(Text),
        ),
      );
      expect(rich.textSpan!.toPlainText(), 'Hello world');
      final span = rich.textSpan! as TextSpan;
      expect((span.children!.first as TextSpan).text, 'Hello');
      expect((span.children!.last as TextSpan).style!.color!.a, lessThan(1));
      await tester.pumpWidget(view('Hello world!', streaming: false));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byType(RevealingText),
                matching: find.byType(Text),
              ),
            )
            .textSpan!
            .toPlainText(),
        'Hello world!',
      );
      await tester.pumpWidget(view('Reduced motion', reduced: true));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'thinking is compact, expands on demand and collapses when answer begins',
    (tester) async {
      Widget view(bool answer) => MaterialApp(
        home: Scaffold(
          body: ThinkingSection(
            text: 'Reasoning details',
            label: 'Thinking',
            hasAnswer: answer,
          ),
        ),
      );
      await tester.pumpWidget(view(false));
      expect(tester.getSize(find.byType(ThinkingSection)).height, lessThan(48));
      expect(find.text('Reasoning details'), findsNothing);
      await tester.tap(find.text('Thinking'));
      await tester.pumpAndSettle();
      expect(find.text('Reasoning details'), findsOneWidget);
      await tester.pumpWidget(view(true));
      await tester.pumpAndSettle();
      expect(find.text('Reasoning details'), findsNothing);
      expect(tester.getSize(find.byType(ThinkingSection)).height, lessThan(48));
    },
  );
}
