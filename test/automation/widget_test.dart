import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/app/app_controller.dart';
import 'package:tako/app/automation_controller.dart';
import 'package:tako/core/automation/automation.dart';
import 'package:tako/core/automation/automation_capability.dart';
import 'package:tako/data/database.dart';
import 'package:tako/l10n/gen/app_localizations.dart';
import 'package:tako/ui/automation/automation_screen.dart';

import '../app/app_controller_test.dart' as fixtures;

class _Capability extends UnavailableAutomation {
  @override
  bool get isAvailable => true;
  @override
  bool get shortcutEntry => true;
  @override
  Future<Map<String, Object?>> status() async => {'canPost': true};
}

class _Services extends fixtures.FakeServices {
  final _capability = _Capability();
  @override
  AutomationCapability get automation => _capability;
}

// The form test is deliberately independent of native model/file discovery
// and database scheduling; repository/agent tests cover real persistence.
class _UiApp extends AppController {
  _UiApp(AppDatabase database)
    : super(
        database: database,
        services: _Services(),
        promptTemplate: 'Fixture',
      ) {
    providers = [fixtures.config()];
    selectedProviderId = 'local';
    selectedModelId = 'model-1';
  }
  late final _uiAutomation = _UiAutomations(this);
  @override
  AutomationController get automation => _uiAutomation;
  void changed() => notifyListeners();
}

class _UiAutomations extends AutomationController {
  _UiAutomations(_UiApp super.app) {
    platformStatus = {'canPost': true};
  }
  @override
  Future<AutomationRule> saveRule(AutomationRule rule) async {
    rule.validate();
    rules = [...rules, rule];
    (app as _UiApp).changed();
    return rule;
  }

  @override
  Future<List<AutomationRule>> listRules() async => rules;
  int clears = 0;
  @override
  Future<void> clearHistory() async {
    clears++;
  }
}

void main() {
  testWidgets(
    'rule editor saves a disabled rule with a text model and prompt',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = AppDatabase(NativeDatabase.memory());
      final app = _UiApp(database);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await database.close();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith((ref) => app)],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const AutomationsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Set up Shortcuts automation'), findsOneWidget);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      Finder field(String label) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label,
      );
      await tester.enterText(field('Name'), 'Daily fixture');
      await tester.enterText(field('Task prompt'), 'Check my fixture');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final saved = (await app.automation.listRules()).single;
      expect(saved.name, 'Daily fixture');
      expect(saved.prompt, 'Check my fixture');
      expect(saved.model, 'model-1');
      expect(saved.enabled, isFalse);
      expect(find.text('Daily fixture'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear finished history'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(app._uiAutomation.clears, 0);
      await tester.tap(find.byTooltip('Clear finished history'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(app._uiAutomation.clears, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
