import 'dart:convert';

import '../util/json.dart';
import 'condition.dart';

enum AutomationTrigger { schedule, notification, shortcut }

enum AutomationBatch { immediate, window, scheduled }

enum AutomationStatus {
  queued,
  running,
  waiting,
  completed,
  silent,
  failed,
  cancelled,
  timedOut,
}

class AutomationSchedule {
  const AutomationSchedule({
    this.frequency = 'daily',
    this.hour = 20,
    this.minute = 0,
    this.weekdays = const [1, 2, 3, 4, 5, 6, 7],
    this.everyMinutes = 60,
    this.at,
    this.exact = false,
  });
  final String frequency;
  final int hour, minute, everyMinutes;
  final List<int> weekdays;
  final DateTime? at;
  final bool exact;
  factory AutomationSchedule.fromJson(JsonMap j) => AutomationSchedule(
    frequency: asString(j['frequency']) ?? 'daily',
    hour: asInt(j['hour']) ?? 20,
    minute: asInt(j['minute']) ?? 0,
    everyMinutes: asInt(j['everyMinutes']) ?? 60,
    weekdays: (asList(j['weekdays']) ?? [1, 2, 3, 4, 5, 6, 7])
        .whereType<int>()
        .toList(),
    at: DateTime.tryParse(asString(j['at']) ?? ''),
    exact: asBool(j['exact']) ?? false,
  );
  JsonMap toJson() => {
    'frequency': frequency,
    'hour': hour,
    'minute': minute,
    'weekdays': weekdays,
    'everyMinutes': everyMinutes,
    'at': at?.toUtc().toIso8601String(),
    'exact': exact,
  };
  void validate() {
    if (!{'once', 'daily', 'weekly', 'interval'}.contains(frequency) ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59 ||
        everyMinutes < 15 ||
        everyMinutes > 525600 ||
        (frequency == 'once' && at == null) ||
        (frequency == 'weekly' &&
            (weekdays.isEmpty || weekdays.any((d) => d < 1 || d > 7)))) {
      throw const FormatException('Invalid schedule');
    }
  }

  DateTime? nextAfter(DateTime time) {
    validate();
    if (frequency == 'once') return at!.isAfter(time) ? at!.toUtc() : null;
    if (frequency == 'interval') {
      return time.add(Duration(minutes: everyMinutes)).toUtc();
    }
    final local = time.toLocal();
    for (var day = 0; day <= 7; day++) {
      final next = DateTime(
        local.year,
        local.month,
        local.day + day,
        hour,
        minute,
      );
      if (next.isAfter(time) &&
          (frequency != 'weekly' || weekdays.contains(next.weekday))) {
        return next.toUtc();
      }
    }
    return null;
  }
}

class AutomationRule {
  const AutomationRule({
    required this.id,
    required this.name,
    required this.prompt,
    required this.providerId,
    required this.model,
    this.enabled = false,
    this.trigger = AutomationTrigger.schedule,
    this.condition = '',
    this.batch = AutomationBatch.immediate,
    this.windowSeconds = 60,
    this.schedule = const AutomationSchedule(),
    this.continueConversation = false,
    this.waitTimeoutMinutes,
    this.revision = 1,
    this.conversationId,
  });
  final String id, name, prompt, providerId, model, condition;
  final bool enabled, continueConversation;
  final AutomationTrigger trigger;
  final AutomationBatch batch;
  final int windowSeconds, revision;
  final int? waitTimeoutMinutes;
  final AutomationSchedule schedule;
  final String? conversationId;
  factory AutomationRule.fromJson(JsonMap j) => AutomationRule(
    id: asString(j['id']) ?? '',
    name: asString(j['name']) ?? '',
    prompt: asString(j['prompt']) ?? '',
    providerId: asString(j['providerId']) ?? '',
    model: asString(j['model']) ?? '',
    enabled: asBool(j['enabled']) ?? false,
    trigger: AutomationTrigger.values.firstWhere(
      (v) => v.name == j['trigger'],
      orElse: () => AutomationTrigger.schedule,
    ),
    condition: asString(j['condition']) ?? '',
    batch: AutomationBatch.values.firstWhere(
      (v) => v.name == j['batch'],
      orElse: () => AutomationBatch.immediate,
    ),
    windowSeconds: asInt(j['windowSeconds']) ?? 60,
    schedule: AutomationSchedule.fromJson(asMap(j['schedule']) ?? {}),
    continueConversation: asBool(j['continueConversation']) ?? false,
    waitTimeoutMinutes: asInt(j['waitTimeoutMinutes']),
    revision: asInt(j['revision']) ?? 1,
    conversationId: asString(j['conversationId']),
  );
  JsonMap toJson() => {
    'id': id,
    'name': name,
    'prompt': prompt,
    'providerId': providerId,
    'model': model,
    'enabled': enabled,
    'trigger': trigger.name,
    'condition': condition,
    'batch': batch.name,
    'windowSeconds': windowSeconds,
    'schedule': schedule.toJson(),
    'continueConversation': continueConversation,
    'waitTimeoutMinutes': waitTimeoutMinutes,
    'revision': revision,
    'conversationId': conversationId,
  };
  AutomationRule copyWith({
    bool? enabled,
    int? revision,
    String? conversationId,
  }) => AutomationRule.fromJson({
    ...toJson(),
    'enabled': enabled ?? this.enabled,
    'revision': revision ?? this.revision,
    'conversationId': conversationId ?? this.conversationId,
  });
  void validate() {
    if (id.isEmpty ||
        name.trim().isEmpty ||
        prompt.trim().isEmpty ||
        providerId.isEmpty ||
        model.isEmpty ||
        name.length > 120 ||
        prompt.length > 60000 ||
        windowSeconds < 1 ||
        windowSeconds > 86400 ||
        (waitTimeoutMinutes != null &&
            (waitTimeoutMinutes! < 1 || waitTimeoutMinutes! > 43200))) {
      throw const FormatException('Invalid automation rule');
    }
    NotificationCondition(condition);
    schedule.validate();
  }

  bool get usesSchedule =>
      trigger == AutomationTrigger.schedule ||
      trigger == AutomationTrigger.notification &&
          batch == AutomationBatch.scheduled;
  bool sameTiming(AutomationRule other) =>
      enabled == other.enabled &&
      trigger == other.trigger &&
      batch == other.batch &&
      jsonEncode(schedule.toJson()) == jsonEncode(other.schedule.toJson());
  String encode() => jsonEncode(toJson());
}

class AutomationRun {
  const AutomationRun({
    required this.id,
    required this.rule,
    required this.status,
    required this.createdAt,
    required this.dueAt,
    this.conversationId,
    this.result = '',
    this.reason,
    this.waitingAt,
    this.inputs = const [],
    this.pending = const {},
  });
  final String id;
  final AutomationRule rule;
  final AutomationStatus status;
  final DateTime createdAt, dueAt;
  final DateTime? waitingAt;
  final String? conversationId, reason;
  final String result;
  final List<JsonMap> inputs;
  final JsonMap pending;
  factory AutomationRun.fromJson(JsonMap j) => AutomationRun(
    id: j['id']! as String,
    rule: AutomationRule.fromJson(asMap(j['rule'])!),
    status: AutomationStatus.values.byName(j['status']! as String),
    createdAt: DateTime.parse(j['createdAt']! as String),
    dueAt: DateTime.parse(j['dueAt']! as String),
    conversationId: asString(j['conversationId']),
    result: asString(j['result']) ?? '',
    reason: asString(j['reason']),
    waitingAt: DateTime.tryParse(asString(j['waitingAt']) ?? ''),
    inputs: (asList(j['inputs']) ?? []).map((v) => asMap(v)!).toList(),
    pending: asMap(j['pending']) ?? {},
  );
  JsonMap toJson() => {
    'id': id,
    'rule': rule.toJson(),
    'status': status.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'dueAt': dueAt.toUtc().toIso8601String(),
    'conversationId': conversationId,
    'result': result,
    'reason': reason,
    'waitingAt': waitingAt?.toUtc().toIso8601String(),
    'inputs': inputs,
    'pending': pending,
  };
  AutomationRun copyWith({
    AutomationStatus? status,
    String? conversationId,
    String? result,
    String? reason,
    DateTime? waitingAt,
    JsonMap? pending,
    List<JsonMap>? inputs,
    bool clearWaiting = false,
  }) => AutomationRun.fromJson({
    ...toJson(),
    'status': (status ?? this.status).name,
    'conversationId': conversationId ?? this.conversationId,
    'result': result ?? this.result,
    'reason': reason,
    'waitingAt': clearWaiting
        ? null
        : (waitingAt ?? this.waitingAt)?.toUtc().toIso8601String(),
    'pending': pending ?? this.pending,
    'inputs': inputs ?? this.inputs,
  });
  bool get terminal => {
    AutomationStatus.completed,
    AutomationStatus.silent,
    AutomationStatus.failed,
    AutomationStatus.cancelled,
    AutomationStatus.timedOut,
  }.contains(status);
  bool expired(DateTime now) =>
      waitingAt != null &&
      rule.waitTimeoutMinutes != null &&
      !now.isBefore(
        waitingAt!.add(Duration(minutes: rule.waitTimeoutMinutes!)),
      );
}

bool isSilentAutomationResult(String finalText) =>
    finalText.trim() == '[SILENT]';
