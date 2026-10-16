import 'package:flutter/foundation.dart';

import '../../platform/capabilities.dart';
import '../util/json.dart';
import 'automation.dart';

abstract class AutomationCapability extends ChangeNotifier
    implements Capability {
  bool get notificationTriggers;
  bool get exactSchedules;
  bool get shortcutEntry;
  Future<JsonMap> status();
  Future<void> requestExactPermission();
  Future<bool> requestNotifications();
  Future<void> syncRules(
    List<AutomationRule> rules,
    Map<String, DateTime> next,
  );
  Future<List<JsonMap>> inbox();
  Future<void> acknowledge(List<String> ids);
  Future<void> wake(DateTime? at);
  Future<void> notify(
    String runId,
    String title,
    String body, {
    bool waiting = false,
  });
  Future<bool> acquire(String owner);
  Future<void> clearNotification(String runId);
  Future<void> release(String owner);
  Future<String?> interrupted(String owner);
  Future<void> signalChanged();
  void Function()? onChanged;
  void Function(String runId)? onOpen;
  void Function(String reason)? onStop;
}

class UnavailableAutomation extends AutomationCapability {
  @override
  bool get isAvailable => false;
  @override
  bool get notificationTriggers => false;
  @override
  bool get exactSchedules => false;
  @override
  bool get shortcutEntry => false;
  @override
  Future<JsonMap> status() async => {};
  @override
  Future<void> requestExactPermission() async {}
  @override
  Future<bool> requestNotifications() async => false;
  @override
  Future<void> syncRules(
    List<AutomationRule> rules,
    Map<String, DateTime> next,
  ) async {}
  @override
  Future<List<JsonMap>> inbox() async => [];
  @override
  Future<void> acknowledge(List<String> ids) async {}
  @override
  Future<void> wake(DateTime? at) async {}
  @override
  Future<void> notify(
    String runId,
    String title,
    String body, {
    bool waiting = false,
  }) async {}
  @override
  Future<bool> acquire(String owner) async => true;
  @override
  Future<void> clearNotification(String runId) async {}
  @override
  Future<void> release(String owner) async {}
  @override
  Future<String?> interrupted(String owner) async => null;
  @override
  Future<void> signalChanged() async {}
}
