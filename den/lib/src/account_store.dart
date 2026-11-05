import 'dart:convert';

import 'api.dart';
import 'permissions.dart';
import 'store.dart';

final class AccountStore {
  AccountStore(this.store);
  final Store store;

  int sharedToday(User user) =>
      store.db.select(
            'SELECT coalesce(sum(input_tokens + output_tokens), 0) AS n FROM usage WHERE user_id = ? AND day = ? AND shared = 1',
            [user.id, today()],
          ).first['n']
          as int;

  Map<String, Object?> adminUser(User user) {
    final seen =
        store.db.select(
              'SELECT max(last_seen_at) AS t FROM devices WHERE user_id = ?',
              [user.id],
            ).first['t']
            as int?;
    return {
      ...user.toJson(),
      'disabled': user.disabled,
      'permissions': {
        for (final key in defaultPermissions.keys) key: user.overrides[key],
      },
      'effectivePermissions': user.permissions,
      'identities': [
        for (final row in store.db.select(
          'SELECT provider_id, email FROM identities WHERE user_id = ?',
          [user.id],
        ))
          {'providerId': row['provider_id'], 'email': row['email']},
      ],
      'lastSeenAt': seen == null ? null : iso(seen),
      'usageToday': sharedToday(user),
    };
  }

  User requiredUser(String id) =>
      store.userById(id) ?? (throw const ApiException(404, 'not_found'));

  void guardAdmin(User user) {
    if (user.isAdmin &&
        !user.disabled &&
        store.users.where((u) => u.isAdmin && !u.disabled).length <= 1) {
      fail(400, 'last_admin');
    }
  }

  User patch(User user, Map<String, Object?> changes) {
    final role = string(
      changes,
      'role',
      fallback: user.isAdmin ? 'admin' : 'user',
    );
    if (!['admin', 'user'].contains(role)) fail(400, 'invalid_request');
    final disabled = boolean(changes, 'disabled', fallback: user.disabled);
    if (role != 'admin' || disabled) guardAdmin(user);
    final displayName = string(
      changes,
      'displayName',
      fallback: user.displayName,
      max: 128,
    );
    final permissions = changes.containsKey('permissions')
        ? {
            ...user.overrides,
            ...validatePermissions(changes['permissions'], overrides: true),
          }
        : user.overrides;
    if (changes.containsKey('password')) {
      store.setPassword(user.username, string(changes, 'password'));
    }
    store.db.execute(
      'UPDATE users SET is_admin = ?, disabled = ?, display_name = ?, permissions = ? WHERE id = ?',
      [
        role == 'admin' ? 1 : 0,
        disabled ? 1 : 0,
        displayName,
        jsonEncode(permissions),
        user.id,
      ],
    );
    if (disabled) {
      // Retain hashes so a disabled token gets account_disabled, then stays revoked after re-enabling.
      store.db.execute('UPDATE devices SET revoked = 1 WHERE user_id = ?', [
        user.id,
      ]);
      store.db.execute('DELETE FROM pair_codes WHERE user_id = ?', [user.id]);
      store.db.execute('DELETE FROM grants WHERE user_id = ?', [user.id]);
    }
    return requiredUser(user.id);
  }

  List<Map<String, Object?>> usage(int days) => [
    for (final row in store.db.select(
      '''
      SELECT u.username, g.* FROM usage g JOIN users u ON u.id = g.user_id
      WHERE day >= ? ORDER BY day DESC, user_id, model
    ''',
      [
        DateTime.now()
            .toUtc()
            .subtract(Duration(days: days - 1))
            .toIso8601String()
            .substring(0, 10),
      ],
    ))
      {
        'userId': row['user_id'],
        'username': row['username'],
        'model': row['model'],
        'day': row['day'],
        'requests': row['requests'],
        'inputTokens': row['input_tokens'],
        'outputTokens': row['output_tokens'],
        'shared': row['shared'] == 1,
      },
  ];
}
