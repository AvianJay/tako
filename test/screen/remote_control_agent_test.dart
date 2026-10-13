import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/files/workspace.dart';
import 'package:tako/core/permissions/permission_gate.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/core/screen/remote_control_agent.dart';
import 'package:tako/core/tools/device_tools.dart';
import 'package:tako/core/tools/tool.dart';
import 'package:tako/core/tools/tool_executor.dart';
import 'package:tako/core/tools/tool_registry.dart';
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
    screen.launch(arguments['package'] as String);
    return {'launched': true};
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
    ]);
    build();
    final receipt = jsonDecode((await run()).content) as Map;
    expect(receipt['verified'], false);
    expect(receipt['missing_text'], ['Done']);
    expect(receipt['status'], 'reported_complete');
    expect(receipt['semantic_review_needed'], true);
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
