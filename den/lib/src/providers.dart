import 'dart:convert';

import 'api.dart';
import 'config.dart';
import 'network_guard.dart';
import 'secrets.dart';
import 'settings.dart';
import 'store.dart';

final class Provider {
  Provider(this.data, this.secret, {this.ownerId, this.configKey});
  final Map<String, Object?> data;
  final String secret;
  final String? configKey;
  final String? ownerId;
  String get id => data['id'] as String;
  String get name => data['name'] as String;
  String get baseUrl => data['baseUrl'] as String;
  List<String> get models => (data['models'] as List).cast<String>();
  bool get own => ownerId != null;
  String get prefix => own ? 'me/$name/' : '$name/';
  bool get enabled => data['enabled'] == true;
  Map<String, Object?> toJson() => {
    ...data,
    'hasApiKey': secret.isNotEmpty || (configKey?.isNotEmpty ?? false),
  };
}

final class Providers {
  Providers(
    this.store,
    this.settings,
    this.secrets,
    this.guard,
    List<Upstream> upstreams,
  ) : configured = [
        for (final u in upstreams)
          Provider(
            {
              'id': 'config-${u.name}',
              'name': u.name,
              'displayName': u.name,
              'baseUrl': u.baseUrl.replaceAll(RegExp(r'/+$'), ''),
              'models': u.models,
              'enabled': true,
              'source': 'config',
              'access': {'allUsers': true, 'userIds': <String>[]},
              'createdAt': iso(0),
              'updatedAt': iso(0),
            },
            '',
            configKey: u.apiKey,
          ),
      ] {
    final names = <String>{};
    for (final upstream in upstreams) {
      if (upstream.name == 'me' ||
          !RegExp(r'^[a-z0-9][a-z0-9_-]{0,31}$').hasMatch(upstream.name) ||
          !names.add(upstream.name)) {
        throw StateError('Configured provider names must be valid and unique.');
      }
      httpUrl(upstream.baseUrl);
    }
  }
  final Store store;
  final Settings settings;
  final Secrets secrets;
  final NetworkGuard guard;
  final List<Provider> configured;

  List<Provider> list({String? ownerId}) => [
    if (ownerId == null) ...configured,
    for (final row in store.db.select(
      'SELECT * FROM providers WHERE owner_id IS ? ORDER BY created_at, id',
      [ownerId],
    ))
      if (ownerId != null || !configured.any((p) => p.name == row['name']))
        Provider(
          jsonDecode(row['data'] as String) as Map<String, Object?>,
          row['secret'] as String,
          ownerId: ownerId,
        ),
  ];

  Provider get(String id, {String? ownerId}) =>
      list(ownerId: ownerId).where((p) => p.id == id).firstOrNull ??
      (throw const ApiException(404, 'not_found'));

  List<Provider> visible(User user) => [
    if (user.permissions['useSharedProviders'] == true)
      for (final provider in list())
        if (provider.enabled &&
            (user.isAdmin ||
                (provider.data['access'] as Map)['allUsers'] == true ||
                ((provider.data['access'] as Map)['userIds'] as List).contains(
                  user.id,
                )))
          provider,
    if (user.permissions['ownProviders'] == true)
      ...list(ownerId: user.id).where((p) => p.enabled),
  ];

  Future<String> key(Provider provider) => provider.configKey != null
      ? Future.value(provider.configKey!)
      : secrets.decrypt(provider.secret, 'provider:${provider.id}');

  Future<void> check(Provider provider) async {
    if (provider.own && !settings.allowPrivate) {
      await guard.resolve(Uri.parse(provider.baseUrl));
    }
  }

  Future<Provider> save(
    Map<String, Object?> changes, {
    String? ownerId,
    String? id,
  }) async {
    final old = id == null ? null : get(id, ownerId: ownerId);
    if (old?.data['source'] == 'config') fail(400, 'read_only');
    final data = {...?old?.data, ...changes};
    final name = string(data, 'name');
    if (name == 'me' || !RegExp(r'^[a-z0-9][a-z0-9_-]{0,31}$').hasMatch(name)) {
      fail(400, 'invalid_name');
    }
    if (list(ownerId: ownerId).any((p) => p.name == name && p.id != id)) {
      fail(409, 'name_taken');
    }
    final uri = httpUrl(string(data, 'baseUrl'));
    if (ownerId != null && !settings.allowPrivate) guard.literal(uri);
    final displayName = string(data, 'displayName', fallback: name, max: 128);
    final models = data.containsKey('models')
        ? strings(data['models'])
        : <String>[];
    final enabled = boolean(data, 'enabled');
    Map<String, Object?>? access;
    if (ownerId == null) {
      final value = data['access'] ?? {'allUsers': true, 'userIds': <String>[]};
      if (value is! Map<String, Object?>) fail(400, 'invalid_request');
      access = {
        'allUsers': boolean(value, 'allUsers'),
        'userIds': strings(value['userIds'] ?? <String>[]),
      };
    }
    final providerId = id ?? newId();
    final secret = changes.containsKey('apiKey')
        ? await secrets.encrypt(
            string(changes, 'apiKey'),
            'provider:$providerId',
          )
        : old?.secret ?? '';
    final result = {
      'id': providerId,
      'name': name,
      'displayName': displayName,
      'baseUrl': uri.toString().replaceAll(RegExp(r'/+$'), ''),
      'models': models,
      'enabled': enabled,
      'source': ownerId == null ? 'admin' : 'user',
      'access': ?access,
      'createdAt': old?.data['createdAt'] ?? iso(now()),
      'updatedAt': iso(now()),
    };
    // Recheck after encryption yields, so concurrent creates still return the contract's conflict.
    if (list(ownerId: ownerId).any((p) => p.name == name && p.id != id)) {
      fail(409, 'name_taken');
    }
    if (id != null) get(id, ownerId: ownerId);
    store.db.execute(
      '''INSERT INTO providers (id, owner_id, name, data, secret, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET name = excluded.name,
      data = excluded.data, secret = excluded.secret, updated_at = excluded.updated_at''',
      [providerId, ownerId, name, jsonEncode(result), secret, now(), now()],
    );
    return get(providerId, ownerId: ownerId);
  }

  void delete(String id, {String? ownerId}) {
    final provider = get(id, ownerId: ownerId);
    if (provider.data['source'] == 'config') fail(400, 'read_only');
    store.db.execute('DELETE FROM providers WHERE id = ? AND owner_id IS ?', [
      id,
      ownerId,
    ]);
  }
}
