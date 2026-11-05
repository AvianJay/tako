import 'dart:convert';

import 'api.dart';
import 'secrets.dart';
import 'settings.dart';
import 'store.dart';

const oauthNames = {
  'google': 'Google',
  'discord': 'Discord',
  'github': 'GitHub',
  'oidc': 'OpenID Connect',
};
const oauthScopes = {
  'google': ['openid', 'email', 'profile'],
  'discord': ['identify', 'email'],
  'github': ['read:user', 'user:email'],
  'oidc': ['openid', 'email', 'profile'],
};

final class OAuthProvider {
  OAuthProvider(this.data, this.secret, {this.configSecret});
  final Map<String, Object?> data;
  final String secret;
  final String? configSecret;
  String get id => data['id'] as String;
  String get type => data['type'] as String;
  String get clientId => data['clientId'] as String;
  bool get enabled => data['enabled'] == true;
}

final class OAuthStore {
  OAuthStore(
    this.store,
    this.settings,
    this.secrets,
    List<Map<String, Object?>> config,
  ) : configured = [
        for (final data in config)
          OAuthProvider(
            {
              'id': data['id'],
              'type': data['type'],
              'name': data['name'],
              'clientId': data['clientId'],
              'issuer': data['issuer'],
              'scopes': oauthScopes[data['type']],
              'enabled': true,
              'source': 'config',
            },
            '',
            configSecret: data['clientSecret'] as String?,
          ),
      ];
  final Store store;
  final Settings settings;
  final Secrets secrets;
  final List<OAuthProvider> configured;

  List<OAuthProvider> get providers => [
    ...configured,
    for (final row in store.db.select(
      'SELECT * FROM oauth_providers ORDER BY id',
    ))
      if (!configured.any((p) => p.id == row['id']))
        OAuthProvider(
          jsonDecode(row['data'] as String) as Map<String, Object?>,
          row['secret'] as String,
        ),
  ];

  OAuthProvider get(String id) =>
      providers.where((p) => p.id == id).firstOrNull ??
      (throw const ApiException(404, 'not_found'));

  String? redirectUri(String id) => settings.publicUrl == null
      ? null
      : '${settings.publicUrl}/v1/auth/oauth/$id/callback';

  Map<String, Object?> toJson(OAuthProvider p) => {
    ...p.data,
    'hasClientSecret':
        p.secret.isNotEmpty || (p.configSecret?.isNotEmpty ?? false),
    'redirectUri': redirectUri(p.id),
  };

  Future<String> secret(OAuthProvider p) => p.configSecret != null
      ? Future.value(p.configSecret!)
      : secrets.decrypt(p.secret, 'oauth:${p.id}');

  Future<OAuthProvider> save(Map<String, Object?> changes, {String? id}) async {
    final old = id == null ? null : get(id);
    if (old?.data['source'] == 'config') fail(400, 'read_only');
    final data = {...?old?.data, ...changes};
    final type = string(data, 'type');
    if (!oauthNames.containsKey(type)) fail(400, 'invalid_request');
    if (old != null && type != old.type) fail(400, 'invalid_request');
    final providerId = id ?? string(data, 'id', fallback: type);
    if (!RegExp(r'^[a-z0-9-]{1,32}$').hasMatch(providerId) ||
        (id != null && changes.containsKey('id') && changes['id'] != id)) {
      fail(400, 'invalid_request');
    }
    if (old == null && providers.any((p) => p.id == providerId)) {
      fail(409, 'id_taken');
    }
    final clientId = string(data, 'clientId', max: 1024);
    if (clientId.isEmpty) fail(400, 'invalid_request');
    final issuer = type == 'oidc'
        ? httpUrl(
            string(data, 'issuer'),
            httpsOnly: true,
          ).toString().replaceAll(RegExp(r'/+$'), '')
        : null;
    if (old != null &&
        issuer != old.data['issuer'] &&
        store.db.select('SELECT 1 FROM identities WHERE provider_id = ?', [
          id,
        ]).isNotEmpty) {
      fail(400, 'identity_in_use');
    }
    final scopes = data.containsKey('scopes')
        ? strings(data['scopes'])
        : oauthScopes[type]!;
    final requiredScope = type == 'discord'
        ? 'identify'
        : (type == 'github' ? 'read:user' : 'openid');
    final result = {
      'id': providerId,
      'type': type,
      'name': string(data, 'name', fallback: oauthNames[type]!, max: 128),
      'clientId': clientId,
      'issuer': issuer,
      'scopes': {requiredScope, ...scopes}.toList(),
      'enabled': boolean(data, 'enabled'),
      'source': 'admin',
    };
    final secretValue = changes.containsKey('clientSecret')
        ? await secrets.encrypt(
            string(changes, 'clientSecret'),
            'oauth:$providerId',
          )
        : old?.secret ?? '';
    if (old == null && providers.any((p) => p.id == providerId)) {
      fail(409, 'id_taken');
    }
    if (id != null) get(id);
    store.db.execute(
      'INSERT INTO oauth_providers (id, data, secret) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET data = excluded.data, secret = excluded.secret',
      [providerId, jsonEncode(result), secretValue],
    );
    return get(providerId);
  }

  void delete(String id) {
    if (get(id).data['source'] == 'config') fail(400, 'read_only');
    store.db.execute('DELETE FROM oauth_providers WHERE id = ?', [id]);
  }

  List<Map<String, Object?>> identities(User user) => [
    for (final row in store.db.select(
      'SELECT * FROM identities WHERE user_id = ? ORDER BY created_at, id',
      [user.id],
    ))
      {
        'id': row['id'],
        'providerId': row['provider_id'],
        'providerName':
            providers
                .where((p) => p.id == row['provider_id'])
                .firstOrNull
                ?.data['name'] ??
            row['provider_id'],
        'email': row['email'],
        'name': row['name'],
        'createdAt': iso(row['created_at'] as int),
      },
  ];

  void unlink(User user, String id) {
    final links = identities(user);
    if (!links.any((p) => p['id'] == id)) fail(404, 'not_found');
    if (!user.hasPassword && links.length <= 1) {
      fail(400, 'last_sign_in_method');
    }
    store.db.execute('DELETE FROM identities WHERE id = ? AND user_id = ?', [
      id,
      user.id,
    ]);
  }
}
