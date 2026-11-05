import 'package:sqlite3/sqlite3.dart';

// Kept verbatim for prototype migration tests.
const schemaV1 = '''
        CREATE TABLE users (
          id TEXT PRIMARY KEY,
          username TEXT NOT NULL UNIQUE COLLATE NOCASE,
          password_hash TEXT NOT NULL,
          is_admin INTEGER NOT NULL DEFAULT 0,
          seq INTEGER NOT NULL DEFAULT 0,
          pruned_seq INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
        ) STRICT;
        CREATE TABLE devices (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          name TEXT NOT NULL,
          token_hash TEXT NOT NULL UNIQUE,
          created_at INTEGER NOT NULL,
          last_seen_at INTEGER NOT NULL
        ) STRICT;
        CREATE TABLE pair_codes (
          code_hash TEXT PRIMARY KEY,
          user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          expires_at INTEGER NOT NULL
        ) STRICT;
        CREATE TABLE records (
          user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          collection TEXT NOT NULL,
          id TEXT NOT NULL,
          version INTEGER NOT NULL,
          seq INTEGER NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0,
          data TEXT,
          updated_at INTEGER NOT NULL,
          device_id TEXT,
          PRIMARY KEY (user_id, collection, id)
        ) STRICT;
        CREATE INDEX records_seq ON records (user_id, seq);
        CREATE TABLE blobs (
          user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          hash TEXT NOT NULL,
          size INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          PRIMARY KEY (user_id, hash)
        ) STRICT;
        CREATE TABLE usage (
          user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          model TEXT NOT NULL,
          day TEXT NOT NULL,
          requests INTEGER NOT NULL DEFAULT 0,
          input_tokens INTEGER NOT NULL DEFAULT 0,
          output_tokens INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (user_id, model, day)
        ) STRICT;
      ''';

void migrate(Database db) {
  db.execute('PRAGMA journal_mode = WAL');
  db.execute('PRAGMA foreign_keys = ON');
  db.execute('PRAGMA busy_timeout = 5000');
  final version = db.select('PRAGMA user_version').first.values.first as int;
  if (version > 2) throw StateError('Database is newer than this server.');
  if (version == 2) return;
  db.execute('BEGIN IMMEDIATE');
  try {
    if (version == 0) db.execute(schemaV1);
    db.execute(schemaV2);
    db.execute('PRAGMA user_version = 2');
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}

const schemaV2 = '''
  ALTER TABLE users ADD COLUMN display_name TEXT NOT NULL DEFAULT '';
  ALTER TABLE users ADD COLUMN disabled INTEGER NOT NULL DEFAULT 0;
  ALTER TABLE users ADD COLUMN permissions TEXT NOT NULL DEFAULT '{}';
  UPDATE users SET display_name = username;
  ALTER TABLE devices ADD COLUMN revoked INTEGER NOT NULL DEFAULT 0;
  ALTER TABLE usage ADD COLUMN shared INTEGER NOT NULL DEFAULT 1;
  CREATE TABLE settings (id INTEGER PRIMARY KEY CHECK(id = 1), data TEXT NOT NULL) STRICT;
  CREATE TABLE providers (
    id TEXT PRIMARY KEY, owner_id TEXT REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL, data TEXT NOT NULL, secret TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
  ) STRICT;
  CREATE UNIQUE INDEX providers_name ON providers(coalesce(owner_id, ''), name);
  CREATE TABLE oauth_providers (id TEXT PRIMARY KEY, data TEXT NOT NULL, secret TEXT NOT NULL DEFAULT '') STRICT;
  CREATE TABLE identities (
    id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider_id TEXT NOT NULL, subject TEXT NOT NULL, email TEXT, name TEXT, created_at INTEGER NOT NULL,
    UNIQUE(provider_id, subject)
  ) STRICT;
  CREATE TABLE invites (
    code_hash TEXT PRIMARY KEY, code_cipher TEXT NOT NULL, note TEXT NOT NULL,
    max_uses INTEGER NOT NULL, uses INTEGER NOT NULL DEFAULT 0,
    expires_at INTEGER NOT NULL, created_at INTEGER NOT NULL
  ) STRICT;
  CREATE TABLE grants (
    hash TEXT PRIMARY KEY, kind TEXT NOT NULL, user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
    data TEXT NOT NULL, expires_at INTEGER NOT NULL
  ) STRICT;
''';
