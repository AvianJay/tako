import 'automation.dart';

abstract interface class AutomationManagement {
  Future<List<AutomationRule>> listRules();
  Future<AutomationRule?> getRule(String id);
  Future<AutomationRule> saveRule(AutomationRule rule);
  Future<void> deleteRule(String id);
  Future<AutomationRun> runRule(String id);
}
