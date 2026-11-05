import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';

import 'api.dart';
import 'config.dart';
import 'grants.dart';
import 'invites.dart';
import 'secrets.dart';
import 'settings.dart';
import 'store.dart';

Map<String, Object?> session(Device device, String token) => {
  'token': token,
  'device': {'id': device.id, 'name': device.name},
  'user': device.user.toJson(),
};

final class RateLimiter {
  final _attempts = <String, List<int>>{};
  void forgive(String key) {
    final values = _attempts[key];
    if (values == null || values.isEmpty) return;
    values.removeLast();
    if (values.isEmpty) _attempts.remove(key);
  }

  void check(
    String key, {
    int limit = 10,
    Duration window = const Duration(minutes: 15),
  }) {
    final current = now();
    final cutoff = current - window.inMilliseconds;
    _attempts.removeWhere(
      (_, values) => values.isEmpty || values.last <= current - 900000,
    );
    if (!_attempts.containsKey(key) && _attempts.length >= 10000) {
      fail(429, 'too_many_attempts');
    }
    final values = _attempts.putIfAbsent(key, () => []);
    values.removeWhere((value) => value <= cutoff);
    if (values.length >= limit || _attempts.length > 10000) {
      fail(429, 'too_many_attempts');
    }
    values.add(now());
  }
}

final class Auth {
  Auth(this.store, this.settings, this.invites, this.grants, this.config) {
    if (store.userCount == 0 && (config.adminPassword?.isNotEmpty ?? false)) {
      store.createUser(
        config.adminUsername ?? 'admin',
        config.adminPassword!,
        isAdmin: true,
      );
    }
    if (store.userCount == 0) setupToken = randomToken();
  }
  final Store store;
  final Settings settings;
  final Invites invites;
  final Grants grants;
  final DenConfig config;
  final limiter = RateLimiter();
  String? setupToken;

  String address(Request request) {
    if (config.trustProxy &&
        (request.headers['x-forwarded-for']?.isNotEmpty ?? false)) {
      return request.headers['x-forwarded-for']!.split(',').last.trim();
    }
    final info = request.context['shelf.io.connection_info'];
    return info is HttpConnectionInfo ? info.remoteAddress.address : 'unknown';
  }

  Response signIn(User user, String name) {
    if (user.disabled) fail(403, 'account_disabled');
    final (device, token) = store.createDevice(user, name);
    return json(session(device, token));
  }

  Future<Response> setup(Request request) async {
    if (store.userCount > 0) {
      setupToken = null;
      fail(403, 'setup_done');
    }
    limiter.check('setup:${address(request)}');
    final data = await body(request);
    if (store.userCount > 0) fail(403, 'setup_done');
    final deviceName = string(
      data,
      'deviceName',
      fallback: 'Web browser',
      max: 64,
    );
    if (!constantTimeEquals(
      utf8.encode(digest(string(data, 'setupToken', fallback: ''))),
      utf8.encode(digest(setupToken ?? '')),
    )) {
      fail(403, 'invalid_setup_token');
    }
    // No await between the final guard and creation: concurrent setups cannot win twice.
    if (store.userCount > 0) fail(403, 'setup_done');
    final user = store.createUser(
      string(data, 'username'),
      string(data, 'password'),
      isAdmin: true,
      displayName: string(
        data,
        'displayName',
        fallback: string(data, 'username'),
        max: 128,
      ),
    );
    setupToken = null;
    return signIn(user, deviceName);
  }

  Future<Response> login(Request request) async {
    final data = await body(request);
    final username = string(data, 'username', fallback: '', max: 128).trim();
    limiter.check('login:${address(request)}', limit: 50);
    limiter.check('login:${address(request)}:${username.toLowerCase()}');
    final user = store.checkPassword(
      username,
      string(data, 'password', fallback: ''),
    );
    if (user == null) fail(401, 'invalid_login');
    if (user.disabled) fail(403, 'account_disabled');
    if (!settings.passwordLogin && !user.isAdmin) {
      fail(403, 'password_login_disabled');
    }
    limiter.forgive('login:${address(request)}');
    limiter.forgive('login:${address(request)}:${username.toLowerCase()}');
    return signIn(
      user,
      string(data, 'deviceName', fallback: 'Web browser', max: 64),
    );
  }

  User registerUser(
    String username,
    String? password,
    String displayName,
    String invite, {
    bool inviteHashed = false,
  }) {
    if (store.userCount == 0 || settings.registration == 'closed') {
      fail(403, 'registration_closed');
    }
    store.db.execute('BEGIN IMMEDIATE');
    try {
      if (settings.registration == 'invite') {
        invites.consume(invite, hashed: inviteHashed);
      }
      final user = store.createUser(
        username,
        password,
        displayName: displayName,
      );
      store.db.execute('COMMIT');
      return user;
    } catch (_) {
      store.db.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<Response> register(Request request) async {
    limiter.check('register:${address(request)}', limit: 30);
    final data = await body(request);
    final name = string(data, 'deviceName', fallback: 'Web browser', max: 64);
    final user = registerUser(
      string(data, 'username'),
      string(data, 'password'),
      string(data, 'displayName', fallback: string(data, 'username'), max: 128),
      string(data, 'inviteCode', fallback: ''),
    );
    return signIn(user, name);
  }

  String ticket(User user) => grants.create(
    'ticket',
    {},
    userId: user.id,
    lifetime: const Duration(minutes: 2),
  );

  Future<Response> redeemTicket(Request request) async {
    limiter.check('ticket:${address(request)}', limit: 50);
    final data = await body(request);
    final name = string(data, 'deviceName', fallback: 'Web browser', max: 64);
    final grant = grants.get('ticket', string(data, 'ticket'), consume: true);
    if (grant == null) fail(400, 'invalid_ticket');
    final user = store.userById(grant['userId'] as String);
    if (user == null) fail(400, 'invalid_ticket');
    return signIn(user, name);
  }

  Future<Response> startDevice(Request request) async {
    limiter.check('device:${address(request)}', limit: 30);
    final data = await body(request);
    final deviceCode = randomToken();
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final raw = String.fromCharCodes([
      for (var i = 0; i < 8; i++)
        alphabet.codeUnitAt(random.nextInt(alphabet.length)),
    ]);
    final userCode = '${raw.substring(0, 4)}-${raw.substring(4)}';
    final entry = {
      'deviceName': string(data, 'deviceName', fallback: 'Device', max: 64),
      'platform': string(data, 'platform', fallback: '', max: 64),
      'createdAt': now(),
      'status': 'pending',
    };
    grants.create('device', entry, token: deviceCode);
    // Only the hash of the long code is needed to approve a pending grant.
    grants.create('device_user', {
      'deviceHash': digest(deviceCode),
    }, token: normalizeCode(userCode));
    final origin = settings.publicUrl ?? request.requestedUri.origin;
    return json({
      'deviceCode': deviceCode,
      'userCode': userCode,
      'verificationUrl': '$origin/link?code=$userCode',
      'expiresIn': 600,
      'interval': 3,
    });
  }

  Future<Response> poll(Request request) async {
    final data = await body(request);
    final code = string(data, 'deviceCode');
    limiter.check(
      'poll:${address(request)}',
      limit: 300,
      window: const Duration(minutes: 1),
    );
    limiter.check(
      'poll:${digest(code)}',
      limit: 5,
      window: const Duration(seconds: 3),
    );
    final grant = grants.get('device', code);
    if (grant == null) fail(410, 'expired');
    if (grant['status'] == 'pending') {
      return json({'status': 'pending'}, status: 202);
    }
    grants.get('device', code, consume: true);
    if (grant['status'] == 'denied') fail(403, 'access_denied');
    final user = store.userById(grant['userId'] as String);
    if (user == null) fail(410, 'expired');
    return signIn(user, grant['deviceName'] as String);
  }

  Response device(Request request, User user, String code, String? action) {
    limiter.check('confirm:${user.id}', limit: 60);
    final link = grants.get('device_user', normalizeCode(code));
    if (link == null) fail(404, 'not_found');
    final rows = store.db.select(
      'SELECT * FROM grants WHERE hash = ? AND kind = ? AND expires_at > ?',
      [link['deviceHash'], 'device', now()],
    );
    if (rows.isEmpty) fail(404, 'not_found');
    final row = rows.first;
    final data = jsonDecode(row['data'] as String) as Map<String, Object?>;
    if (data['status'] != 'pending') fail(404, 'not_found');
    if (request.method == 'GET' && action == null) {
      return json({
        'userCode':
            '${normalizeCode(code).substring(0, 4)}-${normalizeCode(code).substring(4)}',
        'deviceName': data['deviceName'],
        'platform': data['platform'],
        'createdAt': iso(data['createdAt'] as int),
        'expiresAt': iso(row['expires_at'] as int),
      });
    }
    if (request.method != 'POST' || !['approve', 'deny'].contains(action)) {
      fail(404, 'not_found');
    }
    data['status'] = action == 'approve' ? 'approved' : 'denied';
    store.db.execute('UPDATE grants SET data = ?, user_id = ? WHERE hash = ?', [
      jsonEncode(data),
      user.id,
      link['deviceHash'],
    ]);
    grants.get('device_user', normalizeCode(code), consume: true);
    return json({'ok': true});
  }
}
