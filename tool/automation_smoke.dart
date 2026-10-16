// Isolated on-device smoke probe. Build with a separate tako.applicationId;
// never point it at the user's installed app or a real model endpoint.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tako/app/app_controller.dart';
import 'package:tako/core/automation/automation.dart';
import 'package:tako/core/providers/provider_config.dart';
import 'package:tako/data/database.dart';
import 'package:tako/platform/automation/background_entry.dart';
import 'package:tako/platform/services.dart';

@pragma('vm:entry-point')
Future<void> automationMain() => startAutomationWorker();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final display = ValueNotifier('Starting isolated automation probe');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ValueListenableBuilder(
            valueListenable: display,
            builder: (_, value, _) => Text(value),
          ),
        ),
      ),
    ),
  );
  final app = AppController(
    database: AppDatabase(),
    services: PlatformServices(),
    promptTemplate: 'Automation smoke fixture',
  );
  try {
    await app.initialize();
    app.setAppForeground(false);
    await app.saveProvider(
      ProviderConfig(
        id: 'fixture',
        displayName: 'Local test fixture',
        apiType: ApiType.chatCompletions,
        baseUrl: 'http://10.0.2.2:18080/v1',
        model: 'fixture',
        isLocal: true,
        capabilities: const ProviderCapabilities(
          tools: true,
          contextWindow: 32768,
        ),
        maxOutputTokens: 256,
      ),
    );
    final scheduledRule = await app.automation.saveRule(
      AutomationRule(
        id: 'schedule-probe',
        name: 'Schedule fixture',
        prompt:
            'BACKGROUND FIXTURE: call get_device_status once and report completion.',
        providerId: 'fixture',
        model: 'fixture',
        enabled: true,
        schedule: AutomationSchedule(
          frequency: 'once',
          at: DateTime.now().add(const Duration(seconds: 5)),
        ),
      ),
    );
    for (var round = 0; round < 120; round++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final runs = await app.automation.repository.runs();
      final completed = runs
          .where(
            (r) =>
                r.rule.id == 'schedule-probe' &&
                r.rule.revision == scheduledRule.revision &&
                r.status == AutomationStatus.completed,
          )
          .firstOrNull;
      if (completed != null) {
        final audit = await app.audit.list();
        if (completed.result != 'Automation fixture result' ||
            !audit.any(
              (r) => r.toolName == 'get_device_status' && !r.isError,
            )) {
          throw StateError('fixture assertion');
        }
        display.value = 'AUTOMATION_SMOKE_OK';
        debugPrint(
          'AUTOMATION_SMOKE_OK: headless worker, device tool, persisted result',
        );
        await app.automation.saveRule(
          const AutomationRule(
            id: 'notification-probe',
            name: 'Notification fixture',
            prompt:
                'BACKGROUND FIXTURE: call get_device_status once and report completion.',
            providerId: 'fixture',
            model: 'fixture',
            enabled: true,
            trigger: AutomationTrigger.notification,
            condition:
                'package == "com.android.shell" and "Tako fixture" in title',
            batch: AutomationBatch.window,
            windowSeconds: 2,
          ),
        );
        debugPrint('AUTOMATION_NOTIFICATION_READY');
        return;
      }
      if (runs.any(
        (r) =>
            r.rule.id == 'schedule-probe' &&
            r.rule.revision == scheduledRule.revision &&
            r.status == AutomationStatus.failed,
      )) {
        throw StateError('fixture task failed');
      }
    }
    throw StateError('fixture deadline');
  } catch (_) {
    display.value = 'AUTOMATION_SMOKE_FAILED';
    debugPrint('AUTOMATION_SMOKE_FAILED');
  }
}
