import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/automation/automation.dart';
import '../core/automation/condition.dart';
import '../core/util/ids.dart';
import '../core/util/json.dart';
import 'database.dart';

/// All ingest and batch mutations are transactional. Native delivery is at
/// least once; the event ledger makes importing it idempotent.
class AutomationRepository {
  AutomationRepository(this.database);
  final AppDatabase database;
  Future<List<AutomationRule>> rules() async =>
      (await database
              .customSelect('SELECT data FROM automation_rules ORDER BY rowid')
              .get())
          .map(
            (r) => AutomationRule.fromJson(
              tryDecodeObject(r.read<String>('data'))!,
            ),
          )
          .toList();
  Future<AutomationRule?> rule(String id) async {
    final row = await database
        .customSelect(
          'SELECT data FROM automation_rules WHERE id=?',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    return row == null
        ? null
        : AutomationRule.fromJson(tryDecodeObject(row.read<String>('data'))!);
  }

  Future<Map<String, DateTime>> nextTimes() async => {
    for (final r
        in await database
            .customSelect(
              'SELECT id,next_at FROM automation_rules WHERE next_at IS NOT NULL',
            )
            .get())
      r.read<String>('id'): DateTime.fromMillisecondsSinceEpoch(
        r.read<int>('next_at'),
        isUtc: true,
      ),
  };
  Future<void> saveRule(
    AutomationRule rule, {
    DateTime? now,
  }) => database.transaction(() async {
    rule.validate();
    final previous = await this.rule(rule.id);
    final next = previous != null && rule.sameTiming(previous)
        ? (await nextTimes())[rule.id]
        : rule.enabled && rule.usesSchedule
        ? rule.schedule.nextAfter(now ?? DateTime.now())
        : null;
    await database.customStatement(
      'INSERT INTO automation_rules(id,data,next_at) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data,next_at=excluded.next_at',
      [rule.id, rule.encode(), next?.millisecondsSinceEpoch],
    );
    if (!rule.enabled) await cancelRule(rule.id);
  });

  Future<void> deleteRule(String id) async {
    await cancelRule(id);
    await database.customStatement('DELETE FROM automation_rules WHERE id=?', [
      id,
    ]);
  }

  Future<void> cancelRule(String id) async {
    for (final run in await runs(ruleId: id, statuses: activeStatuses)) {
      if (!run.terminal) {
        await saveRun(run.copyWith(status: AutomationStatus.cancelled));
      }
    }
    await database.customStatement(
      'DELETE FROM automation_inputs WHERE rule_id=?',
      [id],
    );
  }

  Future<void> saveRun(AutomationRun run) => database.customStatement(
    'INSERT INTO automation_runs(id,rule_id,status,due_at,data) VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET status=excluded.status,due_at=excluded.due_at,data=excluded.data',
    [
      run.id,
      run.rule.id,
      run.status.name,
      run.dueAt.millisecondsSinceEpoch,
      jsonEncode(run.toJson()),
    ],
  );
  static const activeStatuses = [
    AutomationStatus.queued,
    AutomationStatus.running,
    AutomationStatus.waiting,
  ];
  Future<List<AutomationRun>> recentRuns({int limit = 100}) async {
    final active = await runs(statuses: activeStatuses);
    final recent = await runs(
      statuses: AutomationStatus.values
          .where((s) => !activeStatuses.contains(s))
          .toList(),
      limit: limit,
    );
    return [...active, ...recent]..sort((a, b) => b.dueAt.compareTo(a.dueAt));
  }

  /// Keep resumable work and conversations still used by a continuing rule.
  Future<List<String>> clearHistory({
    String? openConversationId,
  }) => database.transaction(() async {
    await database.customStatement(
      "DELETE FROM automation_runs WHERE status NOT IN ('queued','running','waiting')",
    );
    final rows = await database
        .customSelect(
          '''
      SELECT id FROM conversation_records AS c
      WHERE json_extract(c.data, '\$.automationRuleId') IS NOT NULL
        AND c.id IS NOT ?
        AND NOT EXISTS (SELECT 1 FROM automation_runs AS r
          WHERE json_extract(r.data, '\$.conversationId') = c.id
            OR (json_extract(r.data, '\$.rule.continueConversation') = 1
              AND json_extract(r.data, '\$.rule.conversationId') = c.id))
        AND NOT EXISTS (SELECT 1 FROM automation_runs AS r
          WHERE r.status = 'running' AND json_extract(r.data, '\$.conversationId') IS NULL)
        AND NOT EXISTS (SELECT 1 FROM automation_rules AS r
          WHERE json_extract(r.data, '\$.continueConversation') = 1
            AND json_extract(r.data, '\$.conversationId') = c.id)
    ''',
          variables: [Variable<String>(openConversationId)],
        )
        .get();
    return rows.map((r) => r.read<String>('id')).toList();
  });

  /// Read scheduling metadata without decoding stored prompts/tool receipts.
  Future<DateTime?> nextWake() async {
    final row = await database.customSelect('''
      SELECT MIN(at) AS at FROM (
        SELECT due_at AS at FROM automation_runs WHERE status='queued'
        UNION ALL
        SELECT CAST(strftime('%s', json_extract(data, '\$.waitingAt')) AS INTEGER) * 1000 + 1000
          + CAST(json_extract(data, '\$.rule.waitTimeoutMinutes') AS INTEGER) * 60000
          FROM automation_runs WHERE status='waiting'
        UNION ALL
        SELECT expires_at AS at FROM execution_leases
          WHERE EXISTS (SELECT 1 FROM automation_runs WHERE status='running')
      )
    ''').getSingle();
    final value = row.readNullable<int>('at');
    return value == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }

  Future<List<AutomationRun>> runs({
    String? ruleId,
    List<AutomationStatus>? statuses,
    int? limit,
  }) async =>
      (await database
              .customSelect(
                'SELECT data FROM automation_runs WHERE 1=1 ${ruleId == null ? '' : 'AND rule_id=?'} ${statuses == null ? '' : 'AND status IN (${statuses.map((_) => '?').join(',')})'} ORDER BY due_at DESC ${limit == null ? '' : 'LIMIT ?'}',
                variables: [
                  if (ruleId != null) Variable.withString(ruleId),
                  if (statuses != null)
                    ...statuses.map((s) => Variable.withString(s.name)),
                  if (limit != null) Variable.withInt(limit),
                ],
              )
              .get())
          .map(
            (r) => AutomationRun.fromJson(
              tryDecodeObject(r.read<String>('data'))!,
            ),
          )
          .toList();
  Future<AutomationRun?> run(String id) async {
    final row = await database
        .customSelect(
          'SELECT data FROM automation_runs WHERE id=?',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    return row == null
        ? null
        : AutomationRun.fromJson(tryDecodeObject(row.read<String>('data'))!);
  }

  Future<AutomationRun> enqueue(
    AutomationRule rule, {
    List<JsonMap> inputs = const [],
    DateTime? due,
    String? id,
  }) async {
    final now = DateTime.now().toUtc();
    final chunks = <List<JsonMap>>[];
    var chunk = <JsonMap>[];
    var chars = 0;
    for (final input in inputs) {
      final size = jsonEncode(input).length;
      if (chunk.isNotEmpty && (chunk.length >= 50 || chars + size > 24000)) {
        chunks.add(chunk);
        chunk = [];
        chars = 0;
      }
      chunk.add(input);
      chars += size;
    }
    if (chunk.isNotEmpty || chunks.isEmpty) chunks.add(chunk);
    AutomationRun? first;
    for (final input in chunks) {
      final run = AutomationRun(
        id: first == null ? (id ?? newId()) : newId(),
        rule: rule,
        status: AutomationStatus.queued,
        createdAt: now,
        dueAt: due ?? now,
        inputs: input,
      );
      await saveRun(run);
      first ??= run;
    }
    return first!;
  }

  Future<void> ingest(
    List<JsonMap> events, {
    DateTime? now,
    bool allowExact = true,
  }) => database.transaction(() async {
    final time = now ?? DateTime.now();
    final all = await rules();
    var clockChanged = false;
    for (final event in events) {
      final id = asString(event['id']);
      if (id == null) continue;
      final found = await database
          .customSelect(
            'SELECT 1 FROM automation_events WHERE id=?',
            variables: [Variable.withString(id)],
          )
          .getSingleOrNull();
      if (found != null) continue;
      await database.customStatement(
        'INSERT INTO automation_events(id,received_at) VALUES(?,?)',
        [id, time.millisecondsSinceEpoch],
      );
      final kind = event['kind'];
      if (kind == 'clock') {
        clockChanged = true;
        continue;
      }
      for (final rule in all.where((r) => r.enabled)) {
        if (kind == 'notification' &&
            rule.trigger == AutomationTrigger.notification) {
          final revisions = asMap(event['ruleRevisions']);
          if (revisions != null && revisions[rule.id] != rule.revision) {
            continue;
          }
          final data = asMap(event['data']) ?? {};
          if (!NotificationCondition(rule.condition).matches(data)) continue;
          if (rule.batch == AutomationBatch.scheduled) {
            await database.customStatement(
              'INSERT OR IGNORE INTO automation_inputs(id,rule_id,data) VALUES(?,?,?)',
              ['${rule.id}:$id', rule.id, jsonEncode(data)],
            );
          } else if (rule.batch == AutomationBatch.window) {
            final received = DateTime.fromMillisecondsSinceEpoch(
              asInt(event['receivedAt']) ?? time.millisecondsSinceEpoch,
              isUtc: true,
            );
            final batch =
                (await runs(
                      ruleId: rule.id,
                      statuses: [AutomationStatus.queued],
                    ))
                    .where(
                      (r) =>
                          r.status == AutomationStatus.queued &&
                          r.rule.revision == rule.revision &&
                          !r.dueAt.isBefore(received) &&
                          r.inputs.length < 50 &&
                          jsonEncode(r.inputs).length +
                                  jsonEncode(data).length <=
                              24000,
                    )
                    .firstOrNull;
            if (batch == null) {
              await enqueue(
                rule,
                inputs: [data],
                due: received.add(Duration(seconds: rule.windowSeconds)),
              );
            } else {
              await saveRun(batch.copyWith(inputs: [...batch.inputs, data]));
            }
          } else {
            await enqueue(rule, inputs: [data]);
          }
        } else if ((kind == 'schedule' || kind == 'shortcut') &&
            event['ruleId'] == rule.id &&
            (event['revision'] == null || event['revision'] == rule.revision)) {
          final input = asMap(event['data']);
          if (kind == 'shortcut') {
            if (rule.trigger == AutomationTrigger.shortcut) {
              await enqueue(rule, inputs: [?input]);
            }
          } else {
            if (allowExact || !rule.schedule.exact) {
              await _scheduled(rule, time);
            }
          }
        }
      }
    }
    // Catch up once, not once per missed occurrence.
    final next = await nextTimes();
    for (final rule in all.where((r) => r.enabled && r.usesSchedule)) {
      if (rule.schedule.exact && !allowExact) continue;
      if (next[rule.id] case final due? when !due.isAfter(time)) {
        await _scheduled(rule, time);
      }
      // Catch up before recomputing wall-clock schedules for a time-zone change.
      // Interval schedules keep their existing cadence.
      if (clockChanged && rule.schedule.frequency != 'interval') {
        await database.customStatement(
          'UPDATE automation_rules SET next_at=? WHERE id=?',
          [rule.schedule.nextAfter(time)?.millisecondsSinceEpoch, rule.id],
        );
      }
    }
  });
  Future<void> _scheduled(AutomationRule rule, DateTime now) async {
    final next = (await nextTimes())[rule.id];
    if (next == null || next.isAfter(now)) return;
    final records = await database
        .customSelect(
          'SELECT data FROM automation_inputs WHERE rule_id=? ORDER BY rowid',
          variables: [Variable.withString(rule.id)],
        )
        .get();
    final input = records
        .map((r) => tryDecodeObject(r.read<String>('data'))!)
        .toList();
    if (rule.trigger == AutomationTrigger.schedule || input.isNotEmpty) {
      await enqueue(rule, inputs: input);
    }
    await database.customStatement(
      'DELETE FROM automation_inputs WHERE rule_id=?',
      [rule.id],
    );
    await database.customStatement(
      'UPDATE automation_rules SET next_at=? WHERE id=?',
      [rule.schedule.nextAfter(now)?.millisecondsSinceEpoch, rule.id],
    );
  }

  Future<bool> acquire(
    String owner, {
    DateTime? now,
  }) => database.transaction(() async {
    final time = now ?? DateTime.now();
    await database.customStatement(
      'DELETE FROM execution_leases WHERE expires_at <= ?',
      [time.millisecondsSinceEpoch],
    );
    final rows = await database
        .customSelect('SELECT owner FROM execution_leases WHERE name=\'agent\'')
        .get();
    if (rows.isNotEmpty && rows.single.read<String>('owner') != owner) {
      return false;
    }
    await database.customStatement(
      'INSERT INTO execution_leases(name,owner,expires_at) VALUES(\'agent\',?,?) ON CONFLICT(name) DO UPDATE SET expires_at=excluded.expires_at',
      [owner, time.add(const Duration(seconds: 45)).millisecondsSinceEpoch],
    );
    return true;
  });
  Future<void> release(String owner) => database.customStatement(
    'DELETE FROM execution_leases WHERE owner=?',
    [owner],
  );
  Future<bool> hasLease() async =>
      (await database
              .customSelect(
                'SELECT 1 FROM execution_leases WHERE expires_at > ?',
                variables: [
                  Variable.withInt(DateTime.now().millisecondsSinceEpoch),
                ],
              )
              .get())
          .isNotEmpty;
  Future<void> recover({DateTime? now}) => database.transaction(() async {
    final time = now ?? DateTime.now();
    // Take the writer lock first so recovery cannot race an acquisition/renewal.
    await database.customStatement(
      'DELETE FROM execution_leases WHERE expires_at <= ?',
      [time.millisecondsSinceEpoch],
    );
    final leases = await database
        .customSelect('SELECT owner FROM execution_leases')
        .get();
    final owners = leases.map((r) => r.read<String>('owner')).toSet();
    for (final run in await runs(statuses: [AutomationStatus.running])) {
      if (!owners.contains('automation:${run.id}')) {
        await saveRun(
          run.copyWith(
            status: AutomationStatus.waiting,
            reason: 'interrupted',
            waitingAt: time,
          ),
        );
      }
    }
  });
}
