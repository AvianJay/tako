import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/app/app_controller.dart';
import 'package:tako/core/automation/automation.dart';
import 'package:tako/core/automation/automation_capability.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/conversation.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/permissions/permission_gate.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/core/tools/automation_tools.dart';
import 'package:tako/core/tools/tool.dart';
import 'package:tako/data/database.dart';
import 'package:tako/platform/capabilities.dart';

import '../app/app_controller_test.dart' as fixtures;

class _Automation extends UnavailableAutomation {
  final alerts = <String>[];
  final cleared = <String>[];
  int syncs = 0;
  @override
  Future<void> syncRules(
    List<AutomationRule> rules,
    Map<String, DateTime> next,
  ) async {
    syncs++;
  }

  @override
  Future<void> clearNotification(String id) async {
    cleared.add(id);
  }

  @override
  bool get isAvailable => true;
  @override
  bool get notificationTriggers => true;
  @override
  Future<Map<String, Object?>> status() async => {
    'canPost': true,
    'exact': true,
  };
  @override
  Future<void> notify(
    String id,
    String title,
    String body, {
    bool waiting = false,
  }) async {
    alerts.add(waiting ? 'waiting' : body);
  }
}

class _Services extends fixtures.FakeServices {
  final capability = _Automation();
  @override
  AutomationCapability get automation => capability;
}

class _Adapter implements ProviderAdapter {
  _Adapter(this.turns);
  final List<List<ProviderEvent>> turns;
  final requests = <ChatRequest>[];
  @override
  Future<List<ModelInfo>> listModels({CancelToken? cancel}) async => [];
  @override
  Stream<ProviderEvent> send(
    ChatRequest request, {
    required CancelToken cancel,
  }) async* {
    final next = turns[requests.length];
    requests.add(request);
    for (final event in next) {
      cancel.throwIfCancelled();
      yield event;
    }
  }
}

class _Tool implements Tool {
  final counts = <String, int>{};
  @override
  String get name => 'fixture_tool';
  @override
  String get description => 'Fixture operation';
  @override
  Capability get requires => const _Available();
  @override
  Map<String, Object?> get schema => {
    'type': 'object',
    'properties': {
      'operation': {'type': 'string'},
    },
    'required': ['operation'],
  };
  @override
  RiskLevel riskFor(Map<String, Object?> args, ToolContext context) =>
      args['operation'] == 'first' ? RiskLevel.safe : RiskLevel.high;
  @override
  Future<ToolResult> run(Map<String, Object?> args, ToolContext ctx) async {
    final value = args['operation']! as String;
    counts.update(value, (n) => n + 1, ifAbsent: () => 1);
    return const ToolResult(content: 'completed');
  }
}

class _Available implements Capability {
  const _Available();
  @override
  bool get isAvailable => true;
}

class _HeldAdapter extends _Adapter {
  _HeldAdapter() : super([]);
  final started = Completer<void>();
  final reply = Completer<void>();
  @override
  Stream<ProviderEvent> send(
    ChatRequest request, {
    required CancelToken cancel,
  }) async* {
    requests.add(request);
    started.complete();
    await cancel.bind(reply.future);
    yield const TextDelta('Must not notify after cancellation');
    yield const Done('stop');
  }
}

class _ReplayTool implements Tool {
  int executions = 0;
  @override
  String get name => 'js_repl';
  @override
  String get description => 'Detect an unsafe replay';
  @override
  Capability get requires => const _Available();
  @override
  Map<String, Object?> get schema => {
    'type': 'object',
    'properties': {
      'code': {'type': 'string'},
    },
    'required': ['code'],
  };
  @override
  RiskLevel riskFor(Map<String, Object?> args, ToolContext ctx) =>
      RiskLevel.safe;
  @override
  Future<ToolResult> run(Map<String, Object?> args, ToolContext ctx) async {
    executions++;
    return const ToolResult(content: 'replayed');
  }
}

List<ProviderEvent> calls() => [
  for (final op in ['first', 'second']) ...[
    ToolCallStart(op, 'fixture_tool'),
    ToolCallArgsDelta(op, jsonEncode({'operation': op})),
    ToolCallEnd(op),
  ],
  const Done('tool_calls'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<(AppController, _Services)> setup(
    _Adapter adapter, {
    Tool? tool,
  }) async {
    final services = _Services();
    final database = AppDatabase(NativeDatabase.memory());
    final app = AppController(
      database: database,
      services: services,
      promptTemplate: 'Fixture',
      bindControls: false,
      adapterFactory: (_, _, _) => adapter,
      extraTools: [?tool],
    );
    await app.initialize(automationWorker: true);
    await app.saveProvider(
      fixtures.config().copyWith(
        capabilities: const ProviderCapabilities(
          tools: true,
          contextWindow: 32768,
        ),
      ),
    );
    await app.automation.initialize(background: true);
    addTearDown(() async {
      app.automation.dispose();
      app.dispose();
      await database.close();
    });
    return (app, services);
  }

  Future<AutomationRun> queue(
    AppController app, {
    bool continuation = false,
  }) async {
    await app.automation.saveRule(
      AutomationRule(
        id: 'rule',
        name: 'Fixture automation',
        prompt: 'Summarize the input',
        providerId: 'local',
        model: 'model-1',
        enabled: true,
        continueConversation: continuation,
      ),
    );
    return app.automation.runRule('rule');
  }

  test('idle drains do not resynchronize unchanged native rules', () async {
    final (app, services) = await setup(_Adapter([]));
    final syncs = services.capability.syncs;
    await app.automation.drain();
    await app.automation.drain();
    expect(services.capability.syncs, syncs);
  });

  test(
    'an old notification can still open a run outside the recent history limit',
    () async {
      final (app, _) = await setup(_Adapter([]));
      final original = await queue(app);
      await app.automation.repository.saveRun(
        original.copyWith(status: AutomationStatus.completed),
      );
      for (var i = 1; i <= 101; i++) {
        await app.automation.repository.saveRun(
          AutomationRun.fromJson({
            ...original.toJson(),
            'id': 'newer-$i',
            'status': 'completed',
            'dueAt': original.dueAt.add(Duration(seconds: i)).toIso8601String(),
          }),
        );
      }
      await app.automation.refresh();
      expect(app.automation.runs.any((r) => r.id == original.id), isFalse);
      await app.automation.watchRun(original.id);
      await app.automation.refresh();
      expect(app.automation.runs.any((r) => r.id == original.id), isTrue);
      app.automation.unwatchRun(original.id);
      await app.automation.refresh();
      expect(app.automation.runs.any((r) => r.id == original.id), isFalse);
    },
  );

  test('automation leaves an open incognito chat usable', () async {
    final adapter = _Adapter([
      const [TextDelta('Private reply'), Done('stop')],
      const [TextDelta('[SILENT]'), Done('stop')],
      const [TextDelta('Still private'), Done('stop')],
    ]);
    final (app, _) = await setup(adapter);
    await app.newChat(incognito: true);
    await app.send('Private request');
    final id = app.conversation!.id;
    final before = await app.chats.getMessages(id);
    await queue(app);
    await app.automation.drain();
    expect((await app.chats.getConversation(id))?.incognito, isTrue);
    expect(await app.chats.getMessages(id), hasLength(before.length));
    await app.send('Continue private request');
    expect(app.conversation!.id, id);
    expect(app.visibleMessages.last.text, 'Still private');
  });

  test(
    'opening and refreshing a continued automation preserves its instructions',
    () async {
      final adapter = _Adapter([
        const [TextDelta('First'), Done('stop')],
        const [TextDelta('[SILENT]'), Done('stop')],
      ]);
      final (app, services) = await setup(adapter);
      final first = await queue(app, continuation: true);
      await app.automation.drain();
      final id = (await app.automation.repository.run(
        first.id,
      ))!.conversationId!;
      final original = (await app.chats.getConversation(id))!;
      // Also repair conversations made before automation used the shared builder.
      await app.chats.saveConversation(
        Conversation.fromJson({
          ...original.toJson(),
          'promptConfigKey': null,
          'systemPrompt': 'Old prompt',
        }),
      );
      await app.openConversation(id);
      expect(app.conversation!.systemPrompt, contains('untrusted data'));
      expect(app.conversation!.systemPrompt, contains('exactly [SILENT]'));
      expect(app.conversation!.promptConfigKey, isNotNull);
      await app.automation.runRule('rule');
      await app.automation.drain();
      expect(adapter.requests.last.systemPrompt, contains('untrusted data'));
      expect(adapter.requests.last.systemPrompt, contains('exactly [SILENT]'));
      expect(services.capability.alerts, ['First']);
    },
  );

  test('AI rule patches preserve omitted fields and pending runs', () async {
    final (app, _) = await setup(_Adapter([]));
    final saved = await app.automation.saveRule(
      const AutomationRule(
        id: 'patch',
        name: 'Original',
        prompt: 'Keep prompt',
        providerId: 'local',
        model: 'model-1',
        enabled: true,
        trigger: AutomationTrigger.notification,
        condition: 'package == "example"',
        batch: AutomationBatch.scheduled,
        windowSeconds: 123,
        schedule: AutomationSchedule(hour: 8, minute: 30),
        continueConversation: true,
        waitTimeoutMinutes: 10,
      ),
    );
    final pending = await app.automation.repository.enqueue(saved);
    final tool = createAutomationTools(
      app.automation,
    ).firstWhere((t) => t.name == 'automation_save');
    final result = await tool.run(
      {
        'id': 'patch',
        'name': 'Renamed',
        'schedule': {'minute': 45},
      },
      ToolContext(
        conversationId: 'chat',
        messageId: 'edit',
        cancel: CancelToken(),
      ),
    );
    expect(result.isError, isFalse);
    final updated = (await app.automation.getRule('patch'))!;
    final expected = {
      ...saved.toJson(),
      'name': 'Renamed',
      'revision': saved.revision + 1,
      'schedule': {...saved.schedule.toJson(), 'minute': 45},
    };
    expect(updated.toJson(), expected);
    expect(
      (await app.automation.repository.run(pending.id))!.status,
      AutomationStatus.queued,
    );
  });

  test('resume clears the preceding waiting period before running', () async {
    final adapter = _HeldAdapter();
    final (app, _) = await setup(adapter);
    final queued = await queue(app);
    final run = queued.copyWith(
      status: AutomationStatus.waiting,
      waitingAt: DateTime.now().subtract(const Duration(minutes: 4)),
    );
    await app.automation.repository.saveRun(run);
    final work = app.automation.resume(run.id);
    await adapter.started.future;
    final running = (await app.automation.repository.run(run.id))!;
    expect(running.status, AutomationStatus.running);
    expect(running.waitingAt, isNull);
    adapter.reply.complete();
    await work;
  });

  test(
    'silent task is saved without posting a result or changing current chat',
    () async {
      final adapter = _Adapter([
        const [
          ReasoningDelta('intermediate'),
          TextDelta('[SILENT]'),
          Done('stop'),
        ],
      ]);
      final (app, services) = await setup(adapter);
      final run = await queue(app);
      await app.automation.drain();
      final finished = await app.automation.repository.run(run.id);
      expect(finished!.status, AutomationStatus.silent);
      expect(services.capability.alerts, isEmpty);
      expect(services.capability.cleared, contains(run.id));
      expect(app.conversation, isNull);
      expect(await app.chats.listConversations(), isEmpty);
      expect(adapter.requests.single.systemPrompt, contains('untrusted data'));
    },
  );
  test(
    'normal final answer posts a result and independent runs use separate conversations',
    () async {
      final adapter = _Adapter([
        const [TextDelta('First'), Done('stop')],
        const [TextDelta('Second'), Done('stop')],
      ]);
      final (app, services) = await setup(adapter);
      await queue(app);
      await app.automation.drain();
      await app.automation.runRule('rule');
      await app.automation.drain();
      expect(services.capability.alerts, ['First', 'Second']);
      final ids = (await app.automation.repository.runs())
          .map((r) => r.conversationId)
          .toSet();
      expect(ids, hasLength(2));
    },
  );
  test(
    'background approval persists prior receipts; resume never repeats completed action',
    () async {
      final tool = _Tool(),
          adapter = _Adapter([
            calls(),
            const [TextDelta('Finished'), Done('stop')],
          ]);
      final (app, services) = await setup(adapter, tool: tool);
      final run = await queue(app);
      await app.automation.drain();
      final waiting = (await app.automation.repository.run(run.id))!;
      expect(waiting.status, AutomationStatus.waiting);
      expect(waiting.reason, 'approval');
      expect(tool.counts, {'first': 1});
      expect(services.capability.alerts, ['waiting']);
      final resumed = app.automation.resume(run.id);
      for (var i = 0; i < 100 && app.pendingApproval == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(app.pendingApproval?.arguments, {'operation': 'second'});
      app.decideApproval(PermissionChoice.allowOnce);
      await resumed;
      expect(tool.counts, {'first': 1, 'second': 1});
      expect(
        (await app.automation.repository.run(run.id))!.status,
        AutomationStatus.completed,
      );
      expect(adapter.requests, hasLength(2));
    },
  );
  test(
    'continuation uses the rule conversation while keeping runs distinct',
    () async {
      final adapter = _Adapter([
        const [TextDelta('One'), Done('stop')],
        const [TextDelta('Two'), Done('stop')],
      ]);
      final (app, _) = await setup(adapter);
      await queue(app, continuation: true);
      await app.automation.drain();
      await app.automation.runRule('rule');
      await app.automation.drain();
      expect(
        (await app.automation.repository.runs())
            .map((r) => r.conversationId)
            .toSet(),
        hasLength(1),
      );
      expect(
        adapter.requests.last.messages.where((m) => m.role.name == 'user'),
        hasLength(2),
      );
    },
  );
  test(
    'an interrupted REPL program is replaced with receipts, never replayed',
    () async {
      final replay = _ReplayTool();
      final adapter = _Adapter([
        const [TextDelta('Reviewed saved operations'), Done('stop')],
      ]);
      final (app, _) = await setup(adapter, tool: replay);
      final run = await queue(app);
      final now = DateTime.now();
      await app.chats.createConversation(
        Conversation(
          id: 'recovery',
          title: 'Recovery',
          createdAt: now,
          updatedAt: now,
          systemPrompt: 'Fixture',
          automationRuleId: 'rule',
        ),
      );
      await app.chats.saveMessage(
        ChatMessage(
          id: 'input',
          conversationId: 'recovery',
          role: MessageRole.user,
          content: const [TextBlock('Fixture request')],
          createdAt: now,
          timezoneOffsetMinutes: 0,
        ),
      );
      const call = ToolCallBlock(
        id: 'outer',
        name: 'js_repl',
        arguments: '{"code":"already partially executed"}',
      );
      await app.chats.saveMessage(
        ChatMessage(
          id: 'model-response',
          conversationId: 'recovery',
          parentId: 'input',
          role: MessageRole.assistant,
          content: const [call],
          createdAt: now,
          timezoneOffsetMinutes: 0,
        ),
      );
      await app.automation.repository.saveRun(
        run.copyWith(
          conversationId: 'recovery',
          status: AutomationStatus.waiting,
          reason: 'interrupted',
          waitingAt: now,
          pending: {
            'inFlight': {
              'model-response:outer': {
                'messageId': 'model-response',
                'call': call.toJson(),
              },
            },
            'receipts': [
              {
                'messageId': 'model-response',
                'call': const ToolCallBlock(
                  id: 'inner',
                  name: 'fixture_tool',
                  arguments: '{}',
                ).toJson(),
                'result': const ToolResultBlock(
                  toolCallId: 'inner',
                  toolName: 'fixture_tool',
                  content: 'completed before interruption',
                ).toJson(),
              },
            ],
          },
        ),
      );
      await app.automation.resume(run.id);
      expect(replay.executions, 0);
      expect(adapter.requests, hasLength(1));
      final results = adapter.requests.single.messages
          .expand((m) => m.content)
          .whereType<ToolResultBlock>();
      expect(
        results.single.content,
        contains('interrupted_operation_not_replayed'),
      );
      expect(results.single.content, contains('completed before interruption'));
      expect(
        (await app.automation.repository.run(run.id))!.status,
        AutomationStatus.completed,
      );
    },
  );
  test(
    'AI-created rules can default to the current text provider and model',
    () async {
      final (app, _) = await setup(_Adapter([]));
      final saved = await app.automation.saveRule(
        const AutomationRule(
          id: 'default-model',
          name: 'Default model',
          prompt: 'Fixture',
          providerId: '',
          model: '',
        ),
      );
      expect(saved.providerId, 'local');
      expect(saved.model, 'model-1');
    },
  );
  test(
    'cancelling an active model request stays cancelled and clears its notice',
    () async {
      final adapter = _HeldAdapter();
      final (app, services) = await setup(adapter);
      final run = await queue(app);
      final work = app.automation.drain();
      await adapter.started.future;
      await app.automation.cancel(run.id);
      adapter.reply.complete();
      await work;
      expect(
        (await app.automation.repository.run(run.id))!.status,
        AutomationStatus.cancelled,
      );
      expect(services.capability.alerts, isEmpty);
      expect(services.capability.cleared, contains(run.id));
    },
  );
  for (final reason in ['paused', 'system']) {
    test(
      'native stop reason $reason preserves user pause versus system retry',
      () async {
        final adapter = _HeldAdapter();
        final (app, services) = await setup(adapter);
        final run = await queue(app);
        final work = app.automation.drain();
        await adapter.started.future;
        services.capability.onStop!(reason);
        adapter.reply.complete();
        await work;
        final stored = (await app.automation.repository.run(run.id))!;
        expect(
          stored.status,
          reason == 'paused'
              ? AutomationStatus.waiting
              : AutomationStatus.queued,
        );
        expect(stored.reason, reason);
        expect(
          services.capability.alerts,
          reason == 'paused' ? ['waiting'] : <String>[],
        );
      },
    );
  }
}
