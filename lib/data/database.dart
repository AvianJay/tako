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
    : super(executor ?? driftDatabase(name: 'tako', native: nativeOptions));

  // Configure the busy handler before Drift reads user_version, which happens
  // before migration callbacks and can race another engine's WAL recovery.
  static final nativeOptions = DriftNativeOptions(
    setup: (database) {
      database.execute('PRAGMA busy_timeout = 5000');
    },
  );

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: _migrate,
    onUpgrade: (m, from, to) => _migrate(m),
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA busy_timeout = 5000');
      await customStatement('PRAGMA journal_mode = WAL');
    },
  );

  Future<void> _migrate(Migrator m) async {
    // Native Drift transactions use BEGIN IMMEDIATE. A second engine waits,
    // then rechecks the version after the first migration has committed.
    await customStatement('PRAGMA busy_timeout = 5000');
    await transaction(() async {
      final from = (await customSelect(
        'PRAGMA user_version',
      ).getSingle()).read<int>('user_version');
      if (from >= schemaVersion) return;
      if (from == 0) {
        await m.createAll();
        await customStatement(
          'CREATE INDEX messages_conversation ON message_records (conversation_id, created_at)',
        );
        await _createAuditIndex();
        await _createMemoryIndex();
        await _createAutomationTables();
      } else {
        if (from < 2) {
          await m.createTable(auditRecords);
          await _createAuditIndex();
        }
        if (from < 3) {
          await m.createTable(memories);
          await _createMemoryIndex();
        }
        if (from < 4) await _createAutomationTables();
      }
      // Commit the version with its schema, rather than in Drift's later step.
      await customStatement('PRAGMA user_version = $schemaVersion');
    });
  }

  Future<void> _createAutomationTables() async {
    await customStatement(
      'CREATE TABLE automation_rules (id TEXT PRIMARY KEY, data TEXT NOT NULL, next_at INTEGER)',
    );
    await customStatement(
      'CREATE TABLE automation_inputs (id TEXT PRIMARY KEY, rule_id TEXT NOT NULL, data TEXT NOT NULL)',
    );
    await customStatement(
      'CREATE TABLE automation_runs (id TEXT PRIMARY KEY, rule_id TEXT NOT NULL, status TEXT NOT NULL, due_at INTEGER NOT NULL, data TEXT NOT NULL)',
    );
    await customStatement(
      'CREATE INDEX automation_runs_due ON automation_runs(status, due_at)',
    );
    await customStatement(
      'CREATE TABLE automation_events (id TEXT PRIMARY KEY, received_at INTEGER NOT NULL)',
    );
    await customStatement(
      'CREATE TABLE execution_leases (name TEXT PRIMARY KEY, owner TEXT NOT NULL, expires_at INTEGER NOT NULL)',
    );
  }

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
