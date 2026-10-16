import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app_controller.dart';
import 'app/bootstrap.dart';
import 'data/database.dart';
import 'platform/automation/background_entry.dart';
import 'platform/services.dart';

@pragma('vm:entry-point')
Future<void> automationMain() => startAutomationWorker();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'QuickJS-NG',
    ], await rootBundle.loadString('assets/licenses/quickjs-ng.txt'));
  });
  runApp(
    AppBootstrap(
      loadController: () async => AppController(
        database: AppDatabase(),
        services: PlatformServices(),
        promptTemplate: await rootBundle.loadString(
          'assets/prompts/system_prompt.md',
        ),
      ),
    ),
  );
}
