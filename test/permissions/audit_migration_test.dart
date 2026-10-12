import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/permissions/risk_level.dart';
import 'package:tako/data/audit_repository.dart';
import 'package:tako/data/database.dart';
import 'package:tako/data/memory_repository.dart';

void main() {
  test('v1 upgrade preserves all existing data and adds auditable v2 table', () async {
    final database = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(
            'CREATE TABLE conversation_records (id TEXT NOT NULL PRIMARY KEY, data TEXT NOT NULL, updated_at INTEGER NOT NULL)',
          );
          raw.execute(
            'CREATE TABLE message_records (id TEXT NOT NULL PRIMARY KEY, conversation_id TEXT NOT NULL REFERENCES conversation_records(id), parent_id TEXT, status TEXT NOT NULL, created_at INTEGER NOT NULL, data TEXT NOT NULL)',
          );
          raw.execute(
            'CREATE TABLE provider_records (id TEXT NOT NULL PRIMARY KEY, data TEXT NOT NULL)',
          );
          raw.execute(
            'CREATE TABLE setting_records (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)',
          );
          raw.execute(
            'CREATE INDEX messages_conversation ON message_records (conversation_id, created_at)',
          );
          raw.execute(
            "INSERT INTO conversation_records VALUES ('chat', '{\"title\":\"preserved\"}', 0)",
          );
          raw.execute(
            "INSERT INTO message_records VALUES ('m','chat',NULL,'done',0,'{\"text\":\"preserved\"}')",
          );
          raw.execute(
            "INSERT INTO provider_records VALUES ('p','{\"model\":\"preserved\"}')",
          );
          raw.execute("INSERT INTO setting_records VALUES ('theme','dark')");
          raw.execute('PRAGMA user_version = 1');
        },
      ),
    );
    addTearDown(database.close);
    expect(
      (await database.select(database.conversationRecords).getSingle()).data,
      '{"title":"preserved"}',
    );
    expect(
      (await database.select(database.messageRecords).getSingle()).data,
      '{"text":"preserved"}',
    );
    expect(
      (await database.select(database.providerRecords).getSingle()).data,
      '{"model":"preserved"}',
    );
    expect(
      (await database.select(database.settingRecords).getSingle()).value,
      'dark',
    );
    final audit = AuditRepository(database);
    await audit.start(
      conversationId: 'chat',
      messageId: 'm',
      toolCallId: 'call',
      toolName: 'test',
      arguments: '{}',
      risk: RiskLevel.safe,
    );
    expect((await audit.list()).single.toolName, 'test');
    // Later migrations run in the same upgrade.
    final memory = MemoryRepository(database);
    await memory.save(text: 'Created after a v1 upgrade');
    expect((await memory.search('upgrade')).single.text, contains('v1'));
    final version = await database
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.read<int>('user_version'), database.schemaVersion);
  });
}
