import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'tako',
    dartOut: 'lib/platform/automation/automation_api.g.dart',
    kotlinOut:
        'android/app/src/main/kotlin/tw/avianjay/tako/AutomationApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'tw.avianjay.tako',
      errorClassName: 'AutomationError',
    ),
    swiftOut: 'ios/Runner/AutomationApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'AutomationApiError'),
  ),
)
@HostApi()
abstract class AutomationApi {
  void ready();
  String status();
  void requestExactPermission();
  @async
  bool requestNotifications();
  void syncRules(String rulesJson);
  String inbox();
  void acknowledge(List<String> ids);
  void wake(int? at);
  void notify(String runId, String title, String body, bool waiting);
  void clearNotification(String runId);
  bool acquire(String owner);
  void release(String owner);
  String? interrupted(String owner);
  void signalChanged();
}

@FlutterApi()
abstract class AutomationEvents {
  void changed();
  void openRun(String runId);
  @async
  bool execute();
  void stop(String reason);
}
