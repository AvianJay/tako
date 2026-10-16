import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/automation/automation.dart';
import 'package:tako/core/chat/conversation.dart';
import 'package:tako/data/automation_repository.dart';
import 'package:tako/data/chat_repository.dart';
import 'package:tako/data/database.dart';

AutomationRule rule({
  String id = 'rule',
  AutomationBatch batch = AutomationBatch.immediate,
  AutomationTrigger trigger = AutomationTrigger.notification,
  AutomationSchedule schedule = const AutomationSchedule(),
}) => AutomationRule(
  id: id,
  name: '班群',
  prompt: 'Summarize',
  providerId: 'provider',
  model: 'model',
  enabled: true,
  trigger: trigger,
  condition: 'package == "jp.naver.line" and "班群" in title',
  batch: batch,
  schedule: schedule,
);
Map<String, Object?> event(
  String id, {
  String title = '班群',
  String package = 'jp.naver.line',
}) => {
  'id': id,
  'kind': 'notification',
  'data': {'package': package, 'title': title, 'text': id},
};

void main() {
  late AppDatabase database;
  late AutomationRepository repository;
  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = AutomationRepository(database);
  });
  tearDown(() async {
    await database.close();
  });
  test('edits preserve the existing schedule deadline', () async {
    final before = DateTime.utc(2026, 10, 16, 8);
    final original = rule(
      trigger: AutomationTrigger.schedule,
      schedule: const AutomationSchedule(
        frequency: 'interval',
        everyMinutes: 60,
      ),
    );
    await repository.saveRule(original, now: before);
    final deadline = (await repository.nextTimes())[original.id];
    await repository.saveRule(
      AutomationRule.fromJson({...original.toJson(), 'name': 'Renamed'}),
      now: before.add(const Duration(minutes: 40)),
    );
    expect((await repository.nextTimes())[original.id], deadline);
  });
  test('history is bounded on reads without hiding old active work', () async {
    final now = DateTime.now();
    for (var i = 0; i < 105; i++) {
      final run = await repository.enqueue(
        rule(),
        due: now.subtract(Duration(minutes: i)),
      );
      await repository.saveRun(
        run.copyWith(status: AutomationStatus.completed),
      );
    }
    final active = await repository.enqueue(
      rule(),
      due: now.subtract(const Duration(days: 1)),
    );
    expect(await repository.recentRuns(), hasLength(101));
    expect(
      (await repository.recentRuns()).any((r) => r.id == active.id),
      isTrue,
    );
  });
  test(
    'history cleanup keeps resumable, continuing and open conversations',
    () async {
      final chats = ChatRepository(database), now = DateTime.now();
      for (final id in [
        'orphan',
        'continued',
        'waiting',
        'open',
        'captured-context',
      ]) {
        await chats.createConversation(
          Conversation(
            id: id,
            systemPrompt: 'Fixture',
            automationRuleId: 'rule',
            createdAt: now,
            updatedAt: now,
          ),
        );
        final run = await repository.enqueue(rule(id: id));
        await repository.saveRun(
          run.copyWith(
            conversationId: id,
            status: id == 'waiting'
                ? AutomationStatus.waiting
                : AutomationStatus.completed,
          ),
        );
      }
      await repository.saveRule(
        AutomationRule.fromJson({
          ...rule().toJson(),
          'continueConversation': true,
          'conversationId': 'continued',
        }),
      );
      await repository.enqueue(
        AutomationRule.fromJson({
          ...rule(id: 'edited-rule').toJson(),
          'continueConversation': true,
          'conversationId': 'captured-context',
        }),
      );
      expect(await repository.clearHistory(openConversationId: 'open'), [
        'orphan',
      ]);
      final remaining = await repository.runs();
      expect(remaining, hasLength(2));
      expect(
        remaining.map((r) => r.status),
        containsAll([AutomationStatus.waiting, AutomationStatus.queued]),
      );
    },
  );
  test(
    'wake metadata includes startup lease expiry and waiting timeouts',
    () async {
      final now = DateTime.now().toUtc();
      final run = await repository.enqueue(rule());
      await repository.saveRun(run.copyWith(status: AutomationStatus.running));
      await repository.acquire('automation:${run.id}', now: now);
      expect(
        await repository.nextWake(),
        DateTime.fromMillisecondsSinceEpoch(
          now.millisecondsSinceEpoch + 45000,
          isUtc: true,
        ),
      );
      await repository.release('automation:${run.id}');
      final waiting = AutomationRun.fromJson({
        ...run.toJson(),
        'status': 'waiting',
        'waitingAt': now.toIso8601String(),
        'rule': {...run.rule.toJson(), 'waitTimeoutMinutes': 10},
      });
      await repository.saveRun(waiting);
      final deadline = now.add(const Duration(minutes: 10));
      final wake = await repository.nextWake();
      expect(wake!.isBefore(deadline), isFalse);
      expect(wake.difference(deadline).inMilliseconds, lessThanOrEqualTo(1000));
    },
  );
  test(
    'ingest is idempotent and only matching enabled rules receive events',
    () async {
      await repository.saveRule(rule());
      await repository.saveRule(rule(id: 'disabled').copyWith(enabled: false));
      await repository.ingest([
        event('one'),
        event('other', package: 'other'),
        event('no', title: 'work'),
      ]);
      await repository.ingest([event('one')]);
      final runs = await repository.runs();
      expect(runs, hasLength(1));
      expect(runs.single.inputs.single['text'], 'one');
    },
  );
  test('fixed window collects once and keeps the first deadline', () async {
    await repository.saveRule(rule(batch: AutomationBatch.window));
    final now = DateTime.utc(2026, 10, 16, 10);
    await repository.ingest([event('one')], now: now);
    await repository.ingest([
      event('two'),
    ], now: now.add(const Duration(seconds: 40)));
    final run = (await repository.runs()).single;
    expect(run.inputs, hasLength(2));
    expect(run.dueAt, now.add(const Duration(minutes: 1)));
    await repository.saveRun(run.copyWith(status: AutomationStatus.running));
    await repository.ingest([event('three')]);
    expect(await repository.runs(), hasLength(2));
  });
  test(
    'scheduled digest skips empty input and coalesces missed occurrences',
    () async {
      final before = DateTime(2026, 10, 15, 19);
      await repository.saveRule(
        rule(batch: AutomationBatch.scheduled),
        now: before,
      );
      await repository.ingest([], now: DateTime(2026, 10, 15, 21));
      expect(await repository.runs(), isEmpty);
      await repository.ingest([
        event('one'),
        event('two'),
      ], now: DateTime(2026, 10, 16, 19));
      expect(await repository.runs(), isEmpty);
      await repository.ingest([], now: DateTime(2026, 10, 19, 22));
      expect(await repository.runs(), hasLength(1));
      expect((await repository.runs()).single.inputs, hasLength(2));
      await repository.ingest([], now: DateTime(2026, 10, 19, 22));
      expect(await repository.runs(), hasLength(1));
    },
  );
  test('shortcut events validate enabled source and revision', () async {
    await repository.saveRule(rule(trigger: AutomationTrigger.shortcut));
    await repository.ingest([
      {'id': 'wrong', 'kind': 'shortcut', 'ruleId': 'rule', 'revision': 99},
      {
        'id': 'right',
        'kind': 'shortcut',
        'ruleId': 'rule',
        'revision': 1,
        'data': {'text': 'hello'},
      },
    ]);
    expect((await repository.runs()).single.inputs.single['text'], 'hello');
  });
  test(
    'disabling cancels pending work; edits preserve captured snapshots',
    () async {
      final first = rule();
      await repository.saveRule(first);
      await repository.ingest([event('one')]);
      await repository.saveRule(
        AutomationRule.fromJson({
          ...first.toJson(),
          'prompt': 'Changed',
          'revision': 2,
        }),
      );
      expect((await repository.runs()).single.rule.prompt, 'Summarize');
      await repository.saveRule(first.copyWith(enabled: false));
      expect(
        (await repository.runs()).single.status,
        AutomationStatus.cancelled,
      );
    },
  );
  test(
    'leases protect active work and interrupted runs become reviewable',
    () async {
      final run = await repository.enqueue(rule());
      await repository.saveRun(run.copyWith(status: AutomationStatus.running));
      expect(await repository.acquire('automation:${run.id}'), isTrue);
      expect(await repository.acquire('chat'), isFalse);
      await repository.recover();
      expect((await repository.runs()).single.status, AutomationStatus.running);
      await repository.release('automation:${run.id}');
      await repository.recover();
      expect((await repository.runs()).single.status, AutomationStatus.waiting);
    },
  );
  test('recovery retries after the startup lease expires', () async {
    final start = DateTime.utc(2026, 10, 16);
    final run = await repository.enqueue(rule());
    await repository.saveRun(run.copyWith(status: AutomationStatus.running));
    await repository.acquire('automation:${run.id}', now: start);
    await repository.recover(now: start.add(const Duration(seconds: 10)));
    expect((await repository.run(run.id))!.status, AutomationStatus.running);
    await repository.recover(now: start.add(const Duration(seconds: 45)));
    final recovered = (await repository.run(run.id))!;
    expect(recovered.status, AutomationStatus.waiting);
    expect(recovered.reason, 'interrupted');
  });
  test(
    'a clock event catches up a missed one-shot before recomputing time',
    () async {
      final before = DateTime.utc(2026, 10, 16, 8);
      await repository.saveRule(
        rule(
          trigger: AutomationTrigger.schedule,
          schedule: AutomationSchedule(
            frequency: 'once',
            at: before.add(const Duration(hours: 1)),
          ),
        ),
        now: before,
      );
      await repository.ingest([
        {'id': 'clock', 'kind': 'clock'},
      ], now: before.add(const Duration(hours: 2)));
      expect(await repository.runs(), hasLength(1));
      await repository.ingest([], now: before.add(const Duration(hours: 3)));
      expect(await repository.runs(), hasLength(1));
    },
  );
  test('waiting timeout survives restart and terminal states are explicit', () {
    final start = DateTime.utc(2026, 10, 16);
    final run = AutomationRun(
      id: 'run',
      rule: AutomationRule.fromJson({
        ...rule().toJson(),
        'waitTimeoutMinutes': 5,
      }),
      status: AutomationStatus.waiting,
      createdAt: start,
      dueAt: start,
      waitingAt: start,
    );
    final restored = AutomationRun.fromJson(run.toJson());
    expect(restored.expired(start.add(const Duration(minutes: 4))), isFalse);
    expect(restored.expired(start.add(const Duration(minutes: 5))), isTrue);
    expect(
      restored.copyWith(status: AutomationStatus.timedOut).terminal,
      isTrue,
    );
  });
  test(
    'v3 upgrade preserves settings and installs automation tables',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tako-automation-migration-',
      );
      final file = File('${directory.path}/fixture.sqlite');
      final first = AppDatabase(NativeDatabase(file));
      await first.customStatement(
        "INSERT INTO setting_records(key,value) VALUES('theme','dark')",
      );
      for (final table in [
        'automation_rules',
        'automation_inputs',
        'automation_runs',
        'automation_events',
        'execution_leases',
      ]) {
        await first.customStatement('DROP TABLE $table');
      }
      await first.customStatement('PRAGMA user_version=3');
      await first.close();
      final upgraded = AppDatabase(NativeDatabase(file));
      expect(
        (await upgraded.select(upgraded.settingRecords).getSingle()).value,
        'dark',
      );
      await AutomationRepository(upgraded).saveRule(rule());
      expect(await AutomationRepository(upgraded).rules(), hasLength(1));
      await upgraded.close();
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final artifact = File('${file.path}$suffix');
        if (await artifact.exists()) await artifact.delete();
      }
      await directory.delete();
    },
  );
  test('large notification batches split without dropping any input', () async {
    await repository.saveRule(rule(batch: AutomationBatch.window));
    await repository.ingest([for (var i = 0; i < 120; i++) event('event-$i')]);
    final batches = await repository.runs();
    expect(batches, hasLength(3));
    expect(batches.expand((r) => r.inputs).length, 120);
    expect(batches.every((r) => r.inputs.length <= 50), isTrue);
  });
  test('captured events cannot activate a new or newly edited rule', () async {
    await repository.saveRule(rule().copyWith(revision: 2));
    await repository.saveRule(rule(id: 'new-rule'));
    await repository.ingest([
      {
        ...event('old'),
        'ruleRevisions': {'rule': 1},
      },
    ]);
    expect(await repository.runs(), isEmpty);
    await repository.ingest([
      {
        ...event('new'),
        'ruleRevisions': {'rule': 2, 'new-rule': 1},
      },
    ]);
    expect(await repository.runs(), hasLength(2));
  });
  test(
    'events received after the first window form a separate batch',
    () async {
      await repository.saveRule(rule(batch: AutomationBatch.window));
      final now = DateTime.utc(2026, 10, 16, 10);
      await repository.ingest([
        {...event('one'), 'receivedAt': now.millisecondsSinceEpoch},
        {
          ...event('two'),
          'receivedAt': now
              .add(const Duration(seconds: 90))
              .millisecondsSinceEpoch,
        },
      ], now: now.add(const Duration(minutes: 2)));
      expect(await repository.runs(), hasLength(2));
    },
  );
  test(
    'precise schedules wait for access instead of silently falling back',
    () async {
      final at = DateTime(2026, 10, 16, 9);
      await repository.saveRule(
        rule(
          trigger: AutomationTrigger.schedule,
          schedule: const AutomationSchedule(hour: 10, exact: true),
        ),
        now: at,
      );
      await repository.ingest(
        [],
        now: at.add(const Duration(hours: 2)),
        allowExact: false,
      );
      expect(await repository.runs(), isEmpty);
      await repository.ingest(
        [],
        now: at.add(const Duration(hours: 2)),
        allowExact: true,
      );
      expect(await repository.runs(), hasLength(1));
    },
  );
}
