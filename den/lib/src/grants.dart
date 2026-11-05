import 'dart:convert';

import 'api.dart';
import 'secrets.dart';
import 'store.dart';

/// Short-lived credentials are indexed only by their hashes.
final class Grants {
  Grants(this.store);
  final Store store;

  String create(
    String kind,
    Map<String, Object?> data, {
    String? userId,
    Duration lifetime = const Duration(minutes: 10),
    String? token,
  }) {
    store.db.execute('DELETE FROM grants WHERE expires_at <= ?', [now()]);
    final value = token ?? randomToken();
    store.db.execute(
      'INSERT INTO grants (hash, kind, user_id, data, expires_at) VALUES (?, ?, ?, ?, ?)',
      [
        digest(value),
        kind,
        userId,
        jsonEncode(data),
        now() + lifetime.inMilliseconds,
      ],
    );
    return value;
  }

  Map<String, Object?>? get(String kind, String token, {bool consume = false}) {
    final rows = store.db.select(
      'SELECT * FROM grants WHERE hash = ? AND kind = ? AND expires_at > ?',
      [digest(token), kind, now()],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    if (consume) {
      store.db.execute('DELETE FROM grants WHERE hash = ?', [digest(token)]);
    }
    return {
      ...jsonDecode(row['data'] as String) as Map<String, Object?>,
      'userId': row['user_id'],
      'expiresAt': row['expires_at'],
    };
  }

  void update(String token, Map<String, Object?> data, {String? userId}) =>
      store.db.execute(
        'UPDATE grants SET data = ?, user_id = ? WHERE hash = ?',
        [jsonEncode(data), userId, digest(token)],
      );
}
