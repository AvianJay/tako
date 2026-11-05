import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import 'schema.dart';
import 'permissions.dart';

/// Collections a client may sync. The record bodies are the same JSON the app
/// keeps in its own tables (`Conversation`, `ChatMessage`, `MemoryEntry`, …).
const syncCollections = {
  'conversations',
  'messages',
  'memories',
  'automations',
  'settings',
  'providers',
  'files',
};

/// The largest record body accepted, in UTF-8 bytes. Files go to blobs.
const maxRecordBytes = 1024 * 1024;

final class User {
  const User(
    this.id,
    this.username, {
    required this.isAdmin,
    this.displayName = '',
    this.disabled = false,
    this.hasPassword = true,
    this.createdAt = '',
    this.permissions = const {},
    this.overrides = const {},
  });
  final String id;
  final String username;
  final bool isAdmin;
  final String displayName;
  final bool disabled;
  final bool hasPassword;
  final String createdAt;
  final Map<String, Object?> permissions;
  final Map<String, Object?> overrides;
  Map<String, Object?> toJson() => {
    'id': id,
    'username': username,
    'displayName': displayName,
    'role': isAdmin ? 'admin' : 'user',
    'hasPassword': hasPassword,
    'permissions': permissions,
    'createdAt': createdAt,
  };
}

final class Device {
  const Device(this.id, this.user, this.name);
  final String id;
  final User user;
  final String name;
}

final class SyncRecord {
  const SyncRecord({
    required this.collection,
    required this.id,
    required this.version,
    required this.seq,
    required this.deleted,
    required this.data,
    required this.updatedAt,
    this.deviceId,
  });

  final String collection;
  final String id;
  final int version;
  final int seq;
  final bool deleted;
  final Object? data;
  final DateTime updatedAt;
  final String? deviceId;

  Map<String, Object?> toJson() => {
    'collection': collection,
    'id': id,
    'version': version,
    'seq': seq,
    if (deleted) 'deleted': true,
    if (!deleted) 'data': data,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deviceId': ?deviceId,
  };
}

/// One change sent by a client. [baseVersion] is the version the client last
/// saw, or 0 for a record it believes is new.
final class SyncChange {
  const SyncChange({
    required this.collection,
    required this.id,
    required this.baseVersion,
    this.deleted = false,
    this.data,
  });

  final String collection;
  final String id;
  final int baseVersion;
  final bool deleted;
  final Object? data;
}

sealed class PushResult {
  const PushResult();
}

final class PushApplied extends PushResult {
  const PushApplied(this.record);
  final SyncRecord record;
}

/// The record changed on the server since the client's base version. The
/// client merges [current] and pushes again with its version.
final class PushConflict extends PushResult {
  const PushConflict(this.collection, this.id, this.current);
  final String collection;
  final String id;
  final SyncRecord? current;
}

final class PushRejected extends PushResult {
  const PushRejected(this.collection, this.id, this.reason);
  final String collection;
  final String id;
  final String reason;
}

final class StoreException implements Exception {
  const StoreException(this.code);
  final String code;
  @override
  String toString() => code;
}

/// All server state, in one SQLite file. Tokens and pairing codes are stored
/// only as SHA-256 hashes; passwords as salted PBKDF2.
final class Store {
  Store(this.db) {
    migrate(db);
  }

  factory Store.open(String path) => Store(sqlite3.open(path));
  factory Store.memory() => Store(sqlite3.openInMemory());

  final Database db;
  final _random = Random.secure();

  void close() => db.close();

  // Users and devices.

  int get userCount =>
      db.select('SELECT count(*) AS n FROM users').first['n'] as int;

  User createUser(
    String username,
    String? password, {
    bool isAdmin = false,
    String? displayName,
  }) {
    final name = username.trim();
    if (!RegExp(r'^[A-Za-z0-9_.-]{2,32}$').hasMatch(name)) {
      throw const StoreException('invalid_username');
    }
    if (password != null && password.length < 8) {
      throw const StoreException('password_too_short');
    }
    if (db.select('SELECT 1 FROM users WHERE username = ?', [
      name,
    ]).isNotEmpty) {
      throw const StoreException('username_taken');
    }
    final user = User(newId(), name, isAdmin: isAdmin);
    db.execute(
      'INSERT INTO users (id, username, password_hash, is_admin, created_at, display_name) VALUES (?, ?, ?, ?, ?, ?)',
      [
        user.id,
        name,
        password == null ? '' : hashPassword(password),
        isAdmin ? 1 : 0,
        _now(),
        displayName ?? name,
      ],
    );
    return userById(user.id)!;
  }

  void setPassword(String username, String password) {
    if (password.length < 8) throw const StoreException('password_too_short');
    db.execute('UPDATE users SET password_hash = ? WHERE username = ?', [
      hashPassword(password),
      username,
    ]);
    if (db.updatedRows == 0) throw const StoreException('no_such_user');
  }

  User? checkPassword(String username, String password) {
    final rows = db.select('SELECT * FROM users WHERE username = ?', [
      username.trim(),
    ]);
    if (rows.isEmpty) {
      // Spend the same time as a real check, so timing reveals no usernames.
      verifyPassword(password, _dummyHash);
      return null;
    }
    final row = rows.first;
    if (row['password_hash'] == '') {
      verifyPassword(password, _dummyHash);
      return null;
    }
    return verifyPassword(password, row['password_hash'] as String)
        ? _user(row)
        : null;
  }

  /// Returns the device and its token. The token is shown only once.
  (Device, String) createDevice(User user, String name) {
    user = userById(user.id)!;
    if (user.disabled) throw const StoreException('account_disabled');
    final token = 'tako_${_randomToken(32)}';
    final device = Device(newId(), user, _deviceName(name));
    final now = _now();
    db.execute(
      'INSERT INTO devices (id, user_id, name, token_hash, created_at, last_seen_at) VALUES (?, ?, ?, ?, ?, ?)',
      [device.id, user.id, device.name, _sha256(token), now, now],
    );
    return (device, token);
  }

  Device? deviceForToken(String token) {
    if (!token.startsWith('tako_')) return null;
    final rows = db.select(
      '''
      SELECT d.id AS device_id, d.name AS device_name, d.last_seen_at, u.*
      FROM devices d JOIN users u ON u.id = d.user_id
      WHERE d.token_hash = ? AND (d.revoked = 0 OR u.disabled = 1)
      ''',
      [_sha256(token)],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final now = _now();
    // Avoid a write on every request.
    if (now - (row['last_seen_at'] as int) > 60000) {
      db.execute('UPDATE devices SET last_seen_at = ? WHERE id = ?', [
        now,
        row['device_id'],
      ]);
    }
    return Device(
      row['device_id'] as String,
      _user(row),
      row['device_name'] as String,
    );
  }

  List<Map<String, Object?>> listDevices(User user) => [
    for (final row in db.select(
      'SELECT id, name, created_at, last_seen_at FROM devices WHERE user_id = ? AND revoked = 0 ORDER BY last_seen_at DESC',
      [user.id],
    ))
      {
        'id': row['id'],
        'name': row['name'],
        'createdAt': _iso(row['created_at'] as int),
        'lastSeenAt': _iso(row['last_seen_at'] as int),
      },
  ];

  bool deleteDevice(User user, String id) {
    db.execute('DELETE FROM devices WHERE id = ? AND user_id = ?', [
      id,
      user.id,
    ]);
    return db.updatedRows > 0;
  }

  /// A short one-time code that lets a new device sign in, like scanning a
  /// QR code in a messaging app's web client.
  ({String code, DateTime expiresAt}) createPairCode(
    User user, {
    Duration lifetime = const Duration(minutes: 5),
  }) {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final chars = [
      for (var i = 0; i < 8; i++) alphabet[_random.nextInt(alphabet.length)],
    ].join();
    final code = '${chars.substring(0, 4)}-${chars.substring(4)}';
    final expires = DateTime.now().add(lifetime);
    db.execute('DELETE FROM pair_codes WHERE expires_at < ?', [_now()]);
    db.execute(
      'INSERT INTO pair_codes (code_hash, user_id, expires_at) VALUES (?, ?, ?)',
      [_sha256(_normalizeCode(code)), user.id, expires.millisecondsSinceEpoch],
    );
    return (code: code, expiresAt: expires);
  }

  /// Consumes [code]; it works once.
  (Device, String)? claimPairCode(String code, String deviceName) {
    final hash = _sha256(_normalizeCode(code));
    final rows = db.select(
      'SELECT u.* FROM pair_codes p JOIN users u ON u.id = p.user_id WHERE p.code_hash = ? AND p.expires_at >= ?',
      [hash, _now()],
    );
    db.execute('DELETE FROM pair_codes WHERE code_hash = ?', [hash]);
    if (rows.isEmpty) return null;
    return createDevice(_user(rows.first), deviceName);
  }

  // Sync.

  int currentSeq(User user) =>
      db.select('SELECT seq FROM users WHERE id = ?', [user.id]).first['seq']
          as int;

  /// Applies [changes] in one transaction. Each change gets the next sequence
  /// number, so a pull from any earlier sequence sees it exactly once.
  List<PushResult> push(Device device, List<SyncChange> changes) {
    final user = device.user;
    final results = <PushResult>[];
    db.execute('BEGIN IMMEDIATE');
    try {
      var seq = currentSeq(user);
      for (final change in changes) {
        final reason = _validate(change);
        if (reason != null) {
          results.add(PushRejected(change.collection, change.id, reason));
          continue;
        }
        final current = record(user, change.collection, change.id);
        if ((current?.version ?? 0) != change.baseVersion) {
          results.add(PushConflict(change.collection, change.id, current));
          continue;
        }
        seq++;
        final now = _now();
        final version = change.baseVersion + 1;
        db.execute(
          '''
          INSERT INTO records (user_id, collection, id, version, seq, deleted, data, updated_at, device_id)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT (user_id, collection, id) DO UPDATE SET
            version = excluded.version, seq = excluded.seq, deleted = excluded.deleted,
            data = excluded.data, updated_at = excluded.updated_at, device_id = excluded.device_id
          ''',
          [
            user.id,
            change.collection,
            change.id,
            version,
            seq,
            change.deleted ? 1 : 0,
            change.deleted ? null : jsonEncode(change.data),
            now,
            device.id,
          ],
        );
        results.add(
          PushApplied(
            SyncRecord(
              collection: change.collection,
              id: change.id,
              version: version,
              seq: seq,
              deleted: change.deleted,
              data: change.deleted ? null : change.data,
              updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
              deviceId: device.id,
            ),
          ),
        );
      }
      db.execute('UPDATE users SET seq = ? WHERE id = ?', [seq, user.id]);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    return results;
  }

  String? _validate(SyncChange change) {
    if (!syncCollections.contains(change.collection)) {
      return 'unknown_collection';
    }
    if (change.id.isEmpty || change.id.length > 128) return 'invalid_id';
    if (change.baseVersion < 0) return 'invalid_base_version';
    if (change.deleted) return null;
    if (change.data is! Map) return 'data_must_be_object';
    if (utf8.encode(jsonEncode(change.data)).length > maxRecordBytes) {
      return 'record_too_large';
    }
    return null;
  }

  /// Changes after [since], oldest first. Deletions are included as
  /// tombstones so other devices remove their copies.
  ///
  /// When tombstones after [since] were pruned, the device may have missed
  /// deletions. The result then has `reset` set and no records: the device
  /// pulls again from 0 and drops synced records the server no longer has.
  ({List<SyncRecord> records, int seq, bool more, bool reset}) pull(
    User user, {
    int since = 0,
    int limit = 500,
    Set<String>? collections,
  }) {
    final pruned =
        db.select('SELECT pruned_seq FROM users WHERE id = ?', [
              user.id,
            ]).first['pruned_seq']
            as int;
    if (since > 0 && since < pruned) {
      return (records: const [], seq: 0, more: true, reset: true);
    }
    final rows = db.select(
      'SELECT * FROM records WHERE user_id = ? AND seq > ? ORDER BY seq LIMIT ?',
      [user.id, since, limit + 1],
    );
    final more = rows.length > limit;
    final page = rows.take(limit).map(_record).toList();
    final last = page.isEmpty ? since : page.last.seq;
    return (
      records: [
        for (final r in page)
          if (collections == null || collections.contains(r.collection)) r,
      ],
      seq: more ? last : max(last, currentSeq(user)),
      more: more,
      reset: false,
    );
  }

  SyncRecord? record(User user, String collection, String id) {
    final rows = db.select(
      'SELECT * FROM records WHERE user_id = ? AND collection = ? AND id = ?',
      [user.id, collection, id],
    );
    return rows.isEmpty ? null : _record(rows.first);
  }

  /// Removes tombstones older than [age], remembering the newest removed
  /// sequence so [pull] can tell devices that never saw them to start over.
  int pruneTombstones({Duration age = const Duration(days: 90)}) {
    final cutoff = DateTime.now().subtract(age).millisecondsSinceEpoch;
    db.execute('BEGIN IMMEDIATE');
    try {
      db.execute(
        '''
        UPDATE users SET pruned_seq = max(pruned_seq, (
          SELECT coalesce(max(seq), 0) FROM records
          WHERE records.user_id = users.id AND deleted = 1 AND updated_at < ?
        ))
        ''',
        [cutoff],
      );
      db.execute('DELETE FROM records WHERE deleted = 1 AND updated_at < ?', [
        cutoff,
      ]);
      final removed = db.updatedRows;
      db.execute('COMMIT');
      return removed;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  // Blobs (file bodies live on disk; see BlobStore).

  void addBlob(User user, String hash, int size) => db.execute(
    'INSERT OR IGNORE INTO blobs (user_id, hash, size, created_at) VALUES (?, ?, ?, ?)',
    [user.id, hash, size, _now()],
  );

  bool hasBlob(User user, String hash) => db.select(
    'SELECT 1 FROM blobs WHERE user_id = ? AND hash = ?',
    [user.id, hash],
  ).isNotEmpty;

  // Usage.

  void recordUsage(
    User user,
    String model, {
    int inputTokens = 0,
    int outputTokens = 0,
    bool shared = true,
  }) {
    final day = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    db.execute(
      '''
      INSERT INTO usage (user_id, model, day, requests, input_tokens, output_tokens, shared)
      VALUES (?, ?, ?, 1, ?, ?, ?)
      ON CONFLICT (user_id, model, day) DO UPDATE SET
        requests = requests + 1,
        input_tokens = input_tokens + excluded.input_tokens,
        output_tokens = output_tokens + excluded.output_tokens
      ''',
      [
        user.id,
        model,
        day,
        max(0, inputTokens),
        max(0, outputTokens),
        shared ? 1 : 0,
      ],
    );
  }

  List<Map<String, Object?>> usage(User user, {int days = 30}) => [
    for (final row in db.select(
      'SELECT model, day, requests, input_tokens, output_tokens FROM usage WHERE user_id = ? ORDER BY day DESC, model LIMIT ?',
      [user.id, days * 20],
    ))
      {
        'model': row['model'],
        'day': row['day'],
        'requests': row['requests'],
        'inputTokens': row['input_tokens'],
        'outputTokens': row['output_tokens'],
      },
  ];

  SyncRecord _record(Row row) => SyncRecord(
    collection: row['collection'] as String,
    id: row['id'] as String,
    version: row['version'] as int,
    seq: row['seq'] as int,
    deleted: row['deleted'] == 1,
    data: row['data'] == null ? null : jsonDecode(row['data'] as String),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    deviceId: row['device_id'] as String?,
  );

  User? userById(String id) {
    final rows = db.select('SELECT * FROM users WHERE id = ?', [id]);
    return rows.isEmpty ? null : _user(rows.first);
  }

  List<User> get users => db
      .select('SELECT * FROM users ORDER BY created_at, id')
      .map(_user)
      .toList();
  User _user(Row row) {
    final overrides =
        jsonDecode(row['permissions'] as String) as Map<String, Object?>;
    final settings = db.select('SELECT data FROM settings WHERE id = 1');
    final defaults = settings.isEmpty
        ? defaultPermissions
        : (jsonDecode(settings.first['data'] as String)
                  as Map)['defaultPermissions']
              as Map;
    return User(
      row['id'] as String,
      row['username'] as String,
      isAdmin: row['is_admin'] == 1,
      displayName: row['display_name'] as String,
      disabled: row['disabled'] == 1,
      hasPassword: row['password_hash'] != '',
      createdAt: _iso(row['created_at'] as int),
      overrides: overrides,
      permissions: effectivePermissions(
        row['is_admin'] == 1,
        defaults,
        overrides,
      ),
    );
  }

  String _randomToken(int bytes) => base64Url
      .encode([for (var i = 0; i < bytes; i++) _random.nextInt(256)])
      .replaceAll('=', '');
}

// Same scheme as the app's `newId`: a base-36 timestamp, then random text.
final _idRandom = Random.secure();
String newId() {
  const alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
  final millis = DateTime.now().toUtc().millisecondsSinceEpoch;
  final buffer = StringBuffer(millis.toRadixString(36).padLeft(9, '0'));
  for (var i = 0; i < 12; i++) {
    buffer.write(alphabet[_idRandom.nextInt(alphabet.length)]);
  }
  return buffer.toString();
}

const _pbkdf2Iterations = 120000;
final _dummyHash = hashPassword('not a real password');

String hashPassword(String password) {
  final random = Random.secure();
  final salt = Uint8List.fromList([
    for (var i = 0; i < 16; i++) random.nextInt(256),
  ]);
  final hash = _pbkdf2(utf8.encode(password), salt, _pbkdf2Iterations);
  return 'pbkdf2-sha256\$$_pbkdf2Iterations\$${base64.encode(salt)}\$${base64.encode(hash)}';
}

bool verifyPassword(String password, String stored) {
  final parts = stored.split('\$');
  if (parts.length != 4 || parts[0] != 'pbkdf2-sha256') return false;
  final expected = base64.decode(parts[3]);
  final actual = _pbkdf2(
    utf8.encode(password),
    base64.decode(parts[2]),
    int.parse(parts[1]),
  );
  return constantTimeEquals(actual, expected);
}

bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// PBKDF2-HMAC-SHA256 with a single 32-byte block.
Uint8List _pbkdf2(List<int> password, List<int> salt, int iterations) {
  final hmac = Hmac(sha256, password);
  var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final result = Uint8List.fromList(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < result.length; j++) {
      result[j] ^= u[j];
    }
  }
  return result;
}

String _sha256(String value) => sha256.convert(utf8.encode(value)).toString();

String _normalizeCode(String code) =>
    code.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

String _deviceName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Device';
  return trimmed.length > 64 ? trimmed.substring(0, 64) : trimmed;
}

int _now() => DateTime.now().millisecondsSinceEpoch;

String _iso(int millis) =>
    DateTime.fromMillisecondsSinceEpoch(millis).toUtc().toIso8601String();
