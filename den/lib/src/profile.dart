import 'package:shelf/shelf.dart';

import 'admin.dart';
import 'api.dart';
import 'events.dart';
import 'oauth.dart';
import 'oauth_store.dart';
import 'store.dart';

final class Profile {
  Profile(this.store, this.admin, this.oauth, this.oauthStore, this.events);
  final Store store;
  final Admin admin;
  final OAuth oauth;
  final OAuthStore oauthStore;
  final EventHub events;

  Future<Response?> route(Request request, User user) async {
    final parts = request.url.pathSegments;
    if (parts.length < 2 || parts[1] != 'me') return null;
    if (parts.length > 2 && parts[2] == 'providers') {
      if (user.permissions['ownProviders'] != true) fail(403, 'forbidden');
      return admin.providerRoute(
        request,
        parts.skip(2).toList(),
        ownerId: user.id,
      );
    }
    if (request.method == 'PATCH' && parts.length == 2) {
      final data = await body(request);
      final name = string(data, 'displayName', max: 128);
      store.db.execute('UPDATE users SET display_name = ? WHERE id = ?', [
        name,
        user.id,
      ]);
      events.publish(user.id, 'account', {});
      return json(store.userById(user.id)!.toJson());
    }
    if (request.method == 'POST' &&
        parts.length == 3 &&
        parts[2] == 'password') {
      final data = await body(request);
      if (user.hasPassword &&
          store.checkPassword(
                user.username,
                string(data, 'currentPassword', fallback: ''),
              ) ==
              null) {
        fail(403, 'invalid_login');
      }
      store.setPassword(user.username, string(data, 'newPassword'));
      events.publish(user.id, 'account', {});
      return json({'ok': true});
    }
    if (parts.length >= 3 && parts[2] == 'identities') {
      if (request.method == 'GET' && parts.length == 3) {
        return json({'identities': oauthStore.identities(user)});
      }
      if (request.method == 'POST' && parts.length == 5 && parts[4] == 'link') {
        final url = await oauth.start(parts[3], {}, linkUser: user);
        return json({'url': url}).change(headers: oauth.browserHeaders(url));
      }
      if (request.method == 'DELETE' && parts.length == 4) {
        oauthStore.unlink(user, parts[3]);
        events.publish(user.id, 'account', {});
        return json({'ok': true});
      }
    }
    return null;
  }
}
