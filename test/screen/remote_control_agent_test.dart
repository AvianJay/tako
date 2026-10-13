import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/files/workspace.dart';
import 'package:tako/core/permissions/permission_gate.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/core/screen/remote_control_agent.dart';
import 'package:tako/core/screen/screen_capability.dart';
import 'package:tako/core/tools/device_tools.dart';
import 'package:tako/core/tools/tool.dart';
import 'package:tako/core/tools/tool_executor.dart';
import 'package:tako/core/tools/tool_registry.dart';
import 'package:tako/core/util/json.dart';
import 'package:tako/data/audit_repository.dart';
import 'package:tako/data/database.dart';
import 'package:tako/platform/device_tools_capability.dart';

import 'fake_screen.dart';

class _Workspace implements WorkspaceCapability {
  @override
  bool get isAvailable => true;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Worker must not persist screenshots');
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
    final index = requests.length;
    requests.add(request);
    for (final event in turns[index]) {
      yield event;
    }
  }
}

List<ProviderEvent> call(String tool, Map<String, Object?> args) => [
  ToolCallStart('action', tool),
  ToolCallArgsDelta('action', jsonEncode(args)),
  const ToolCallEnd('action'),
  const Done('tool_use'),
];

class _Launch implements DeviceToolsCapability {
  _Launch(this.screen);
  final FakeScreen screen;
  @override
  bool get isAvailable => true;
  @override
  bool supports(String tool) => tool == 'open_app';
  @override
  Future<Map<String, Object?>> invoke(
    String tool,
    Map<String, Object?> arguments, {
    required CancelToken cancel,
  }) async {
    screen.launch(arguments['package'] as String? ?? 'com.example.fixture');
    return {'launched': true};
  }
}

class _BusyScreen extends FakeScreen {
  _BusyScreen(super.views) : super(start: 'start');
  int reads = 0;
  bool busyInitially = false;
  @override
  Future<ScreenTree> snapshot({
    required bool screenshot,
    required CancelToken cancel,
  }) {
    reads++;
    if (busyInitially) {
      throw const ScreenException(
        'ictrl_rpc_failed_read_again',
        detail:
            'page_source exceeded 15s and may still be running on the device.',
      );
    }
    return super.snapshot(screenshot: screenshot, cancel: cancel);
  }

  @override
  Future<ScreenActionOutcome> act(ScreenAction action) async {
    actions.add(action);
    throw const ScreenException(
      'ictrl_rpc_failed_read_again',
      detail: 'tap exceeded 15s and may still be running on the device.',
    );
  }
}

class _SparseScreen extends FakeScreen {
  _SparseScreen(super.views) : super(start: 'start', screenshots: true) {
    fastActions = true;
  }
  final imageAccess = <bool>[];
  @override
  Future<ScreenTree> snapshotForModel({
    required bool screenshot,
    required bool automaticScreenshot,
    required CancelToken cancel,
  }) {
    imageAccess.add(automaticScreenshot);
    return snapshot(
      screenshot: screenshot || automaticScreenshot,
      cancel: cancel,
    );
  }
}

void main() {
  late AppDatabase database;
  late FakeScreen screen;
  late PermissionGate gate;
  late _Adapter adapter;
  late RemoteControlAgent agent;
  late ToolExecutor executor;
  var disabled = <String>{};
  var limit = 20;
  final token = CancelToken();
  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    screen = FakeScreen(
      {
        'start': FakeView('com.example.fixture', 'Fixture', [
          FakeWindow(box([button('Start', opens: 'done'), button('Later')])),
        ]),
        'done': FakeView('com.example.fixture', 'Fixture', [
          FakeWindow(box([label('Done'), label('Unrelated private text')])),
        ]),
        'own': FakeView(FakeScreen.ownPackage, 'Tako', [
          FakeWindow(box([label('Private main chat')])),
        ]),
      },
      start: 'start',
      screenshots: true,
    )..fastActions = true;
    gate = PermissionGate(
      policy: const PermissionPolicy(fullPermissions: true),
    );
    disabled = {};
    limit = 20;
    adapter = _Adapter([
      call('tap', {'title': 'Start', 'id': 1, 'screenshot': true}),
    ]);
  });
  void build() {
    final audit = AuditRepository(database);
    agent = RemoteControlAgent(
      screen: screen,
      workspace: _Workspace(),
      deviceTools: (observer) =>
          createDeviceTools(_Launch(screen), observer: observer),
      permissions: gate,
      audit: audit,
      available: () => true,
      backend: () async => (
        config: ProviderConfig(
          id: 'worker',
          displayName: 'Worker',
          apiType: ApiType.messages,
          baseUrl: 'https://example.com',
          model: 'claude-haiku-5-5',
          capabilities: const ProviderCapabilities(tools: true, vision: true),
        ),
        adapter: adapter,
      ),
      screenshots: () => true,
      disabledTools: () => disabled,
      stepLimit: () => limit,
    );
    executor = ToolExecutor(
      registry: ToolRegistry(agent.tools),
      permissions: gate,
      audit: audit,
    );
  }

  Future<ToolResultBlock> run({
    List<String> expected = const ['Done'],
    String? app,
    String? query,
    String? resultKind,
    int? minResults,
    List<Map<String, Object?>>? workflow,
    CancelToken? cancel,
  }) async => (await executor.execute(
    ToolCallBlock(
      id: 'delegate',
      name: 'remote_control',
      arguments: jsonEncode({
        'title': 'Start task',
        'task': 'Start and finish',
        'success_criteria': 'Done must be visible',
        'expected_text': expected,
        'expected_app': ?app,
        'result_contains': ?query,
        'result_kind': ?resultKind,
        'min_results': ?minResults,
        'workflow': ?workflow,
      }),
    ),
    ToolContext(
      conversationId: 'chat',
      messageId: 'main-response',
      cancel: cancel ?? CancelToken(),
    ),
  )).result;
  tearDown(() async {
    screen.dispose();
    await database.close();
  });

  test(
    'bad final-text shape is corrected before contacting the worker',
    () async {
      build();
      final invalid = (await executor.execute(
        ToolCallBlock(
          id: 'bad-delegate',
          name: 'remote_control',
          arguments: jsonEncode({
            'title': 'Start task',
            'task': 'Start and finish',
            'success_criteria': 'Done must be visible',
            'expected_text': 'Done',
          }),
        ),
        ToolContext(
          conversationId: 'chat',
          messageId: 'main-response',
          cancel: CancelToken(),
        ),
      )).result;
      final error = jsonDecode(invalid.content) as Map;
      expect(error['error'], 'invalid_arguments');
      expect(error['path'], r'$.expected_text');
      expect(error['expected'], 'array');
      expect(adapter.requests, isEmpty);
      expect(screen.actions, isEmpty);
      final corrected = await run();
      final receipt = jsonDecode(corrected.content) as Map<String, Object?>;
      expect(receipt['status'], 'verified');
      expect(adapter.requests, hasLength(1));
    },
  );
  for (final fieldName in ['Search', '搜尋', 'Find products']) {
    test(
      'local search opens entry and submits $fieldName in one round',
      () async {
        screen.views['start'] = FakeView('com.example.fixture', 'Fixture', [
          FakeWindow(box([button('Search', opens: 'search')])),
        ]);
        screen.views['search'] = FakeView('com.example.fixture', 'Fixture', [
          FakeWindow(box([field(description: fieldName, submits: 'done')])),
        ]);
        adapter = _Adapter([
          call('screen_workflow', {
            'title': 'Find a stand',
            'steps': [
              {
                'tool': 'search',
                'expect_app': 'com.example.fixture',
                'text': 'foldable stand',
              },
            ],
          }),
        ]);
        build();
        final receipt = jsonDecode((await run()).content) as Map;
        expect(receipt['status'], 'verified');
        expect(adapter.requests, hasLength(1));
        expect(screen.actions.map((a) => a.action), ['tap', 'set_text']);
        expect(screen.actions.last.text, 'foldable stand');
        expect(screen.actions.last.submit, true);
      },
    );
  }
  test('local search refuses ambiguous fields without typing', () async {
    screen.views['start'] = FakeView('com.example.fixture', 'Fixture', [
      FakeWindow(
        box([field(description: 'Search A'), field(description: 'Search B')]),
      ),
    ]);
    adapter = _Adapter([
      call('screen_workflow', {
        'title': 'Search',
        'steps': [
          {
            'tool': 'search',
            'expect_app': 'com.example.fixture',
            'text': 'query',
          },
        ],
      }),
      [
        const TextDelta('Cannot finish: search fields are ambiguous.'),
        const Done('end_turn'),
      ],
      [
        const TextDelta('Not completed: search fields remain ambiguous.'),
        const Done('end_turn'),
      ],
    ]);
    build();
    final result = await run();
    expect(result.isError, true);
    expect(screen.actions, isEmpty);
    expect(
      (await AuditRepository(database).list()).any(
        (r) => r.resultSummary.contains('workflow_search_missing_or_ambiguous'),
      ),
      true,
    );
  });
  test('local search honors type deny after authorized entry tap', () async {
    screen.views['start'] = FakeView('com.example.fixture', 'Fixture', [
      FakeWindow(box([button('Search', opens: 'search')])),
    ]);
    screen.views['search'] = FakeView('com.example.fixture', 'Fixture', [
      FakeWindow(box([field(description: 'Search', submits: 'done')])),
    ]);
    gate.policy = const PermissionPolicy(
      fullPermissions: true,
      overrides: {'type_text': ToolPermission.deny},
    );
    adapter = _Adapter([
      call('screen_workflow', {
        'title': 'Search',
        'steps': [
          {
            'tool': 'search',
            'expect_app': 'com.example.fixture',
            'text': 'query',
          },
        ],
      }),
    ]);
    build();
    final result = await run();
    expect(result.isError, true);
    expect(screen.actions.map((a) => a.action), ['tap']);
    expect(adapter.requests, hasLength(1));
  });

  test(
    'native evidence ends the worker without a final model round; parent sees no raw screens',
    () async {
      build();
      final result = await run();
      final receipt = jsonDecode(result.content) as Map;
      expect(receipt['status'], 'verified');
      expect(receipt['matched_text'], ['Done']);
      expect(adapter.requests, hasLength(1));
      expect(result.attachments, isEmpty);
      expect(result.content.length, lessThan(1000));
      expect(result.content, isNot(contains('Unrelated private text')));
      expect(
        adapter.requests.single.messages.single.text,
        contains('Current screen'),
      );
      expect(
        adapter.requests.single.tools.any((t) => t.name == 'remote_control'),
        false,
      );
      expect(
        adapter.requests.single.tools.any((t) => t.name == 'file_read'),
        false,
      );
      final audited = await AuditRepository(database).list();
      expect(
        audited.map((a) => a.toolName),
        containsAll(['remote_control', 'tap', 'read_screen']),
      );
    },
  );
  test(
    'fresh check costs no model call and rejects another conversation',
    () async {
      build();
      final result = jsonDecode((await run()).content) as Map;
      screen.show('start');
      Future<ToolResultBlock> check(String chat) async =>
          (await executor.execute(
            ToolCallBlock(
              id: 'check',
              name: 'remote_control_check',
              arguments: jsonEncode({'task_id': result['task_id']}),
            ),
            ToolContext(
              conversationId: chat,
              messageId: 'check-response',
              cancel: CancelToken(),
            ),
          )).result;
      expect(
        (jsonDecode((await check('chat')).content)
            as Map<String, Object?>)['verified'],
        false,
      );
      expect(
        (await check('another-chat')).content,
        contains('unknown_remote_task'),
      );
      expect(adapter.requests, hasLength(1));
    },
  );
  test(
    'worker reasoning keeps matching request provenance across tool rounds',
    () async {
      adapter = _Adapter([
        [
          const ReasoningDelta('Choose the next action'),
          const ReasoningMetadata(
            blockIndex: 0,
            sourceApi: 'messages',
            signature: 'opaque-signature',
          ),
          ...call('read_screen', {'title': 'Inspect'}),
        ],
        call('tap', {'title': 'Start', 'id': 1}),
      ]);
      build();
      await run();
      final request = adapter.requests[1];
      final assistant = request.messages.firstWhere(
        (m) => m.content.whereType<ReasoningBlock>().isNotEmpty,
      );
      final reasoning = assistant.content.whereType<ReasoningBlock>().single;
      expect(assistant.providerId, 'worker');
      expect(assistant.model, 'claude-haiku-5-5');
      expect(reasoning.promptHash, request.promptHash);
      expect(request.promptHash, isNotNull);
      expect(reasoning.signature, 'opaque-signature');
    },
  );
  test(
    'matching search title cannot verify an uncompleted cart task',
    () async {
      screen.views['done'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(box([label('ESP32-S3 DevKit board')])),
      ]);
      adapter = _Adapter([
        call('tap', {'title': 'Inspect board', 'id': 1}),
        [
          const TextDelta('Stopped without adding to cart'),
          const Done('end_turn'),
        ],
      ]);
      build();
      final receipt =
          jsonDecode((await run(expected: [], query: 'ESP32S3')).content)
              as Map<String, Object?>;
      expect(receipt['status'], 'reported_complete');
      expect(receipt['verified'], false);
      expect(receipt['semantic_review_needed'], true);
    },
  );
  test('worker claims cannot satisfy a missing expected label', () async {
    adapter = _Adapter([
      [const TextDelta('Task completed: Done'), const Done('end_turn')],
      [const TextDelta('Task completed: Done'), const Done('end_turn')],
    ]);
    build();
    final receipt = jsonDecode((await run()).content) as Map;
    expect(receipt['verified'], false);
    expect(receipt['missing_text'], ['Done']);
    expect(receipt['status'], 'incomplete');
    expect(adapter.requests, hasLength(2));
    expect(receipt['semantic_review_needed'], true);
  });
  test(
    'unfinished navigation recovers once without treating reminders as blockers',
    () async {
      adapter = _Adapter([
        [
          const TextDelta(
            'Not completed: stuck on navigation. I did not enter passwords.',
          ),
          const Done('end_turn'),
        ],
        call('tap', {'title': 'Recover navigation', 'id': 1}),
      ]);
      build();
      final receipt = jsonDecode((await run()).content) as Map;
      expect(receipt['status'], 'verified');
      expect(receipt['verified'], true);
      expect(adapter.requests, hasLength(2));
      expect(screen.actions, hasLength(1));
      expect(
        adapter.requests[1].messages.last.content
            .whereType<TextBlock>()
            .first
            .text,
        contains('Recover within its original scope'),
      );
    },
  );
  test('concrete login and password gates do not retry navigation', () async {
    for (final note in [
      'Unable to continue: login required.',
      'A password prompt blocks this task.',
      '無法繼續：需要登入。',
    ]) {
      adapter = _Adapter([
        [TextDelta(note), const Done('end_turn')],
      ]);
      build();
      final result = await run();
      final receipt = jsonDecode(result.content) as Map;
      expect(receipt['status'], 'blocked', reason: note);
      expect(result.isError, true);
      expect(adapter.requests, hasLength(1));
      expect(screen.actions, isEmpty);
    }
  });
  test('navigation handoffs recover even without exact final labels', () async {
    for (final note in [
      'Please return to the home page and say continue.',
      'I need you to dismiss the progress banner or confirm I may use the back gesture.',
      '請先回到首頁，再跟我說「繼續」。',
      "I haven't reached the free wheel yet. Next I'd tap the back arrow. No spin has been performed.",
    ]) {
      adapter = _Adapter([
        [TextDelta(note), const Done('end_turn')],
        call('tap', {'title': 'Recover navigation', 'id': 1}),
        [const TextDelta('Done is visible.'), const Done('end_turn')],
      ]);
      build();
      final receipt = jsonDecode((await run(expected: [])).content) as Map;
      expect(receipt['status'], 'reported_complete', reason: note);
      expect(receipt['recovery_attempts'], 1);
      expect(adapter.requests, hasLength(3));
      final recovery = adapter.requests[1].messages.last.content;
      expect(recovery.whereType<ImageBlock>(), hasLength(1));
      expect(
        recovery.whereType<TextBlock>().first.text,
        contains('already authorized'),
      );
      expect(
        adapter.requests.first.systemPrompt,
        contains('Full permissions enabled'),
      );
      screen.show('start');
      screen.actions.clear();
    }
  });
  test('an uncertain spin outcome is not retried as navigation', () async {
    adapter = _Adapter([
      [
        const TextDelta(
          'Cannot confirm the spin outcome. Please return to the home page and say continue.',
        ),
        const Done('end_turn'),
      ],
    ]);
    build();
    final receipt = jsonDecode((await run(expected: [])).content) as Map;
    expect(receipt['status'], 'incomplete');
    expect(receipt['reason'], 'worker_mutation_outcome_uncertain');
    expect(receipt['recovery_attempts'], 0);
    expect(adapter.requests, hasLength(1));
    expect(screen.actions, isEmpty);
  });
  test(
    'a workflow image reaches the worker without another read round',
    () async {
      adapter = _Adapter([
        [const TextDelta('Start is visible.'), const Done('end_turn')],
      ]);
      build();
      final result = await run(
        expected: [],
        workflow: [
          {
            'tool': 'open_app',
            'package': 'com.example.fixture',
            'screenshot': true,
          },
        ],
      );
      expect(adapter.requests, hasLength(1));
      expect(
        adapter.requests.single.messages.single.content.whereType<ImageBlock>(),
        hasLength(1),
      );
      expect((jsonDecode(result.content) as Map)['steps'], 2);
    },
  );
  test('final native verification does not request automatic images', () async {
    final sparse = _SparseScreen(screen.views);
    screen = sparse;
    adapter = _Adapter([
      call('tap', {'title': 'Start', 'id': 1}),
    ]);
    build();
    final receipt = tryDecodeObject((await run()).content)!;
    expect(receipt['verified'], true);
    expect(sparse.imageAccess, [true, true, false]);
    expect(adapter.requests, hasLength(1));
    expect(screen.actions, hasLength(1));
  });
  test(
    'a partial launch plan never polls for criteria before worker actions',
    () async {
      build();
      final result = await run(
        workflow: [
          {'tool': 'open_app', 'package': 'com.example.fixture'},
        ],
      );
      expect(tryDecodeObject(result.content)!['status'], 'verified');
      final records = await AuditRepository(database).list();
      expect(records.where((r) => r.toolName == 'read_screen'), hasLength(1));
      expect(adapter.requests, hasLength(1));
    },
  );
  test('unfinished recovery is bounded to one attempt', () async {
    adapter = _Adapter([
      [const TextDelta('Not completed: stuck'), const Done('end_turn')],
      [const TextDelta('Not completed: stuck'), const Done('end_turn')],
    ]);
    build();
    final result = await run();
    final receipt = jsonDecode(result.content) as Map;
    expect(result.isError, true);
    expect(receipt['status'], 'incomplete');
    expect(receipt['reason'], 'worker_reported_incomplete');
    expect(adapter.requests, hasLength(2));
    expect(screen.actions, isEmpty);
  });
  test(
    'verification matches a value separately from its accessibility label',
    () async {
      screen.views['done'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(
          box([
            FakeNode(
              'android.widget.TextView',
              text: '15',
              description: 'Current expression',
            ),
          ]),
        ),
      ]);
      build();
      final receipt =
          jsonDecode((await run(expected: const ['15'])).content) as Map;
      expect(receipt['status'], 'verified');
      expect(receipt['matched_text'], ['15']);
    },
  );
  test(
    'local workflow navigates from fresh labels without model calls',
    () async {
      build();
      final receipt =
          jsonDecode(
                (await run(
                  workflow: [
                    {
                      'tool': 'tap',
                      'label': 'Start',
                      'expect_app': 'com.example.fixture',
                      'expect_text': 'Done',
                    },
                  ],
                )).content,
              )
              as Map<String, Object?>;
      expect(receipt['status'], 'verified');
      expect(receipt['model_rounds'], 0);
      expect(adapter.requests, isEmpty);
      expect(screen.actions, hasLength(1));
    },
  );
  test(
    'nested back navigation executes locally with fresh ids and exact destination',
    () async {
      screen.views['start'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(
          box([label('Detail'), icon(viewId: 'BackButton', opens: 'middle')]),
        ),
      ]);
      screen.views['middle'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(
          box([label('Category'), icon(viewId: 'BackButton', opens: 'root')]),
        ),
      ]);
      screen.views['root'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(box([button('Start', opens: 'done')])),
      ]);
      build();
      final receipt = tryDecodeObject(
        (await run(
          workflow: [
            {
              'tool': 'back',
              'expect_app': 'com.example.fixture',
              'until_label': 'Start',
              'max_back': 4,
            },
            {
              'tool': 'tap',
              'label': 'Start',
              'expect_app': 'com.example.fixture',
            },
          ],
        )).content,
      )!;
      expect(receipt['status'], 'verified');
      expect(receipt['model_rounds'], 0);
      expect(screen.actions, hasLength(3));
      expect(
        (await AuditRepository(
          database,
        ).list()).where((r) => r.toolName == 'tap'),
        hasLength(3),
      );
    },
  );
  for (final workflow in [false, true]) {
    test(
      'busy UI stops ${workflow ? 'workflow' : 'worker'} without another call',
      () async {
        final busy = _BusyScreen(screen.views);
        screen = busy;
        adapter = _Adapter([
          [
            ...call('tap', {
              'title': 'Start',
              'id': 1,
            }).where((e) => e is! Done),
            const ToolCallStart('second', 'read_screen'),
            const ToolCallArgsDelta('second', '{"title":"Read again"}'),
            const ToolCallEnd('second'),
            const Done('tool_use'),
          ],
        ]);
        build();
        final receipt = tryDecodeObject(
          (await run(
            workflow: workflow
                ? [
                    {
                      'tool': 'tap',
                      'label': 'Start',
                      'expect_app': 'com.example.fixture',
                    },
                  ]
                : null,
          )).content,
        )!;
        expect(receipt['status'], 'blocked');
        expect(receipt['reason'], 'device_ui_busy');
        expect(receipt['recovery_attempts'], 0);
        expect(busy.reads, 1);
        expect(busy.actions, hasLength(1));
        expect(adapter.requests, hasLength(workflow ? 0 : 1));
      },
    );
  }
  test(
    'busy initial observation never calls the worker or a final read',
    () async {
      final busy = _BusyScreen(screen.views)..busyInitially = true;
      screen = busy;
      build();
      final receipt = tryDecodeObject((await run()).content)!;
      expect(receipt['status'], 'blocked');
      expect(receipt['reason'], 'device_ui_busy');
      expect(busy.reads, 1);
      expect(busy.actions, isEmpty);
      expect(adapter.requests, isEmpty);
    },
  );
  test(
    'failed selector returns a fresh image without retrying the action',
    () async {
      adapter = _Adapter([
        call('tap', {'title': 'Unknown target', 'id': 999}),
        call('tap', {'title': 'Start', 'id': 1}),
      ]);
      build();
      final receipt = tryDecodeObject((await run()).content)!;
      expect(receipt['status'], 'verified');
      expect(receipt['observation_recoveries'], 1);
      expect(adapter.requests, hasLength(2));
      expect(screen.actions, hasLength(1));
      final fresh = adapter.requests[1].messages.last.content;
      expect(fresh.whereType<ImageBlock>(), hasLength(1));
      expect(fresh.whereType<TextBlock>().first.text, contains('not retried'));
      expect(fresh.whereType<TextBlock>().last.text, contains('Start'));
    },
  );
  test('ambiguous workflow returns a fresh image for replanning', () async {
    adapter = _Adapter([
      call('screen_workflow', {
        'title': 'Find route',
        'steps': [
          {
            'tool': 'tap',
            'label': 'Missing',
            'expect_app': 'com.example.fixture',
          },
        ],
      }),
      call('tap', {'title': 'Start', 'id': 1}),
    ]);
    build();
    final receipt = tryDecodeObject((await run()).content)!;
    expect(receipt['status'], 'verified');
    expect(receipt['observation_recoveries'], 1);
    expect(adapter.requests, hasLength(2));
    expect(screen.actions, hasLength(1));
    expect(
      adapter.requests[1].messages.last.content.whereType<ImageBlock>(),
      hasLength(1),
    );
  });
  test(
    'back workflow never repeats a tap when its page remains unchanged',
    () async {
      screen.views['start'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(box([icon(viewId: 'BackButton')])),
      ]);
      adapter = _Adapter([
        [
          const TextDelta('Navigation blocked by unchanged page.'),
          const Done('end_turn'),
        ],
      ]);
      build();
      await run(
        expected: [],
        workflow: [
          {'tool': 'back', 'expect_app': 'com.example.fixture', 'max_back': 4},
        ],
      );
      expect(screen.actions, hasLength(1));
      final records = await AuditRepository(database).list();
      expect(
        records
            .firstWhere((r) => r.toolName == 'screen_workflow')
            .resultSummary,
        contains('workflow_back_unchanged'),
      );
    },
  );
  test(
    'nested row and button are one selector; sibling duplicates remain ambiguous',
    () async {
      screen.views['start'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(
          box([
            row([button('Start', opens: 'done')], opens: 'done'),
          ]),
        ),
      ]);
      build();
      final result = await run(
        workflow: [
          {
            'tool': 'tap',
            'label': 'Start',
            'expect_app': 'com.example.fixture',
          },
        ],
      );
      expect(tryDecodeObject(result.content)!['model_rounds'], 0);
      expect(screen.actions, hasLength(1));
    },
  );
  test(
    'workflow resolves an app name locally before worker planning',
    () async {
      build();
      final result = await run(
        expected: [],
        workflow: [
          {'tool': 'open_app', 'name': 'Fixture'},
        ],
      );
      expect(tryDecodeObject(result.content)!['workflow_used'], true);
      final records = await AuditRepository(database).list();
      final launch = records.where((r) => r.toolName == 'open_app').single;
      expect(tryDecodeObject(launch.arguments)!['name'], 'Fixture');
      expect(tryDecodeObject(launch.arguments)!.containsKey('package'), false);
    },
  );
  test(
    'native image ID workflow finishes without a worker model call',
    () async {
      screen.views['start'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(
          box([
            FakeNode(
              'Image',
              viewId: 'ic_search_cart',
              opens: 'done',
              bounds: const ScreenBounds(360, 70, 384, 94),
            ),
          ]),
        ),
      ]);
      build();
      final receipt =
          jsonDecode(
                (await run(
                  workflow: [
                    {
                      'tool': 'tap',
                      'view_id': 'ic_search_cart',
                      'expect_app': 'com.example.fixture',
                      'expect_text': 'Done',
                    },
                  ],
                )).content,
              )
              as Map;
      expect(receipt['status'], 'verified');
      expect(receipt['model_rounds'], 0);
      expect(adapter.requests, isEmpty);
      expect(screen.actions, hasLength(1));
    },
  );
  test(
    'worker workflow can finish with native proof without a second model turn',
    () async {
      adapter = _Adapter([
        call('screen_workflow', {
          'title': 'Complete navigation',
          'steps': [
            {
              'tool': 'tap',
              'label': 'Start',
              'expect_app': 'com.example.fixture',
              'expect_text': 'Done',
            },
          ],
        }),
      ]);
      build();
      final receipt = jsonDecode((await run()).content) as Map;
      expect(receipt['verified'], true);
      expect(receipt['workflow_used'], true);
      expect(receipt['model_rounds'], 1);
      expect(adapter.requests, hasLength(1));
    },
  );
  test(
    'workflow selects the control over the same page title and uses fresh ids between steps',
    () async {
      screen.views['start'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(box([label('Start'), button('Start', opens: 'middle')])),
      ]);
      screen.views['middle'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(box([button('Finish', opens: 'done')])),
      ]);
      build();
      final receipt =
          jsonDecode(
                (await run(
                  workflow: [
                    {
                      'tool': 'tap',
                      'label': 'Start',
                      'expect_app': 'com.example.fixture',
                    },
                    {
                      'tool': 'tap',
                      'label': 'Finish',
                      'expect_app': 'com.example.fixture',
                    },
                  ],
                )).content,
              )
              as Map;
      expect(receipt['verified'], true);
      expect(receipt['model_rounds'], 0);
      expect(screen.actions, hasLength(2));
      expect(adapter.requests, isEmpty);
    },
  );
  test(
    'a workflow mismatch hands off its current screen without replaying steps',
    () async {
      adapter = _Adapter([
        [const TextDelta('Done is visible'), const Done('end_turn')],
      ]);
      build();
      final receipt =
          jsonDecode(
                (await run(
                  workflow: [
                    {
                      'tool': 'tap',
                      'label': 'Start',
                      'expect_app': 'com.example.fixture',
                    },
                    {
                      'tool': 'tap',
                      'label': 'No longer here',
                      'expect_app': 'com.example.fixture',
                    },
                  ],
                )).content,
              )
              as Map<String, Object?>;
      expect(receipt['status'], 'verified');
      expect(adapter.requests, hasLength(1));
      expect(screen.actions, hasLength(1));
      expect(
        adapter.requests.single.messages.single.text,
        contains('completed_steps'),
      );
    },
  );
  test(
    'search labels exclude fields and a bare echo and still need review',
    () async {
      screen.views['done'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(
          box([
            field(text: 'ESP32-S3 private query'),
            label('ESP32-S3'),
            label('ESP32-S3 DevKit board'),
          ]),
        ),
      ]);
      adapter = _Adapter([
        call('tap', {'title': 'Start', 'id': 1}),
        [const TextDelta('Results observed'), const Done('end_turn')],
      ]);
      build();
      final receipt =
          jsonDecode((await run(expected: [], query: 'ESP32S3')).content)
              as Map<String, Object?>;
      expect(receipt['matching_results'], ['ESP32-S3 DevKit board']);
      expect(receipt['semantic_review_needed'], true);
    },
  );
  test(
    'product evidence requires a title and price in the same visible card',
    () async {
      screen.views['done'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(
          box([
            list([
              row([label('ESP32-S3 DevKit board'), label('NT\$95')]),
              row([label('ESP32-S3 suggestions')]),
              row([label('Other advertisement'), label('\$1')]),
            ]),
          ]),
        ),
      ]);
      build();
      final receipt =
          jsonDecode(
                (await run(
                  expected: [],
                  query: 'ESP32S3',
                  resultKind: 'product',
                )).content,
              )
              as Map<String, Object?>;
      expect(receipt['status'], 'verified');
      expect(receipt['result_items'], [
        {'title': 'ESP32-S3 DevKit board', 'price': 'NT\$95'},
      ]);
      expect(receipt['semantic_review_needed'], false);
      expect(adapter.requests, hasLength(1));
    },
  );
  test(
    'a one-read budget never adds an unbudgeted verification read',
    () async {
      limit = 1;
      build();
      final receipt = jsonDecode((await run()).content) as Map<String, Object?>;
      expect(receipt['steps'], 1);
      expect(receipt['status'], 'incomplete');
      expect(adapter.requests, isEmpty);
    },
  );
  test('a comparison cannot finish on only one matching product', () async {
    screen.views['done'] = FakeView('com.example.fixture', 'Fixture', [
      FakeWindow(
        box([
          list([
            row([label('foldable stand A'), label(r'NT$95')]),
          ]),
        ]),
      ),
    ]);
    adapter = _Adapter([
      call('tap', {'title': 'Start', 'id': 1}),
      [
        const TextDelta('Not completed: only one option visible.'),
        const Done('end_turn'),
      ],
      [
        const TextDelta('Not completed: still only one option.'),
        const Done('end_turn'),
      ],
    ]);
    build();
    final receipt =
        jsonDecode(
              (await run(
                expected: [],
                query: 'stand',
                resultKind: 'product',
                minResults: 2,
              )).content,
            )
            as Map;
    expect(receipt['verified'], false);
    expect(receipt['status'], 'incomplete');
    expect(receipt['result_items'], hasLength(1));
    expect(adapter.requests, hasLength(3));
  });
  test(
    'denied child action stops with no later action or false success',
    () async {
      gate.policy = const PermissionPolicy(
        fullPermissions: true,
        overrides: {'tap': ToolPermission.deny},
      );
      build();
      final result = await run();
      expect(
        (jsonDecode(result.content) as Map<String, Object?>)['status'],
        'blocked',
      );
      expect(screen.actions, isEmpty);
      expect(adapter.requests, hasLength(1));
    },
  );
  test(
    'an own-app initial read does not prevent launching the requested app',
    () async {
      screen.show('own');
      adapter = _Adapter([
        call('open_app', {
          'title': 'Open fixture',
          'package': 'com.example.fixture',
        }),
        call('tap', {'title': 'Start', 'id': 1}),
      ]);
      build();
      final receipt = jsonDecode((await run()).content) as Map;
      expect(receipt['status'], 'verified');
      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests.first.messages.single.text,
        isNot(contains('Private main chat')),
      );
    },
  );
  test(
    'step exhaustion cannot promote a partial state to a completed task',
    () async {
      limit = 3;
      adapter = _Adapter([
        call('read_screen', {'title': 'Read'}),
      ]);
      build();
      final receipt =
          jsonDecode(
                (await run(
                  expected: const [],
                  app: 'com.example.fixture',
                )).content,
              )
              as Map;
      expect(receipt['status'], 'incomplete');
      expect(receipt['reason'], 'worker_step_limit');
      expect(receipt['semantic_review_needed'], true);
      expect(receipt['verified'], false);
    },
  );
  test('Stop cancels before any worker request', () async {
    build();
    token.cancel();
    final result = await run(cancel: token);
    expect(result.isError, true);
    expect(adapter.requests, isEmpty);
    expect(screen.actions, isEmpty);
  });
}
