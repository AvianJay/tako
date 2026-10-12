import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/app/app_controller.dart';
import 'package:tako/app/bootstrap.dart';
import 'package:tako/data/database.dart';
import 'package:tako/platform/services.dart';
import 'package:tako/ui/brand/tako_mark.dart';
import 'package:tako/ui/chat/chat_screen.dart';

/// The launch screen's mark; in-app marks use the icon extent.
final splash = find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint &&
      widget.painter is TakoMarkPainter &&
      (widget.painter! as TakoMarkPainter).extent ==
          TakoMarkPainter.launcherExtent,
);

void main() {
  testWidgets(
    'first frame paints while controller and storage are still pending',
    (tester) async {
      final pending = Completer<AppController>();
      final database = AppDatabase(NativeDatabase.memory());
      await tester.pumpWidget(
        AppBootstrap(loadController: () => pending.future),
      );
      expect(find.bySemanticsLabel('Tako'), findsOneWidget);
      expect(splash, findsOneWidget);
      expect(find.byType(ChatScreen), findsNothing);
      final controller = AppController(
        database: database,
        services: PlatformServices(),
        promptTemplate: 'test',
      );
      await tester.runAsync(() async {
        pending.complete(controller);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      // The app builds beneath the splash, which still has to morph.
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(splash, findsOneWidget);
      // Test frames are never reported rasterized; the fallback starts it.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(splash, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(database.close);
    },
  );
}
