import 'api.dart';
import 'secrets.dart';
import 'store.dart';

final class Invites {
  Invites(this.store, this.secrets);
  final Store store;
  final Secrets secrets;

  void consume(String code, {bool hashed = false}) {
    store.db.execute(
      'UPDATE invites SET uses = uses + 1 WHERE code_hash = ? AND uses < max_uses AND expires_at > ?',
      [hashed ? code : digest(code), now()],
    );
    if (store.db.updatedRows != 1) fail(400, 'invalid_invite');
  }

  Future<Map<String, Object?>> create(Map<String, Object?> data) async {
    final uses = data['maxUses'] ?? 1;
    final days = data['expiresInDays'] ?? 7;
    if (uses is! int ||
        uses < 1 ||
        uses > 100000 ||
        days is! num ||
        !days.isFinite ||
        days <= 0 ||
        days > 3650) {
      fail(400, 'invalid_request');
    }
    final note = string(data, 'note', fallback: '', max: 512);
    final code = randomToken(18);
    final hash = digest(code);
    final encrypted = await secrets.encrypt(code, 'invite:$hash');
    store.db.execute(
      'INSERT INTO invites (code_hash, code_cipher, note, max_uses, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?)',
      [hash, encrypted, note, uses, now() + (days * 86400000).round(), now()],
    );
    return (await list()).firstWhere((row) => row['code'] == code);
  }

  Future<List<Map<String, Object?>>> list() async => [
    for (final row in store.db.select(
      'SELECT * FROM invites ORDER BY created_at DESC',
    ))
      {
        'code': await secrets.decrypt(
          row['code_cipher'] as String,
          'invite:${row['code_hash']}',
        ),
        'note': row['note'],
        'maxUses': row['max_uses'],
        'uses': row['uses'],
        'expiresAt': iso(row['expires_at'] as int),
        'createdAt': iso(row['created_at'] as int),
      },
  ];

  void delete(String code) => store.db.execute(
    'DELETE FROM invites WHERE code_hash = ?',
    [digest(code)],
  );
}
