import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/files/workspace.dart';
import 'package:tako/core/permissions/permission_gate.dart';
import 'package:tako/core/providers/cancel_token.dart';
import 'package:tako/core/screen/screen_capability.dart';
import 'package:tako/core/tools/screen_sequence_tool.dart';
import 'package:tako/core/tools/screen_tools.dart';
import 'package:tako/core/tools/tool.dart';
import 'package:tako/core/tools/tool_executor.dart';
import 'package:tako/core/tools/tool_registry.dart';
import 'package:tako/data/audit_repository.dart';
import 'package:tako/data/database.dart';

import 'fake_screen.dart';

class _Workspace implements WorkspaceCapability {
  @override
  bool get isAvailable => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CancelScreen extends FakeScreen {
  _CancelScreen(super.views, {required super.start, required this.cancel});
  final CancelToken cancel;
  @override
  Future<ScreenActionOutcome> act(ScreenAction action) async {
    final result = await super.act(action);
    cancel.cancel();
    return result;
  }
}

void main() {
  late AppDatabase database;
  late FakeScreen screen;
  late ScreenReadings readings;
  late PermissionGate gate;
  late ToolExecutor executor;
  var response = 0;
  var remaining = 12;
  final views = {
    'stable': FakeView('com.example.keys', 'Keys', [
      FakeWindow(
        box([
          button('1'),
          button('2'),
          button('Pay now'),
          field(description: 'Password', password: true),
        ]),
      ),
    ]),
    'changed': FakeView('com.example.keys', 'Keys', [
      FakeWindow(box([label('Different view')])),
    ]),
  };
  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    screen = FakeScreen(views, start: 'stable')..fastActions = true;
    readings = ScreenReadings();
    gate = PermissionGate(
      policy: const PermissionPolicy(fullPermissions: true),
    );
    response = 0;
    remaining = 12;
  });
  void build() {
    final audit = AuditRepository(database);
    final observer = ScreenObserver(
      screen: screen,
      workspace: _Workspace(),
      readings: readings,
      allowed: (_) => true,
    );
    final primitives = ToolExecutor(
      registry: ToolRegistry(
        createScreenTools(screen, workspace: _Workspace(), observer: observer),
      ),
      permissions: gate,
      audit: audit,
    );
    executor = ToolExecutor(
      registry: ToolRegistry([
        ...primitives.registry.allTools,
        ScreenSequenceTool(
          screen: screen,
          readings: readings,
          executor: () => primitives,
          remaining: () => remaining,
        ),
      ]),
      permissions: gate,
      audit: audit,
    );
  }

  Future<ToolResultBlock> run(
    String name,
    Map<String, Object?> args, {
    CancelToken? cancel,
  }) async => (await executor.execute(
    ToolCallBlock(
      id: 'call-${response++}',
      name: name,
      arguments: jsonEncode({'title': 'Enter keys', ...args}),
    ),
    ToolContext(
      conversationId: 'chat',
      messageId: 'response-$response',
      cancel: cancel ?? CancelToken(),
    ),
  )).result;
  Future<ToolResultBlock> sequence(
    List<Map<String, Object?>> actions, {
    CancelToken? cancel,
  }) => run('screen_sequence', {'actions': actions}, cancel: cancel);
  tearDown(() async {
    screen.dispose();
    await database.close();
  });

  test(
    'stable sequence audits each action and returns one final observation',
    () async {
      build();
      await run('read_screen', {});
      final result = await sequence([
        {'tool': 'tap', 'id': 1},
        {'tool': 'tap', 'id': 2},
      ]);
      final content = jsonDecode(result.content) as Map;
      expect(result.isError, false);
      expect(content['attempted'], 2);
      expect(screen.actions, hasLength(2));
      final receipts = (content['receipts'] as List)
          .cast<Map<String, Object?>>();
      expect(
        receipts.first['receipt'],
        isNot(contains('screen after the action')),
      );
      expect(receipts.last['receipt'], contains('screen after the action'));
      expect(
        (await AuditRepository(
          database,
        ).list()).where((r) => r.toolName == 'tap'),
        hasLength(2),
      );
    },
  );
  test(
    'a denied high-risk step preserves the first receipt and skips later steps',
    () async {
      final prompts = <PermissionRequest>[];
      gate = PermissionGate(
        policy: const PermissionPolicy(fullPermissions: true),
        onPendingChanged: (request) {
          if (request != null) {
            prompts.add(request);
            scheduleMicrotask(() => gate.decide(PermissionChoice.deny));
          }
        },
      );
      build();
      await run('read_screen', {});
      final result = await sequence([
        {'tool': 'tap', 'id': 1},
        {'tool': 'tap', 'id': 3},
        {'tool': 'tap', 'id': 2},
      ]);
      expect(result.isError, true);
      expect(screen.actions, hasLength(1));
      expect(prompts.single.toolName, 'tap');
      expect(prompts.single.risk, RiskLevel.high);
      expect(result.sideEffects, hasLength(1));
      expect(result.content, contains('denied_by_user'));
    },
  );
  test('password fields remain blocked inside a sequence', () async {
    build();
    await run('read_screen', {});
    final result = await sequence([
      {'tool': 'type_text', 'id': 4, 'text': 'never type this'},
    ]);
    expect(result.content, contains('password_entry_blocked'));
    expect(screen.actions, isEmpty);
  });
  test('compact ordered ids preserve repeated keys', () async {
    build();
    await run('read_screen', {});
    final result = await run('screen_sequence', {
      'tap_ids': [1, 2, 1],
    });
    expect(result.isError, false);
    expect(screen.actions.map((a) => a.node), [1, 2, 1]);
    expect(
      (await run('screen_sequence', {
        'tap_ids': [1],
        'actions': [
          {'tool': 'tap', 'id': 1},
        ],
      })).content,
      contains('use_tap_ids_or_actions'),
    );
  });
  test('sequence budget counts inner steps before committing any', () async {
    remaining = 1;
    build();
    await run('read_screen', {});
    final result = await sequence([
      {'tool': 'tap', 'id': 1},
      {'tool': 'tap', 'id': 2},
    ]);
    expect(result.content, contains('step_limit'));
    expect(screen.actions, isEmpty);
  });
  test(
    'reject a nonfinal submission and unsupported tool before actions',
    () async {
      build();
      await run('read_screen', {});
      expect(
        (await sequence([
          {'tool': 'type_text', 'id': 4, 'text': 'x', 'submit': true},
          {'tool': 'tap', 'id': 1},
        ])).content,
        contains('submission_must_be_last'),
      );
      expect(
        (await sequence([
          {'tool': 'file_delete', 'id': 1},
        ])).isError,
        true,
      );
      expect(screen.actions, isEmpty);
    },
  );
  test(
    'Stop after a committed action retains its receipt and prevents the next action',
    () async {
      final cancel = CancelToken();
      screen.dispose();
      screen = _CancelScreen(views, start: 'stable', cancel: cancel)
        ..fastActions = true;
      build();
      await run('read_screen', {});
      final result = await sequence([
        {'tool': 'tap', 'id': 1},
        {'tool': 'tap', 'id': 2},
      ], cancel: cancel);
      expect(result.isError, true);
      expect(screen.actions, hasLength(1));
      expect(result.sideEffects, hasLength(1));
      expect(result.content, contains('cancelled'));
    },
  );
}
