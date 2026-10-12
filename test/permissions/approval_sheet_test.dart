import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/app/app_controller.dart';
import 'package:tako/core/browser/browser_capability.dart';
import 'package:tako/core/notifications/notification_capability.dart';
import 'package:tako/core/providers/cancel_token.dart';
import 'package:tako/core/screen/screen_capability.dart';
import 'package:tako/core/shell/shell_capability.dart';
import 'package:tako/core/tools/tool.dart';
import 'package:tako/data/database.dart';
import 'package:tako/l10n/gen/app_localizations.dart';
import 'package:tako/platform/app_services.dart';
import 'package:tako/ui/chat/tool_widgets.dart';

class _NoServices implements AppServices {
  @override
  final BrowserCapability browser = UnavailableBrowser();
  @override
  final ScreenCapability screen = UnavailableScreen();
  @override
  final ShellCapability shell = UnavailableShell();
  @override
  final NotificationCapability notifications = UnavailableNotifications();
  @override
  Future<void> refreshDeviceControl() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final risk in [RiskLevel.sensitive, RiskLevel.action, RiskLevel.high]) {
    testWidgets(
      '${risk.name} approval keeps decisions visible above long arguments',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 760);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final database = AppDatabase(NativeDatabase.memory());
        final app = AppController(
          database: database,
          services: _NoServices(),
          promptTemplate: '',
        );
        final token = CancelToken();
        addTearDown(() async {
          token.cancel();
          app.dispose();
          await tester.runAsync(database.close);
        });
        final decision = app.permissionGate.authorize(
          toolName: 'file_write',
          args: {
            'path': 'report.txt',
            'text': 'Long content to review\n' * 1000,
          },
          risk: risk,
          context: ToolContext(
            conversationId: 'chat',
            messageId: 'message',
            cancel: token,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ToolApprovalSheet(app: app),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Deny').hitTestable(), findsOneWidget);
        if (risk == RiskLevel.action) {
          expect(find.text('Allow once'), findsNothing);
          expect(find.text('Allow in this chat').hitTestable(), findsOneWidget);
        } else {
          expect(find.text('Allow once').hitTestable(), findsOneWidget);
        }
        final denyRect = tester.getRect(
          find.widgetWithText(OutlinedButton, 'Deny'),
        );
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -500),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(find.widgetWithText(OutlinedButton, 'Deny')),
          denyRect,
        );
        expect(find.text('Deny').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Deny'));
        await tester.pump();
        expect((await decision).allowed, isFalse);
      },
    );
  }
}
