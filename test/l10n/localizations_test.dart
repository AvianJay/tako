import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/l10n/gen/app_localizations.dart';
import 'package:tako/ui/settings/app_update_screen.dart';

void main() {
  test('translation sources contain no lossy encoding replacements', () {
    final files = Directory(
      'lib/l10n',
    ).listSync().whereType<File>().where((file) => file.path.endsWith('.arb'));
    final damaged = RegExp(r'\?{2,}|\uFFFD');
    for (final file in files) {
      final strings =
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      for (final entry in strings.entries) {
        if (entry.key.startsWith('@') || entry.value is! String) continue;
        expect(
          damaged.hasMatch(entry.value! as String),
          isFalse,
          reason: '${file.path}: ${entry.key} contains encoding replacements',
        );
      }
    }
  });

  for (final locale in [const Locale('zh'), const Locale('zh', 'TW')]) {
    testWidgets('updater displays Chinese labels for $locale', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AppUpdateScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(locale.countryCode == 'TW' ? '應用程式更新' : '应用更新'),
        findsOneWidget,
      );
      expect(
        find.text(locale.countryCode == 'TW' ? '檢查更新' : '检查更新'),
        findsOneWidget,
      );
      final l = AppLocalizations.of(
        tester.element(find.byType(AppUpdateScreen)),
      );
      for (final label in [
        l.appUpdates,
        l.appUpdatesHelp,
        l.installedVersion,
        l.checkUpdates,
        l.downloadUpdate,
        l.updateAvailable,
        l.updateCurrent,
        l.updateCheckFailed,
        l.updateInstallPermission,
        l.updateInstallerOpened,
        l.updateInstallFailed,
        l.generateChatTitle,
        l.titleGenerationFailed,
        l.toolLoopDetected,
        l.maxToolSteps,
        l.maxScreenToolSteps,
      ]) {
        expect(
          RegExp(r'[\u3400-\u9FFF]').hasMatch(label),
          isTrue,
          reason: label,
        );
        expect(label, isNot(contains('?')));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
