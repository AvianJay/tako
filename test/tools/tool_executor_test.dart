import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/chat/agent_suspended.dart';
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
    this.inputSchema,
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
  final Map<String, Object?>? inputSchema;
  int runs = 0;

  @override
  String get description => 'Test tool.';
  @override
  Map<String, Object?> get schema =>
      inputSchema ??
      const {
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

  for (final error in ['foreground_required', 'notification_access_required']) {
    test('normal chat receives $error as a tool error', () async {
      final executor = ToolExecutor(
        registry: ToolRegistry([
          TestTool(
            onRun: () async => ToolResult(
              content: jsonEncode({'error': error}),
              isError: true,
            ),
          ),
        ]),
        permissions: PermissionGate(),
        audit: audit,
      );
      final result = (await executor.execute(call(), context())).result;
      expect(result.isError, isTrue);
      expect(
        (jsonDecode(result.content) as Map<String, Object?>)['error'],
        error,
      );
    });
    test('automation suspends on $error and latches the pause', () async {
      AgentSuspended? suspended;
      final gate = PermissionGate()
        ..suspendOnUnavailable = true
        ..onSuspended = (pause) => suspended = pause;
      final executor = ToolExecutor(
        registry: ToolRegistry([
          TestTool(
            onRun: () async => ToolResult(
              content: jsonEncode({'error': error}),
              isError: true,
            ),
          ),
        ]),
        permissions: gate,
        audit: audit,
      );
      await expectLater(
        executor.execute(call(), context()),
        throwsA(isA<AgentSuspended>()),
      );
      expect(suspended?.reason, 'foreground');
    });
  }

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

  test('schema feedback corrects array mistakes before any action', () async {
    final tool = TestTool(
      inputSchema: const {
        'type': 'object',
        'properties': {
          'expected_text': {
            'type': 'array',
            'minItems': 1,
            'items': {'type': 'string'},
          },
        },
        'required': ['expected_text'],
        'additionalProperties': false,
      },
    );
    final executor = ToolExecutor(
      registry: ToolRegistry([tool]),
      permissions: PermissionGate(),
      audit: audit,
    );
    final rejected = await executor.execute(
      call(args: '{"expected_text":"private message"}'),
      context(),
    );
    final error = jsonDecode(rejected.result.content) as Map<String, dynamic>;
    expect(error['error'], 'invalid_arguments');
    expect(error['path'], r'$.expected_text');
    expect(error['expected'], 'array');
    expect(error['hint'], contains('No action was executed'));
    expect(rejected.result.content, isNot(contains('private message')));
    expect(tool.runs, 0);
    final corrected = await executor.execute(
      call(args: '{"expected_text":["private message"]}'),
      context(),
    );
    expect(corrected.result.isError, isFalse);
    expect(tool.runs, 1);
    expect((await audit.list()).every((r) => r.finishedAt != null), isTrue);
  });

  test('nested schema errors identify the exact item without values', () async {
    final tool = TestTool(
      inputSchema: const {
        'type': 'object',
        'properties': {
          'steps': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'submit': {'type': 'boolean'},
              },
              'required': ['submit'],
              'additionalProperties': false,
            },
          },
        },
        'required': ['steps'],
        'additionalProperties': false,
      },
    );
    final executor = ToolExecutor(
      registry: ToolRegistry([tool]),
      permissions: PermissionGate(),
      audit: audit,
    );
    final result = await executor.execute(
      call(args: '{"steps":[{"submit":true},{"submit":"secret fixture"}]}'),
      context(),
    );
    final error = jsonDecode(result.result.content) as Map<String, dynamic>;
    expect(error['path'], r'$.steps[1].submit');
    expect(error['expected'], 'boolean');
    expect(result.result.content, isNot(contains('secret fixture')));
    expect(tool.runs, 0);
  });

  test(
    'schema feedback reports missing fields and hides unknown keys',
    () async {
      final tool = TestTool();
      final executor = ToolExecutor(
        registry: ToolRegistry([tool]),
        permissions: PermissionGate(),
        audit: audit,
      );
      final missing = await executor.execute(call(args: '{}'), context());
      final missingError =
          jsonDecode(missing.result.content) as Map<String, Object?>;
      expect(missingError['path'], r'$.text');
      expect(missingError['expected'], 'required field');
      final unknown = await executor.execute(
        call(args: '{"text":"a","sk-private-fixture":"secret fixture"}'),
        context(),
      );
      final unknownError =
          jsonDecode(unknown.result.content) as Map<String, Object?>;
      expect(unknownError['path'], r'$');
      expect(unknown.result.content, isNot(contains('sk-private-fixture')));
      expect(unknown.result.content, isNot(contains('secret fixture')));
      expect(tool.runs, 0);
    },
  );

  test('empty arrays cannot bypass a required workflow minimum', () async {
    final tool = TestTool(
      inputSchema: const {
        'type': 'object',
        'properties': {
          'steps': {'type': 'array', 'minItems': 1, 'maxItems': 12},
        },
        'required': ['steps'],
      },
    );
    final executor = ToolExecutor(
      registry: ToolRegistry([tool]),
      permissions: PermissionGate(),
      audit: audit,
    );
    final result = await executor.execute(
      call(args: '{"steps":[]}'),
      context(),
    );
    final error = jsonDecode(result.result.content) as Map<String, Object?>;
    expect(error['path'], r'$.steps');
    expect(error['expected'], 'array length 1..12');
    expect(tool.runs, 0);
  });

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
