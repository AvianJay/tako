import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import 'account_store.dart';
import 'api.dart';
import 'events.dart';
import 'gateway.dart';
import 'invites.dart';
import 'oauth_store.dart';
import 'providers.dart';
import 'settings.dart';
import 'store.dart';

final class Admin {
  Admin(
    this.store,
    this.settings,
    this.accounts,
    this.providers,
    this.oauth,
    this.invites,
    this.events,
    this.gateway,
    this.blobDir,
  );
  final Store store;
  final Settings settings;
  final AccountStore accounts;
  final Providers providers;
  final OAuthStore oauth;
  final Invites invites;
  final EventHub events;
  final Gateway gateway;
  final String blobDir;

  void changed({String? userId, bool account = false}) {
    gateway.invalidate();
    for (final user in store.users) {
      if (userId != null && user.id != userId) continue;
      events.publish(user.id, 'models', {});
      if (account) events.publish(user.id, 'account', {});
    }
  }

  Future<Response> providerRoute(
    Request request,
    List<String> parts, {
    String? ownerId,
  }) async {
    final id = parts.length > 1 ? parts[1] : null;
    if (parts.length > 3) fail(404, 'not_found');
    if (id != null &&
        parts.length == 3 &&
        parts.last == 'test' &&
        request.method == 'POST') {
      return gateway.test(providers.get(id, ownerId: ownerId));
    }
    if (parts.length > 2) fail(404, 'not_found');
    if (request.method == 'GET' && id == null) {
      return json({
        'providers': providers
            .list(ownerId: ownerId)
            .map((p) => p.toJson())
            .toList(),
      });
    }
    if ((request.method == 'POST' && id == null) ||
        (request.method == 'PATCH' && id != null)) {
      final provider = await providers.save(
        await body(request),
        ownerId: ownerId,
        id: id,
      );
      changed(userId: ownerId);
      return json(provider.toJson());
    }
    if (request.method == 'DELETE' && id != null) {
      providers.delete(id, ownerId: ownerId);
      changed(userId: ownerId);
      return json({'ok': true});
    }
    fail(404, 'not_found');
  }

  Future<Response> route(Request request, User actor) async {
    if (!actor.isAdmin) fail(403, 'forbidden');
    final parts = request.url.pathSegments.skip(2).toList();
    if (parts.isEmpty) fail(404, 'not_found');
    final id = parts.length == 2 ? parts[1] : null;
    if (parts.first == 'providers') return providerRoute(request, parts);
    if (parts.length > 2) fail(404, 'not_found');
    switch ((request.method, parts.first, id)) {
      case ('GET', 'settings', null):
        return json(settings.data);
      case ('PATCH', 'settings', null):
        final result = settings.patch(await body(request));
        changed(account: true);
        return json(result);
      case ('GET', 'users', null):
        return json({'users': store.users.map(accounts.adminUser).toList()});
      case ('POST', 'users', null):
        final data = await body(request);
        final role = string(data, 'role', fallback: 'user');
        if (!['admin', 'user'].contains(role)) fail(400, 'invalid_request');
        final user = store.createUser(
          string(data, 'username'),
          string(data, 'password'),
          isAdmin: role == 'admin',
          displayName: string(
            data,
            'displayName',
            fallback: string(data, 'username'),
            max: 128,
          ),
        );
        return json(accounts.adminUser(user));
      case ('PATCH', 'users', final String id):
        final data = await body(request);
        final user = accounts.patch(accounts.requiredUser(id), data);
        changed(userId: id, account: true);
        return json(accounts.adminUser(user));
      case ('DELETE', 'users', final String id):
        final user = accounts.requiredUser(id);
        accounts.guardAdmin(user);
        final directory = Directory(p.join(blobDir, user.id));
        // IDs originate in our store. Still verify the deletion stays in the blob root.
        if (!p.isWithin(p.absolute(blobDir), p.absolute(directory.path))) {
          fail(400, 'invalid_request');
        }
        store.db.execute('DELETE FROM users WHERE id = ?', [id]);
        if (directory.existsSync()) directory.deleteSync(recursive: true);
        events.publish(id, 'account', {});
        return json({'ok': true});
      case ('GET', 'oauth', null):
        return json({'providers': oauth.providers.map(oauth.toJson).toList()});
      case ('POST', 'oauth', null):
        return json(oauth.toJson(await oauth.save(await body(request))));
      case ('PATCH', 'oauth', final String id):
        return json(
          oauth.toJson(await oauth.save(await body(request), id: id)),
        );
      case ('DELETE', 'oauth', final String id):
        oauth.delete(id);
        return json({'ok': true});
      case ('GET', 'invites', null):
        return json({'invites': await invites.list()});
      case ('POST', 'invites', null):
        return json(await invites.create(await body(request)));
      case ('DELETE', 'invites', final String id):
        invites.delete(id);
        return json({'ok': true});
      case ('GET', 'usage', null):
        final days = int.tryParse(request.url.queryParameters['days'] ?? '30');
        if (days == null || days < 1 || days > 3650) {
          fail(400, 'invalid_request');
        }
        return json({'usage': accounts.usage(days)});
      default:
        fail(404, 'not_found');
    }
  }
}
