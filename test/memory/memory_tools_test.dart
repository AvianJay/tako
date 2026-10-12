import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/memory/memory.dart';
import 'package:tako/core/permissions/permission_gate.dart';
import 'package:tako/core/providers/cancel_token.dart';
import 'package:tako/core/tools/memory_tools.dart';
import 'package:tako/core/tools/tool.dart';
import 'package:tako/core/tools/tool_executor.dart';
import 'package:tako/core/tools/tool_registry.dart';
import 'package:tako/core/util/json.dart';
import 'package:tako/data/audit_repository.dart';
import 'package:tako/data/database.dart';
import 'package:tako/data/memory_repository.dart';
import 'package:tako/platform/capabilities.dart';

class _Switch implements Capability {
  bool on = true;
  @override
  bool get isAvailable => on;
}

void main() {
  late AppDatabase database;
  late MemoryRepository memory;
  late ToolExecutor executor;
  late _Switch gate;
  final requests = <PermissionRequest>[];
  late PermissionGate permissions;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    memory = MemoryRepository(database);
    gate = _Switch();
    requests.clear();
    permissions = PermissionGate(
      onPendingChanged: (request) {
        if (request == null) return;
        requests.add(request);
        final choice = request.choices.contains(PermissionChoice.allowOnce)
            ? PermissionChoice.allowOnce
            : PermissionChoice.allowInChat;
        scheduleMicrotask(() => permissions.decide(choice));
      },
    );
    executor = ToolExecutor(
      registry: ToolRegistry(createMemoryTools(memory, gate: gate)),
      permissions: permissions,
      audit: AuditRepository(database),
    );
  });
  tearDown(() => database.close());

  Future<ToolResultBlock> run(String name, Map<String, Object?> args) async =>
      (await executor.execute(
        ToolCallBlock(id: 'call', name: name, arguments: jsonEncode(args)),
        ToolContext(
          conversationId: 'chat',
          messageId: 'assistant-message',
          cancel: CancelToken(),
        ),
      )).result;

  test(
    'risk levels: reading is private, saving is reversible, deleting asks',
    () async {
      final saved = await run('memory_save', {
        'text': 'Prefers tea',
        'kind': 'preference',
      });
      final id =
          asMap(asMap(jsonDecode(saved.content))!['saved'])!['id'] as String;
      await run('memory_search', {'query': 'tea'});
      await run('memory_update', {'id': id, 'text': 'Prefers green tea'});
      await run('memory_delete', {'id': id});
      expect(requests.map((r) => (r.toolName, r.risk)), [
        ('memory_save', RiskLevel.action),
        ('memory_search', RiskLevel.sensitive),
        ('memory_update', RiskLevel.action),
        ('memory_delete', RiskLevel.high),
      ]);
      expect(requests.last.choices, [
        PermissionChoice.allowOnce,
        PermissionChoice.deny,
      ]);
    },
  );

  test('save returns an undo receipt; a duplicate returns none', () async {
    final first = await run('memory_save', {'text': 'Owns a cat'});
    final effect = first.sideEffects.single;
    expect(effect.kind, 'memory_saved');
    expect(effect.summary, 'Owns a cat');
    final undo = MemoryUndo.fromJson(effect.memoryUndo)!;
    final entry = (await memory.get(undo.id))!;
    expect(entry.sourceMessageId, 'assistant-message');
    expect(entry.revision, undo.revision);
    final again = await run('memory_save', {'text': 'Owns a cat'});
    expect(asMap(jsonDecode(again.content))!['already_saved'], isTrue);
    expect(again.sideEffects, isEmpty);
    expect(await memory.list(), hasLength(1));
  });

  test('search returns compact entries with ids', () async {
    await memory.save(text: '住在台中', kind: MemoryKind.profile);
    final result = await run('memory_search', {'query': '台中', 'limit': 3});
    final found = (jsonDecode(result.content) as Map)['memories'] as List;
    expect(found.single, {
      'id': isA<String>(),
      'text': '住在台中',
      'kind': 'profile',
      'pinned': true,
    });
  });

  test('invalid arguments fail without asking or writing', () async {
    for (final (name, args) in [
      ('memory_save', <String, Object?>{}),
      ('memory_save', {'text': 'x', 'kind': 'secret'}),
      ('memory_save', {'text': ''}),
      ('memory_save', {'text': 'x', 'extra': true}),
      ('memory_update', {'id': 'only-id'}),
      ('memory_search', {'query': 'x', 'limit': 99}),
    ]) {
      final result = await run(name, args);
      expect(result.isError, isTrue, reason: '$name $args');
    }
    expect(requests.where((r) => r.toolName != 'memory_update'), isEmpty);
    expect(await memory.list(), isEmpty);
    final missing = await run('memory_delete', {'id': 'missing'});
    expect(jsonDecode(missing.content), {'error': 'memory_not_found'});
  });

  test('switching memory off hides every memory tool', () {
    final registry = ToolRegistry(createMemoryTools(memory, gate: gate));
    expect(registry.definitions.map((d) => d.name), memoryToolNames);
    gate.on = false;
    expect(registry.definitions, isEmpty);
    expect(registry.get('memory_save'), isNull);
  });
}
