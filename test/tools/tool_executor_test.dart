import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/permissions/permission_gate.dart';
import 'package:tako/core/providers/cancel_token.dart';
import 'package:tako/core/tools/tool.dart';
import 'package:tako/core/tools/tool_executor.dart';
import 'package:tako/core/tools/tool_registry.dart';
import 'package:tako/data/audit_repository.dart';
import 'package:tako/data/database.dart';
import 'package:tako/platform/capabilities.dart';

class TestCapability implements Capability {
  TestCapability([this.isAvailable = true]);
  @override
  bool isAvailable;
}

class TestTool extends Tool {
  TestTool({
    this.name = 'test',
    this.risk = RiskLevel.safe,
    this.output = 'result',
    this.onRun,
    TestCapability? capability,
    this.attachments = const [],
  }) : requires = capability ?? TestCapability();

  @override
  final String name;
  @override
  final TestCapability requires;
  final RiskLevel risk;
  final String output;
  final Future<ToolResult> Function()? onRun;
  final List<ContentBlock> attachments;
  int runs = 0;

  @override
  String get description => 'Test tool.';
  @override
  Map<String, Object?> get schema => const {
    'type': 'object',
    'properties': {
      'text': {'type': 'string', 'minLength': 1},
    },
    'required': ['text'],
    'additionalProperties': false,
  };
  @override
  RiskLevel riskFor(Map<String, Object?> args, ToolContext ctx) => risk;
  @override
  Future<ToolResult> run(Map<String, Object?> args, ToolContext ctx) async {
    runs++;
    return onRun != null
        ? onRun!()
        : ToolResult(content: output, attachments: attachments);
  }
}

ToolContext context([CancelToken? token]) => ToolContext(
  conversationId: 'chat',
  messageId: 'message',
  cancel: token ?? CancelToken(),
);
ToolCallBlock call({String name = 'test', String args = '{"text":"hello"}'}) =>
    ToolCallBlock(id: 'call', name: name, arguments: args);

void main() {
  late AppDatabase database;
  late AuditRepository audit;
  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    audit = AuditRepository(database);
  });
  tearDown(() async => database.close());

  test('registry exposes only available, enabled tools', () {
    final first = TestTool();
    final unavailable = TestTool(
      name: 'off',
      capability: TestCapability(false),
    );
    final disabled = TestTool(name: 'disabled');
    final registry = ToolRegistry(
      [first, unavailable, disabled],
      disabledTools: {'disabled'},
    );
    expect(registry.definitions.map((d) => d.name), ['test']);
    expect(registry.get('off'), isNull);
    expect(registry.get('disabled'), isNull);
    expect(registry.get('unknown'), isNull);
    expect(registry.allTools, hasLength(3));
  });

  test(
    'safe execution is audited and output is bounded with intact Unicode',
    () async {
      final tool = TestTool(
        output: '😀' * 5000,
        attachments: const [
          FileBlock(path: 'a.txt', name: 'a.txt', mimeType: 'text/plain'),
        ],
      );
      final executor = ToolExecutor(
        registry: ToolRegistry([tool]),
        permissions: PermissionGate(),
        audit: audit,
        maxOutputChars: 300,
      );
      final execution = await executor.execute(call(), context());
      expect(tool.runs, 1);
      expect(execution.result.isError, isFalse);
      expect(execution.result.content.length, lessThanOrEqualTo(300));
      expect(execution.result.content, endsWith('[tool output truncated]'));
      expect(
        utf8.decode(utf8.encode(execution.result.content)),
        execution.result.content,
      );
      expect(execution.result.attachments, hasLength(1));
      final record = (await audit.list()).single;
      expect(record.decision, 'safe');
      expect(record.toolCallId, 'call');
      expect(record.finishedAt, isNotNull);
      expect(record.arguments, '{"text":"hello"}');
    },
  );

  test(
    'malformed, invalid, and unavailable calls are audited and never run',
    () async {
      final tool = TestTool();
      final executor = ToolExecutor(
        registry: ToolRegistry([tool]),
        permissions: PermissionGate(),
        audit: audit,
      );
      for (final input in [
        call(args: 'not json'),
        call(args: '[]'),
        call(args: '{}'),
        call(args: '{"text":1}'),
        call(args: '{"text":""}'),
        call(args: '{"text":"a","unknown":true}'),
        call(name: 'unknown'),
      ]) {
        final result = await executor.execute(input, context());
        expect(result.result.isError, isTrue);
      }
      expect(tool.runs, 0);
      expect(await audit.list(), hasLength(7));
      expect((await audit.list()).every((r) => r.finishedAt != null), isTrue);
    },
  );

  test('denied call returns specified JSON and records denial', () async {
    final tool = TestTool(risk: RiskLevel.sensitive);
    late PermissionGate gate;
    gate = PermissionGate(
      onPendingChanged: (request) {
        if (request != null) gate.decide(PermissionChoice.deny);
      },
    );
    final executor = ToolExecutor(
      registry: ToolRegistry([tool]),
      permissions: gate,
      audit: audit,
    );
    final result = await executor.execute(call(), context());
    expect(jsonDecode(result.result.content), {'error': 'denied_by_user'});
    expect(tool.runs, 0);
    expect((await audit.list()).single.decision, 'denied_by_user');
  });

  test(
    'cancel while approval pending cannot execute even after late approval',
    () async {
      final tool = TestTool(risk: RiskLevel.high);
      final prompted = Completer<void>();
      final gate = PermissionGate(
        onPendingChanged: (request) {
          if (request != null) prompted.complete();
        },
      );
      final executor = ToolExecutor(
        registry: ToolRegistry([tool]),
        permissions: gate,
        audit: audit,
      );
      final token = CancelToken();
      final pending = executor.execute(call(), context(token));
      await prompted.future;
      token.cancel();
      final result = await pending;
      gate.decide(PermissionChoice.allowOnce);
      expect(tool.runs, 0);
      expect(gate.pendingApproval, isNull);
      expect(jsonDecode(result.result.content), {'error': 'cancelled'});
      expect((await audit.list()).single.decision, 'cancelled');
    },
  );

  test('disabling a tool while approval pending prevents execution', () async {
    final tool = TestTool(risk: RiskLevel.action);
    final registry = ToolRegistry([tool]);
    late PermissionGate gate;
    gate = PermissionGate(
      onPendingChanged: (request) {
        if (request != null) {
          registry.disabledTools.add('test');
          gate.decide(PermissionChoice.allowInChat);
        }
      },
    );
    final executor = ToolExecutor(
      registry: registry,
      permissions: gate,
      audit: audit,
    );
    final result = await executor.execute(call(), context());
    expect(tool.runs, 0);
    expect(jsonDecode(result.result.content), {'error': 'tool_unavailable'});
  });

  test(
    'side effect receipt is kept when cancel arrives after commit',
    () async {
      final token = CancelToken();
      final tool = TestTool(
        onRun: () async {
          token.cancel();
          return const ToolResult(
            content: 'Written',
            sideEffects: [
              SideEffect(
                kind: 'file_written',
                summary: 'a.txt',
                backupPath: 'old',
              ),
            ],
          );
        },
      );
      final executor = ToolExecutor(
        registry: ToolRegistry([tool]),
        permissions: PermissionGate(),
        audit: audit,
      );
      final result = await executor.execute(call(), context(token));
      expect(result.result.sideEffects.single.backupPath, 'old');
      expect(result.result.isError, isFalse);
      expect((await audit.list()).single.isError, isFalse);
    },
  );

  test('tool errors never expose exception payload', () async {
    final tool = TestTool(
      onRun: () async => throw StateError('sensitive payload'),
    );
    final executor = ToolExecutor(
      registry: ToolRegistry([tool]),
      permissions: PermissionGate(),
      audit: audit,
    );
    final result = await executor.execute(call(), context());
    expect(result.result.content, isNot(contains('sensitive payload')));
    expect(jsonDecode(result.result.content), {'error': 'tool_failed'});
  });

  test(
    'audit redacts credentials recursively and clears or recovers records',
    () async {
      final id = await audit.start(
        conversationId: 'chat',
        messageId: 'm',
        toolCallId: 'c',
        toolName: 'test',
        arguments:
            '{"nested":{"apiKey":"fixture-value"},"text":"Bearer fixture-bearer"}',
        risk: RiskLevel.safe,
      );
      await audit.finish(
        id,
        decision: 'safe',
        resultSummary: 'sk-fixture-secret',
        isError: false,
      );
      var records = await audit.list();
      expect(records.single.arguments, isNot(contains('fixture-value')));
      expect(records.single.arguments, isNot(contains('fixture-bearer')));
      expect(records.single.resultSummary, '[REDACTED]');
      await audit.start(
        conversationId: 'chat',
        messageId: 'm',
        toolCallId: 'c2',
        toolName: 'test',
        arguments: '{}',
        risk: RiskLevel.high,
      );
      expect(await audit.recoverInterrupted(), 1);
      records = await audit.list();
      expect(records.first.decision, 'interrupted');
      await audit.clear();
      expect(await audit.list(), isEmpty);
    },
  );

  test('audit redacts quoted credential values containing spaces', () {
    expect(
      redactAuditText('password="phrase with spaces"'),
      'password=[REDACTED]',
    );
    expect(redactAuditText("secret='phrase with spaces'"), 'secret=[REDACTED]');
  });
}
