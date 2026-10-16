import 'dart:convert';
import 'dart:io';

import '../../core/automation/automation.dart';
import '../../core/automation/automation_capability.dart';
import '../../core/automation/condition.dart';
import '../../core/util/json.dart';
import 'automation_api.g.dart';

class NativeAutomation extends AutomationCapability
    implements AutomationEvents {
  NativeAutomation() {
    AutomationEvents.setUp(this);
  }
  final _api = AutomationApi();
  Future<bool> Function()? onExecute;
  Future<void> ready() => _api.ready();
  @override
  bool get isAvailable => Platform.isAndroid || Platform.isIOS;
  @override
  bool get notificationTriggers => Platform.isAndroid;
  @override
  bool get exactSchedules => Platform.isAndroid;
  @override
  bool get shortcutEntry => Platform.isIOS;
  @override
  Future<JsonMap> status() async => tryDecodeObject(await _api.status()) ?? {};
  @override
  Future<void> requestExactPermission() => _api.requestExactPermission();
  @override
  Future<bool> requestNotifications() => _api.requestNotifications();
  @override
  Future<void> syncRules(
    List<AutomationRule> rules,
    Map<String, DateTime> next,
  ) => _api.syncRules(
    jsonEncode([
      for (final rule in rules)
        {
          ...rule.toJson(),
          'nextAt': next[rule.id]?.millisecondsSinceEpoch,
          'notificationFilter': NotificationCondition.formValues(
            rule.condition,
          ),
        },
    ]),
  );
  @override
  Future<List<JsonMap>> inbox() async =>
      (jsonDecode(await _api.inbox()) as List)
          .map((e) => (e as Map).cast<String, Object?>())
          .toList();
  @override
  Future<void> acknowledge(List<String> ids) => _api.acknowledge(ids);
  @override
  Future<void> wake(DateTime? at) => _api.wake(at?.millisecondsSinceEpoch);
  @override
  Future<void> notify(
    String runId,
    String title,
    String body, {
    bool waiting = false,
  }) => _api.notify(runId, title, body, waiting);
  @override
  Future<bool> acquire(String owner) => _api.acquire(owner);
  @override
  Future<void> clearNotification(String runId) => _api.clearNotification(runId);
  @override
  Future<void> release(String owner) => _api.release(owner);
  @override
  Future<String?> interrupted(String owner) => _api.interrupted(owner);
  @override
  Future<void> signalChanged() => _api.signalChanged();
  @override
  void changed() {
    onChanged?.call();
    notifyListeners();
  }

  @override
  void openRun(String runId) => onOpen?.call(runId);
  @override
  Future<bool> execute() async => await onExecute?.call() ?? true;
  @override
  void stop(String reason) => onStop?.call(reason);
}
