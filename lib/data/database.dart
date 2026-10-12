import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

class ConversationRecords extends Table {
  TextColumn get id => text()();
  TextColumn get data => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class MessageRecords extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId =>
      text().references(ConversationRecords, #id)();
  TextColumn get parentId => text().nullable()();
  TextColumn get status => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get data => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ProviderRecords extends Table {
  TextColumn get id => text()();
  TextColumn get data => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SettingRecords extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Local tool execution history. No foreign keys: removing a chat must not
/// erase its audit trail, which users can clear independently in settings.
class AuditRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get conversationId => text()();
  TextColumn get messageId => text()();
  TextColumn get toolCallId => text()();
  TextColumn get toolName => text()();
  TextColumn get arguments => text()();
  TextColumn get risk => text()();
  TextColumn get decision => text()();
  TextColumn get resultSummary => text().withDefault(const Constant(''))();
  BoolColumn get isError => boolean().withDefault(const Constant(false))();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
}

/// A source message is deliberately not a foreign key: deleting a chat must
/// not remove a memory the user chose to keep across conversations.
@DataClassName('MemoryRow')
class Memories extends Table {
  TextColumn get id => text()();
  TextColumn get textValue => text().named('text')();
  TextColumn get kind => text()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get sourceMessageId => text().nullable()();
  TextColumn get revision => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    ConversationRecords,
    MessageRecords,
    ProviderRecords,
    SettingRecords,
    AuditRecords,
    Memories,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'tako'));

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(
        'CREATE INDEX messages_conversation ON message_records (conversation_id, created_at)',
      );
      await _createAuditIndex();
      await _createMemoryIndex();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(auditRecords);
        await _createAuditIndex();
      }
      if (from < 3) {
        await m.createTable(memories);
        await _createMemoryIndex();
      }
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _createAuditIndex() => customStatement(
    'CREATE INDEX audit_started_at ON audit_records (started_at DESC)',
  );

  /// The FTS table keeps its own copy keyed by memory ID. An external-content
  /// index would depend on implicit rowids, which VACUUM may renumber for a
  /// table whose primary key is text.
  Future<void> _createMemoryIndex() async {
    await customStatement(
      'CREATE INDEX memories_pinned_updated ON memories (pinned DESC, updated_at DESC)',
    );
    await customStatement(
      "CREATE VIRTUAL TABLE memories_fts USING fts5(id UNINDEXED, text, tokenize='unicode61')",
    );
    await customStatement('''
      CREATE TRIGGER memories_fts_insert AFTER INSERT ON memories BEGIN
        INSERT INTO memories_fts(id, text) VALUES (new.id, new.text);
      END
    ''');
    await customStatement('''
      CREATE TRIGGER memories_fts_delete AFTER DELETE ON memories BEGIN
        DELETE FROM memories_fts WHERE id = old.id;
      END
    ''');
    await customStatement('''
      CREATE TRIGGER memories_fts_update AFTER UPDATE OF text ON memories BEGIN
        UPDATE memories_fts SET text = new.text WHERE id = old.id;
      END
    ''');
  }
}
