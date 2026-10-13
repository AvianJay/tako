import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/files/workspace.dart';
import 'package:tako/core/permissions/permission_gate.dart';
import 'package:tako/core/providers/cancel_token.dart';
import 'package:tako/core/screen/screen_capability.dart';
import 'package:tako/core/tools/screen_replay_tool.dart';
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

class _Game extends FakeScreen {
  _Game()
    : super({
        'game': FakeView('com.example.game', 'Game', [
          FakeWindow(box([label('Game area')])),
        ]),
        'other': FakeView('other', 'Other', [
          FakeWindow(box([label('Other app')])),
        ]),
      }, start: 'game');
  final sent = <int>[];
  final clock = Stopwatch()..start();
  bool switchAfterFirst = false;
  bool failSecond = false;
  @override
  bool get supportsTimedGestures => true;
  @override
  Future<ScreenActionOutcome> timedGesture(
    ScreenAction action, {
    required String app,
    required int width,
    required int height,
    required CancelToken cancel,
  }) async {
    cancel.throwIfCancelled();
    if (failSecond && sent.isNotEmpty) throw StateError('transport failed');
    if ((await snapshot(screenshot: false, cancel: cancel)).packageName !=
        app) {
      throw const ScreenException('game_app_or_geometry_changed');
    }
    sent.add(clock.elapsedMilliseconds);
    if (switchAfterFirst) show('other');
    return const ScreenActionOutcome(
      method: 'tap',
      details: {'committed': true},
    );
  }
}

void main() {
  late AppDatabase database;
  late _Game game;
  late ToolExecutor executor;
  late PermissionGate gate;
  late AuditRepository audit;
  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    game = _Game();
    audit = AuditRepository(database);
    gate = PermissionGate(
      policy: const PermissionPolicy(
        fullPermissions: true,
        skipHighRiskConfirmations: true,
      ),
    );
  });
  void build() {
    final readings = ScreenReadings();
    executor = ToolExecutor(
      registry: ToolRegistry([
        ...createScreenTools(game, workspace: _Workspace(), readings: readings),
        ScreenReplayTool(
          screen: game,
          readings: readings,
          audit: audit,
          remaining: () => 20,
          onStep: (_) {},
        ),
      ]),
      permissions: gate,
      audit: audit,
      maxOutputChars: 60000,
    );
  }

  Future<ToolResultBlock> run(
    String tool,
    Map<String, Object?> args, {
    CancelToken? cancel,
  }) async => (await executor.execute(
    ToolCallBlock(
      id: tool,
      name: tool,
      arguments: jsonEncode({'title': 'Play inputs', ...args}),
    ),
    ToolContext(
      conversationId: 'chat',
      messageId: 'response',
      cancel: cancel ?? CancelToken(),
    ),
  )).result;
  Map<String, Object?> gesture(int at) => {
    'action': 'tap',
    'at_ms': at,
    'x': 100,
    'y': 100,
  };
  tearDown(() async {
    game.dispose();
    await database.close();
  });

  test(
    'scheduled inputs keep their spacing with no provider round or repeated full read',
    () async {
      build();
      await run('read_screen', {});
      final result = await run('screen_replay', {
        'app': 'com.example.game',
        'gestures': [gesture(0), gesture(120)],
      });
      expect(result.isError, false);
      expect(game.sent, hasLength(2));
      expect(game.sent.last - game.sent.first, greaterThanOrEqualTo(90));
      expect(result.sideEffects, hasLength(2));
      expect(
        (await audit.list()).where((r) => r.toolName == 'game_tap'),
        hasLength(2),
      );
    },
  );
  test(
    'Stop cancels a future scheduled gesture while retaining the first receipt',
    () async {
      build();
      await run('read_screen', {});
      final cancel = CancelToken();
      final operation = run('screen_replay', {
        'app': 'com.example.game',
        'gestures': [gesture(0), gesture(3000)],
      }, cancel: cancel);
      while (game.sent.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      cancel.cancel();
      final result = await operation;
      expect(game.sent, hasLength(1));
      expect(result.isError, true);
      expect(result.sideEffects, hasLength(1));
      expect(result.content, contains('cancelled'));
    },
  );
  test(
    'foreground change stops without sending into another app or replaying the first gesture',
    () async {
      game.switchAfterFirst = true;
      build();
      await run('read_screen', {});
      final result = await run('screen_replay', {
        'app': 'com.example.game',
        'gestures': [gesture(0), gesture(20)],
      });
      expect(game.sent, hasLength(1));
      expect(result.isError, true);
      expect(result.content, contains('game_app_or_geometry_changed'));
    },
  );
  test(
    'the batch requires high-risk approval and invalid schedules commit nothing',
    () async {
      gate.policy = const PermissionPolicy(
        fullPermissions: true,
        overrides: {'screen_replay': ToolPermission.deny},
      );
      build();
      await run('read_screen', {});
      expect(
        (await run('screen_replay', {
          'app': 'com.example.game',
          'gestures': [gesture(0)],
        })).isError,
        true,
      );
      expect(game.sent, isEmpty);
      expect(
        (await run('screen_replay', {
          'app': 'com.example.game',
          'gestures': [gesture(50), gesture(0)],
        })).content,
        contains('invalid_game_schedule'),
      );
    },
  );
  test(
    'unexpected transport failure preserves earlier committed receipts',
    () async {
      game.failSecond = true;
      build();
      await run('read_screen', {});
      final result = await run('screen_replay', {
        'app': 'com.example.game',
        'gestures': [gesture(0), gesture(20)],
      });
      expect(result.isError, true);
      expect(result.sideEffects, hasLength(1));
      expect(result.content, contains('game_transport_failed_check_screen'));
      final records = (await audit.list())
          .where((r) => r.toolName == 'game_tap')
          .toList();
      expect(records, hasLength(2));
      expect(records.every((r) => r.finishedAt != null), true);
    },
  );
}
