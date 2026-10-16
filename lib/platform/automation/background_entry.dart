import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_controller.dart';
import '../../data/database.dart';
import '../services.dart';
import 'native_automation.dart';

Future<void> startAutomationWorker() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = PlatformServices();
  final app = AppController(
    database: AppDatabase(),
    services: services,
    promptTemplate: await rootBundle.loadString(
      'assets/prompts/system_prompt.md',
    ),
    bindControls: false,
  );
  final capability = services.automation as NativeAutomation;
  capability.onExecute = () async {
    await app.automation.drain();
    return true;
  };
  services.screen.onTakeOver = () => app.automation.pause();
  services.browser.onTakeOver = () => app.automation.pause();
  await app.initialize(automationWorker: true);
  await app.automation.initialize(background: true);
  await capability.ready();
}
