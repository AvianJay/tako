import 'dart:convert';

import 'api.dart';
import 'config.dart';
import 'permissions.dart';
import 'store.dart';

final class Settings {
  Settings(this.store, this.config) {
    store.db.execute(
      'INSERT OR IGNORE INTO settings (id, data) VALUES (1, ?)',
      [
        jsonEncode({
          'serverName': 'Tako Den',
          'publicUrl': config.publicUrl,
          'registration': config.registration.name,
          'passwordLogin': true,
          'defaultPermissions': defaultPermissions,
          'userProvidersAllowPrivateNetworks': false,
        }),
      ],
    );
  }
  final Store store;
  final DenConfig config;

  Map<String, Object?> get data {
    final result =
        jsonDecode(
              store.db
                      .select('SELECT data FROM settings WHERE id = 1')
                      .first['data']
                  as String,
            )
            as Map<String, Object?>;
    if (config.publicUrlLocked) result['publicUrl'] = config.publicUrl;
    return {...result, 'publicUrlLocked': config.publicUrlLocked};
  }

  String? get publicUrl => data['publicUrl'] as String?;
  String get registration => data['registration'] as String;
  bool get passwordLogin => data['passwordLogin'] == true;
  bool get allowPrivate => data['userProvidersAllowPrivateNetworks'] == true;

  Map<String, Object?> patch(Map<String, Object?> changes) {
    final result = data;
    for (final key in changes.keys) {
      switch (key) {
        case 'serverName':
          final name = string(changes, key, max: 128).trim();
          if (name.isEmpty) fail(400, 'invalid_request');
          result[key] = name;
        case 'publicUrl':
          if (config.publicUrlLocked) fail(400, 'read_only');
          final value = changes[key];
          result[key] = value == null
              ? null
              : httpUrl(
                  string(changes, key),
                ).toString().replaceAll(RegExp(r'/+$'), '');
        case 'registration':
          if (!['closed', 'invite', 'open'].contains(changes[key])) {
            fail(400, 'invalid_request');
          }
          result[key] = changes[key];
        case 'passwordLogin' || 'userProvidersAllowPrivateNetworks':
          result[key] = boolean(changes, key);
        case 'defaultPermissions':
          result[key] = {
            ...result[key] as Map,
            ...validatePermissions(changes[key]),
          };
        default:
          fail(400, 'invalid_request');
      }
    }
    result.remove('publicUrlLocked');
    store.db.execute('UPDATE settings SET data = ? WHERE id = 1', [
      jsonEncode(result),
    ]);
    return data;
  }
}
