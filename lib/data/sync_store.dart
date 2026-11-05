import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/chat/conversation.dart';
import '../core/chat/message.dart';
import '../core/den/den_client.dart';
import '../core/den/sync_engine.dart';
import '../core/memory/memory.dart';
import '../core/util/json.dart';
import 'database.dart';

/// Den sync state in the app database. The triggers created with the schema
/// mark changes; this class reads them for upload and applies remote records.
final class SyncStore implements SyncLedger {
  SyncStore(this.database);

  final AppDatabase database;

  static const _privateChat =
      "(json_extract(data, '\$.incognito') IS 1 OR "
      "json_extract(data, '\$.automationRuleId') IS NOT NULL)";

  Future<bool> isEnabled() async {
    final row = await database
        .customSelect('SELECT enabled FROM sync_flags WHERE id = 1')
        .getSingle();
    return row.read<int>('enabled') == 1;
  }

  @override
  Future<void> enable() => database.transaction(() async {
    await database.customStatement('DELETE FROM sync_state');
    await database.customStatement(
      'UPDATE sync_flags SET enabled = 1, applying = 0, seq = 0 WHERE id = 1',
    );
    Future<void> markAll(String collection, String select) =>
        database.customStatement('''
          INSERT INTO sync_state (collection, id, dirty, rev)
          SELECT '$collection', id, 1, 1 FROM ($select)
        ''');
    await markAll(
      'conversations',
      'SELECT id FROM conversation_records WHERE NOT $_privateChat',
    );
    await markAll('messages', '''
      SELECT m.id FROM message_records m
      JOIN conversation_records c ON c.id = m.conversation_id
      WHERE NOT ${_privateChat.replaceAll('data', 'c.data')}
    ''');
    await markAll('memories', 'SELECT id FROM memories');
    await markAll(
      'settings',
      'SELECT key AS id FROM setting_records '
          'WHERE key IN (${AppDatabase.syncedSettingKeys})',
    );
  });

  @override
  Future<void> disable() => database.transaction(() async {
    await database.customStatement('DELETE FROM sync_state');
    await database.customStatement(
      'UPDATE sync_flags SET enabled = 0, applying = 0, seq = 0 WHERE id = 1',
    );
  });

  @override
  Future<int> cursor() async =>
      (await database
              .customSelect('SELECT seq FROM sync_flags WHERE id = 1')
              .getSingle())
          .read<int>('seq');

  @override
  Future<void> setCursor(int seq) => database.customStatement(
    'UPDATE sync_flags SET seq = ? WHERE id = 1',
    [seq],
  );

  @override
  Future<int> pendingCount() async =>
      (await database
              .customSelect(
                'SELECT count(*) AS n FROM sync_state WHERE dirty = 1',
              )
              .getSingle())
          .read<int>('n');

  @override
  Future<List<PendingChange>> pending({int limit = 200}) async {
    // Never-pushed records that were deleted again need no upload.
    await database.customStatement(
      'DELETE FROM sync_state WHERE dirty = 1 AND deleted = 1 AND server_version = 0',
    );
    final rows = await database
        .customSelect(
          '''
          SELECT collection, id, server_version, deleted, rev FROM sync_state
          WHERE dirty = 1
          ORDER BY CASE collection WHEN 'conversations' THEN 0 WHEN 'messages' THEN 1 ELSE 2 END
          LIMIT ?
          ''',
          variables: [Variable.withInt(limit)],
        )
        .get();
    final changes = <PendingChange>[];
    for (final row in rows) {
      final collection = row.read<String>('collection');
      final id = row.read<String>('id');
      final deleted = row.read<int>('deleted') == 1;
      final data = deleted ? null : await _localData(collection, id);
      // A message still streaming is pushed once it has finished.
      if (data != null &&
          collection == 'messages' &&
          data['status'] == MessageStatus.streaming.name) {
        continue;
      }
      changes.add(
        PendingChange(
          collection: collection,
          id: id,
          serverVersion: row.read<int>('server_version'),
          rev: row.read<int>('rev'),
          // A row that vanished without a delete trigger is a deletion too.
          data: data,
        ),
      );
    }
    return changes;
  }

  Future<JsonMap?> _localData(String collection, String id) async {
    switch (collection) {
      case 'conversations':
        return _readJson(
          'SELECT data AS v FROM conversation_records WHERE id = ?',
          id,
        );
      case 'messages':
        return _readJson(
          'SELECT data AS v FROM message_records WHERE id = ?',
          id,
        );
      case 'memories':
        final row = await (database.select(
          database.memories,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        return row == null ? null : _memory(row).toJson();
      case 'settings':
        final row = await (database.select(
          database.settingRecords,
        )..where((t) => t.key.equals(id))).getSingleOrNull();
        return row == null ? null : {'key': row.key, 'value': row.value};
    }
    return null;
  }

  Future<JsonMap?> _readJson(String sql, String id) async {
    final row = await database
        .customSelect(sql, variables: [Variable.withString(id)])
        .getSingleOrNull();
    return row == null ? null : tryDecodeObject(row.read<String>('v'));
  }

  @override
  Future<void> markPushed(PendingChange change, int version) =>
      database.customStatement(
        '''
        UPDATE sync_state SET server_version = ?,
          dirty = CASE WHEN rev = ? THEN 0 ELSE dirty END
        WHERE collection = ? AND id = ?
        ''',
        [version, change.rev, change.collection, change.id],
      );

  @override
  Future<void> markRejected(PendingChange change) => database.customStatement(
    'UPDATE sync_state SET dirty = 0 WHERE collection = ? AND id = ? AND rev = ?',
    [change.collection, change.id, change.rev],
  );

  @override
  Future<void> forgetServerCopy(
    String collection,
    String id,
  ) => database.customStatement(
    'UPDATE sync_state SET server_version = 0 WHERE collection = ? AND id = ?',
    [collection, id],
  );

  @override
  Future<ApplyResult> apply(List<DenRecord> records) {
    if (records.isEmpty) return Future.value(const ApplyResult());
    // Conversations first: messages need theirs (a foreign key).
    final ordered = [...records]
      ..sort((a, b) => _order(a.collection).compareTo(_order(b.collection)));
    return database.transaction(() async {
      await database.customStatement(
        'UPDATE sync_flags SET applying = 1 WHERE id = 1',
      );
      _removedConversations.clear();
      final conversations = <String>{};
      var memories = false;
      var settings = false;
      final deferred = <DenRecord>[];
      for (final record in ordered) {
        final outcome = await _applyOne(record);
        switch (outcome) {
          case _Outcome.deferred:
            deferred.add(record);
          case _Outcome.applied:
            switch (record.collection) {
              case 'conversations':
                conversations.add(record.id);
              case 'messages':
                final conversationId =
                    asString(record.data?['conversationId']) ??
                    await _messageConversation(record.id);
                if (conversationId != null) conversations.add(conversationId);
              case 'memories':
                memories = true;
              case 'settings':
                settings = true;
            }
          case _Outcome.skipped:
            break;
        }
      }
      await database.customStatement(
        'UPDATE sync_flags SET applying = 0 WHERE id = 1',
      );
      return ApplyResult(
        conversations: conversations,
        memories: memories,
        settings: settings,
        deferred: deferred,
      );
    });
  }

  static int _order(String collection) =>
      const {'conversations': 0, 'messages': 1}[collection] ?? 2;

  final _removedConversations = <String, String>{};

  Future<String?> _messageConversation(String id) async =>
      _removedConversations[id] ??
      (await database
              .customSelect(
                'SELECT conversation_id FROM message_records WHERE id = ?',
                variables: [Variable.withString(id)],
              )
              .getSingleOrNull())
          ?.read<String>('conversation_id');

  Future<_Outcome> _applyOne(DenRecord record) async {
    final state = await database
        .customSelect(
          'SELECT server_version, dirty, deleted FROM sync_state WHERE collection = ? AND id = ?',
          variables: [
            Variable.withString(record.collection),
            Variable.withString(record.id),
          ],
        )
        .getSingleOrNull();
    final serverVersion = state?.read<int>('server_version') ?? 0;
    // Already here, including this device's own pushes coming back.
    if (state != null && serverVersion >= record.version) {
      return _Outcome.skipped;
    }
    final dirty = state?.read<int>('dirty') == 1;
    final localDeleted = state?.read<int>('deleted') == 1;

    if (record.deleted) {
      // Deletions win, whichever side made them.
      if (record.collection == 'messages') {
        final conversationId = await _messageConversation(record.id);
        if (conversationId != null) {
          _removedConversations[record.id] = conversationId;
        }
      }
      final existed = await _deleteLocal(record.collection, record.id);
      await _forget(record.collection, record.id);
      return existed ? _Outcome.applied : _Outcome.skipped;
    }
    final data = record.data;
    if (data == null) return _Outcome.skipped;

    if (dirty) {
      final local = localDeleted
          ? null
          : await _localData(record.collection, record.id);
      // Both sides already agree, e.g. signing in again on this device.
      if (local != null && jsonEncode(local) == jsonEncode(data)) {
        await _setServerVersion(record, keepDirty: false);
        return _Outcome.skipped;
      }
      final localWins =
          localDeleted ||
          switch (record.collection) {
            'conversations' ||
            'memories' => !_isNewer(data['updatedAt'], local?['updatedAt']),
            // Only the device that wrote a message changes it.
            'messages' => true,
            _ => false,
          };
      if (localWins) {
        await _setServerVersion(record, keepDirty: true);
        return _Outcome.skipped;
      }
    }

    if (!await _writeLocal(record.collection, data)) {
      if (record.collection == 'messages') return _Outcome.deferred;
      return _Outcome.skipped;
    }
    await _setServerVersion(record, keepDirty: false);
    return _Outcome.applied;
  }

  static bool _isNewer(Object? remote, Object? local) {
    final r = DateTime.tryParse(asString(remote) ?? '');
    final l = DateTime.tryParse(asString(local) ?? '');
    if (r == null) return false;
    if (l == null) return true;
    return !r.isBefore(l);
  }

  Future<void> _setServerVersion(
    DenRecord record, {
    required bool keepDirty,
  }) async {
    await database.customStatement(
      'INSERT OR IGNORE INTO sync_state (collection, id) VALUES (?, ?)',
      [record.collection, record.id],
    );
    await database.customStatement(
      keepDirty
          ? 'UPDATE sync_state SET server_version = ? WHERE collection = ? AND id = ?'
          : 'UPDATE sync_state SET server_version = ?, dirty = 0, deleted = 0 WHERE collection = ? AND id = ?',
      [record.version, record.collection, record.id],
    );
  }

  Future<void> _forget(String collection, String id) =>
      database.customStatement(
        'DELETE FROM sync_state WHERE collection = ? AND id = ?',
        [collection, id],
      );

  /// False when the record cannot be stored yet (a message whose
  /// conversation is missing) or is not valid.
  Future<bool> _writeLocal(String collection, JsonMap data) async {
    try {
      switch (collection) {
        case 'conversations':
          final conversation = Conversation.fromJson(data);
          // Never let a synced record create a private chat here.
          if (conversation.incognito || conversation.automationRuleId != null) {
            return false;
          }
          await database
              .into(database.conversationRecords)
              .insertOnConflictUpdate(
                ConversationRecordsCompanion.insert(
                  id: conversation.id,
                  data: jsonEncode(conversation.toJson()),
                  updatedAt: conversation.updatedAt,
                ),
              );
          return true;
        case 'messages':
          final message = ChatMessage.fromJson(data);
          final conversation =
              await (database.select(database.conversationRecords)
                    ..where((t) => t.id.equals(message.conversationId)))
                  .getSingleOrNull();
          if (conversation == null) return false;
          await database
              .into(database.messageRecords)
              .insertOnConflictUpdate(
                MessageRecordsCompanion.insert(
                  id: message.id,
                  conversationId: message.conversationId,
                  parentId: Value(message.parentId),
                  status: message.status.name,
                  createdAt: message.createdAt,
                  data: jsonEncode(message.toJson()),
                ),
              );
          return true;
        case 'memories':
          final text = asString(data['text']);
          final id = asString(data['id']);
          if (text == null || id == null) return false;
          final now = DateTime.now().toUtc();
          await database
              .into(database.memories)
              .insertOnConflictUpdate(
                MemoriesCompanion.insert(
                  id: id,
                  textValue: text,
                  kind: (memoryKindNamed(data['kind']) ?? MemoryKind.fact).name,
                  pinned: Value(asBool(data['pinned']) ?? false),
                  createdAt:
                      DateTime.tryParse(asString(data['createdAt']) ?? '') ??
                      now,
                  updatedAt:
                      DateTime.tryParse(asString(data['updatedAt']) ?? '') ??
                      now,
                  revision:
                      asString(data['revision']) ??
                      '${now.microsecondsSinceEpoch}',
                  sourceMessageId: Value(asString(data['sourceMessageId'])),
                ),
              );
          return true;
        case 'settings':
          final key = asString(data['key']);
          final value = asString(data['value']);
          if (key == null || value == null) return false;
          await database
              .into(database.settingRecords)
              .insertOnConflictUpdate(
                SettingRecordsCompanion.insert(key: key, value: value),
              );
          return true;
      }
    } on Object {
      // Malformed JSON from another client.
      return false;
    }
    return false;
  }

  Future<bool> _deleteLocal(String collection, String id) async {
    switch (collection) {
      case 'conversations':
        await (database.delete(
          database.messageRecords,
        )..where((t) => t.conversationId.equals(id))).go();
        return await (database.delete(
              database.conversationRecords,
            )..where((t) => t.id.equals(id))).go() >
            0;
      case 'messages':
        return await (database.delete(
              database.messageRecords,
            )..where((t) => t.id.equals(id))).go() >
            0;
      case 'memories':
        return await (database.delete(
              database.memories,
            )..where((t) => t.id.equals(id))).go() >
            0;
      case 'settings':
        return await (database.delete(
              database.settingRecords,
            )..where((t) => t.key.equals(id))).go() >
            0;
    }
    return false;
  }

  static MemoryEntry _memory(MemoryRow row) => MemoryEntry(
    id: row.id,
    text: row.textValue,
    kind: memoryKindNamed(row.kind) ?? MemoryKind.fact,
    pinned: row.pinned,
    createdAt: row.createdAt.toUtc(),
    updatedAt: row.updatedAt.toUtc(),
    revision: row.revision,
    sourceMessageId: row.sourceMessageId,
  );
}

enum _Outcome { applied, skipped, deferred }
