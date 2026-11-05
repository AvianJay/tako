import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tako_den/src/secrets.dart';
import 'package:tako_den/src/api.dart';
import 'package:tako_den/src/auth.dart';
import 'package:tako_den/tako_den.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Harness h;
  tearDown(() => h.close());

  test('rate limiter stays bounded under a flood of distinct names', () {
    h = Harness();
    final limiter = RateLimiter();
    for (var i = 0; i < 10000; i++) {
      limiter.check('name-$i');
    }
    for (var i = 0; i < 3; i++) {
      expect(
        () => limiter.check('overflow-$i'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'too_many_attempts',
          ),
        ),
      );
    }
    limiter.check('name-1');
  });

  test('setup token is per start, single use, and info matches v1', () async {
    h = Harness(admin: false);
    final info = await h.jsonCall('GET', 'v1/info');
    expect(info['version'], '0.2.0');
    expect(info['setupRequired'], true);
    expect(info['features'], containsAll(['device-login', 'oauth']));
    await h.expectError(
      'POST',
      'v1/setup',
      403,
      'invalid_setup_token',
      data: {'setupToken': 'wrong'},
    );
    final result = await h.jsonCall(
      'POST',
      'v1/setup',
      data: {
        'setupToken': h.server.setupToken,
        'username': 'owner',
        'password': 'password123',
        'displayName': 'Owner',
        'deviceName': 'Web',
      },
    );
    expect((result['user'] as Map)['role'], 'admin');
    expect((result['user'] as Map)['displayName'], 'Owner');
    expect(h.server.setupToken, isNull);
    await h.expectError('POST', 'v1/setup', 403, 'setup_done', data: {});
    expect((await h.jsonCall('GET', 'v1/info'))['setupRequired'], false);
  });

  test('admin environment bootstrap skips setup', () async {
    h = Harness(
      admin: false,
      config: const DenConfig(
        adminUsername: 'owner',
        adminPassword: 'password123',
      ),
    );
    expect(h.store.users.single.isAdmin, true);
    expect(h.server.setupToken, isNull);
    await h.expectError('POST', 'v1/setup', 403, 'setup_done', data: {});
  });

  test('open registration cannot take over an unconfigured server', () async {
    h = Harness(
      admin: false,
      config: const DenConfig(registration: Registration.open),
    );
    await h.expectError(
      'POST',
      'v1/auth/register',
      403,
      'registration_closed',
      data: {'username': 'first', 'password': 'password123'},
    );
    expect(h.store.userCount, 0);
    expect(h.server.setupToken, isNotNull);
  });

  test(
    'registration closed, open validation, invite use limits and expiry',
    () async {
      h = Harness();
      Future<void> mode(String mode) async {
        await h.jsonCall(
          'PATCH',
          'v1/admin/settings',
          asAdmin: true,
          data: {'registration': mode},
        );
      }

      Map<String, Object?> registration(String name, [String? code]) => {
        'username': name,
        'password': 'password123',
        'inviteCode': ?code,
      };
      await h.expectError(
        'POST',
        'v1/auth/register',
        403,
        'registration_closed',
        data: registration('ana'),
      );
      await mode('open');
      await h.expectError(
        'POST',
        'v1/auth/register',
        400,
        'invalid_username',
        data: registration('!'),
      );
      await h.expectError(
        'POST',
        'v1/auth/register',
        400,
        'password_too_short',
        data: {'username': 'ana', 'password': 'short'},
      );
      await h.jsonCall('POST', 'v1/auth/register', data: registration('ana'));
      await h.expectError(
        'POST',
        'v1/auth/register',
        400,
        'username_taken',
        data: registration('Ana'),
      );
      await mode('invite');
      await h.expectError(
        'POST',
        'v1/auth/register',
        400,
        'invalid_invite',
        data: registration('ben'),
      );
      final invite = await h.jsonCall(
        'POST',
        'v1/admin/invites',
        asAdmin: true,
        data: {'maxUses': 2, 'note': 'Family'},
      );
      final code = invite['code'] as String;
      await h.jsonCall(
        'POST',
        'v1/auth/register',
        data: registration('ben', code),
      );
      await h.expectError(
        'POST',
        'v1/auth/register',
        400,
        'username_taken',
        data: registration('ben', code),
      );
      await h.jsonCall(
        'POST',
        'v1/auth/register',
        data: registration('cara', code),
      );
      await h.expectError(
        'POST',
        'v1/auth/register',
        400,
        'invalid_invite',
        data: registration('dana', code),
      );
      final listed =
          (await h.jsonCall(
                'GET',
                'v1/admin/invites',
                asAdmin: true,
              ))['invites']
              as List;
      expect((listed.single as Map)['uses'], 2);
      final expiring = await h.jsonCall(
        'POST',
        'v1/admin/invites',
        asAdmin: true,
        data: {},
      );
      h.store.db.execute(
        'UPDATE invites SET expires_at = 0 WHERE code_hash = ?',
        [digest(expiring['code'] as String)],
      );
      await h.expectError(
        'POST',
        'v1/auth/register',
        400,
        'invalid_invite',
        data: registration('dana', expiring['code'] as String),
      );
      await h.jsonCall('DELETE', 'v1/admin/invites/$code', asAdmin: true);
    },
  );

  test(
    'password login switch, administrator exception, disabled and revoked accounts',
    () async {
      h = Harness();
      final user = h.addUser('ana');
      final token = h.token(user);
      await h.jsonCall(
        'PATCH',
        'v1/admin/settings',
        asAdmin: true,
        data: {'passwordLogin': false},
      );
      await h.expectError(
        'POST',
        'v1/auth/login',
        403,
        'password_login_disabled',
        data: {'username': 'ana', 'password': 'password123'},
      );
      await h.jsonCall(
        'POST',
        'v1/auth/login',
        data: {'username': 'admin', 'password': 'password123'},
      );
      await h.jsonCall(
        'PATCH',
        'v1/admin/users/${user.id}',
        asAdmin: true,
        data: {'disabled': true},
      );
      await h.expectError(
        'GET',
        'v1/me',
        403,
        'account_disabled',
        token: token,
      );
      await h.expectError(
        'POST',
        'v1/auth/login',
        403,
        'account_disabled',
        data: {'username': 'ana', 'password': 'password123'},
      );
      await h.jsonCall(
        'PATCH',
        'v1/admin/users/${user.id}',
        asAdmin: true,
        data: {'disabled': false},
      );
      await h.expectError('GET', 'v1/me', 401, 'unauthorized', token: token);
    },
  );

  test(
    'device approval, normalization, single use, denial, expiry and polling limit',
    () async {
      h = Harness();
      Future<Map<String, Object?>> start() => h.jsonCall(
        'POST',
        'v1/auth/device',
        data: {'deviceName': 'Pixel', 'platform': 'android'},
      );
      final device = await start();
      final code = device['userCode'] as String;
      expect(device['verificationUrl'], 'https://den.test/link?code=$code');
      expect(
        (await h.jsonCall(
          'POST',
          'v1/auth/device/poll',
          data: {'deviceCode': device['deviceCode']},
          status: 202,
        ))['status'],
        'pending',
      );
      final normalized = Uri.encodeComponent(
        code.toLowerCase().replaceAll('-', ' '),
      );
      final view = await h.jsonCall(
        'GET',
        'v1/auth/device/$normalized',
        asAdmin: true,
      );
      expect(view['deviceName'], 'Pixel');
      await h.jsonCall(
        'POST',
        'v1/auth/device/$normalized/approve',
        asAdmin: true,
      );
      await h.expectError(
        'POST',
        'v1/auth/device/$code/approve',
        404,
        'not_found',
        asAdmin: true,
      );
      final result = await h.jsonCall(
        'POST',
        'v1/auth/device/poll',
        data: {'deviceCode': device['deviceCode']},
      );
      expect((result['user'] as Map)['id'], h.adminUser!.id);
      await h.expectError(
        'POST',
        'v1/auth/device/poll',
        410,
        'expired',
        data: {'deviceCode': device['deviceCode']},
      );
      final denied = await start();
      await h.jsonCall(
        'POST',
        'v1/auth/device/${denied['userCode']}/deny',
        asAdmin: true,
      );
      await h.expectError(
        'POST',
        'v1/auth/device/poll',
        403,
        'access_denied',
        data: {'deviceCode': denied['deviceCode']},
      );
      final expired = await start();
      h.store.db.execute(
        'UPDATE grants SET expires_at = 0 WHERE kind IN (?, ?)',
        ['device', 'device_user'],
      );
      await h.expectError(
        'POST',
        'v1/auth/device/poll',
        410,
        'expired',
        data: {'deviceCode': expired['deviceCode']},
      );
      await h.expectError(
        'GET',
        'v1/auth/device/${expired['userCode']}',
        404,
        'not_found',
        asAdmin: true,
      );
      final pending = await start();
      for (var i = 0; i < 5; i++) {
        await h.jsonCall(
          'POST',
          'v1/auth/device/poll',
          data: {'deviceCode': pending['deviceCode']},
          status: 202,
        );
      }
      await h.expectError(
        'POST',
        'v1/auth/device/poll',
        429,
        'too_many_attempts',
        data: {'deviceCode': pending['deviceCode']},
      );
      final stored = h.store.db.select('SELECT * FROM grants').toString();
      expect(stored, isNot(contains(pending['deviceCode'])));
      expect(stored, isNot(contains(pending['userCode'])));
    },
  );

  test(
    'device user codes use the pairing alphabet and XXXX-XXXX format',
    () async {
      h = Harness();
      final codes = <String>{};
      for (var i = 0; i < 30; i++) {
        final device = await h.jsonCall(
          'POST',
          'v1/auth/device',
          data: {'deviceName': 'Phone'},
        );
        final code = device['userCode'] as String;
        expect(
          code,
          matches(
            r'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{4}-[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{4}$',
          ),
        );
        expect(codes.add(code), true);
        expect(device['verificationUrl'], 'https://den.test/link?code=$code');
      }
    },
  );

  test('tickets expire and can be redeemed once', () async {
    h = Harness();
    final ticket = h.server.auth.ticket(h.adminUser!);
    expect(
      h.store.db.select('SELECT * FROM grants').toString(),
      isNot(contains(ticket)),
    );
    final result = await h.jsonCall(
      'POST',
      'v1/auth/ticket',
      data: {'ticket': ticket, 'deviceName': 'Browser'},
    );
    expect((result['device'] as Map)['name'], 'Browser');
    await h.expectError(
      'POST',
      'v1/auth/ticket',
      400,
      'invalid_ticket',
      data: {'ticket': ticket},
    );
    final expired = h.server.auth.ticket(h.adminUser!);
    h.store.db.execute('UPDATE grants SET expires_at = 0');
    await h.expectError(
      'POST',
      'v1/auth/ticket',
      400,
      'invalid_ticket',
      data: {'ticket': expired},
    );
  });

  test(
    'deleting a user cascades devices, records, identities, grants, providers and blob files',
    () async {
      h = Harness();
      final user = h.addUser('ana');
      final token = h.token(user);
      await h.provider(token: token);
      h.store.push(h.store.deviceForToken(token)!, [
        const SyncChange(
          collection: 'memories',
          id: 'r1',
          baseVersion: 0,
          data: {},
        ),
      ]);
      h.store.addBlob(user, 'hash', 1);
      final directory = Directory('${h.temp.path}/blobs/${user.id}')
        ..createSync(recursive: true);
      File('${directory.path}/blob').writeAsStringSync('private blob');
      h.server.auth.ticket(user);
      h.store.db.execute(
        'INSERT INTO identities VALUES (?, ?, ?, ?, ?, ?, ?)',
        ['identity', user.id, 'github', 'sub', 'email', 'name', 0],
      );
      await h.jsonCall('DELETE', 'v1/admin/users/${user.id}', asAdmin: true);
      expect(h.store.userById(user.id), isNull);
      expect(directory.existsSync(), false);
      for (final table in [
        'devices',
        'records',
        'blobs',
        'identities',
        'grants',
      ]) {
        expect(
          h.store.db.select('SELECT * FROM $table WHERE user_id = ?', [
            user.id,
          ]),
          isEmpty,
        );
      }
      expect(
        h.store.db.select('SELECT * FROM providers WHERE owner_id = ?', [
          user.id,
        ]),
        isEmpty,
      );
      await h.expectError('GET', 'v1/me', 401, 'unauthorized', token: token);
    },
  );

  test(
    'administrator guards, settings lock, users and profile/password updates',
    () async {
      h = Harness(
        config: const DenConfig(
          publicUrl: 'https://fixed.test',
          publicUrlLocked: true,
        ),
      );
      final user = h.addUser('ana');
      final token = h.token(user);
      for (final path in [
        'settings',
        'users',
        'providers',
        'oauth',
        'invites',
        'usage',
      ]) {
        await h.expectError(
          'GET',
          'v1/admin/$path',
          403,
          'forbidden',
          token: token,
        );
      }
      await h.expectError(
        'PATCH',
        'v1/admin/settings',
        400,
        'read_only',
        asAdmin: true,
        data: {'publicUrl': 'https://other.test'},
      );
      await h.expectError(
        'PATCH',
        'v1/admin/users/${h.adminUser!.id}',
        400,
        'last_admin',
        asAdmin: true,
        data: {'role': 'user'},
      );
      await h.expectError(
        'PATCH',
        'v1/admin/users/${h.adminUser!.id}',
        400,
        'last_admin',
        asAdmin: true,
        data: {'disabled': true},
      );
      await h.expectError(
        'DELETE',
        'v1/admin/users/${h.adminUser!.id}',
        400,
        'last_admin',
        asAdmin: true,
      );
      await h.jsonCall(
        'PATCH',
        'v1/me',
        token: token,
        data: {'displayName': 'Ana'},
      );
      await h.expectError(
        'POST',
        'v1/me/password',
        403,
        'invalid_login',
        token: token,
        data: {'newPassword': 'newPassword123'},
      );
      await h.jsonCall(
        'POST',
        'v1/me/password',
        token: token,
        data: {
          'currentPassword': 'password123',
          'newPassword': 'newPassword123',
        },
      );
      await h.jsonCall(
        'POST',
        'v1/auth/login',
        data: {'username': 'ana', 'password': 'newPassword123'},
      );
      final second = await h.jsonCall(
        'POST',
        'v1/admin/users',
        asAdmin: true,
        data: {
          'username': 'owner2',
          'password': 'password123',
          'role': 'admin',
        },
      );
      expect(second['effectivePermissions'], {
        'useSharedProviders': true,
        'ownProviders': true,
        'dailyTokenLimit': null,
      });
      await h.jsonCall(
        'PATCH',
        'v1/admin/users/${h.adminUser!.id}',
        asAdmin: true,
        data: {'role': 'user'},
      );
      await h.expectError(
        'GET',
        'v1/admin/settings',
        403,
        'forbidden',
        asAdmin: true,
      );
    },
  );

  test('permission defaults/overrides and events update immediately', () async {
    h = Harness();
    final user = h.addUser('ana');
    final token = h.token(user);
    final response = await h.call('GET', 'v1/events', token: token);
    final events = <String>[];
    final ready = Completer<void>();
    final subscription = response.read().transform(utf8.decoder).listen((
      chunk,
    ) {
      events.add(chunk);
      if (!ready.isCompleted) ready.complete();
    });
    await ready.future;
    await h.jsonCall(
      'PATCH',
      'v1/admin/settings',
      asAdmin: true,
      data: {
        'defaultPermissions': {
          'useSharedProviders': false,
          'ownProviders': false,
          'dailyTokenLimit': 10,
        },
      },
    );
    await h.jsonCall(
      'PATCH',
      'v1/admin/users/${user.id}',
      asAdmin: true,
      data: {
        'permissions': {'ownProviders': true, 'dailyTokenLimit': 20},
      },
    );
    final me = (await h.jsonCall('GET', 'v1/me', token: token))['user'] as Map;
    expect(me['permissions'], {
      'useSharedProviders': false,
      'ownProviders': true,
      'dailyTokenLimit': 20,
    });
    await h.jsonCall(
      'PATCH',
      'v1/admin/users/${user.id}',
      asAdmin: true,
      data: {
        'permissions': {'dailyTokenLimit': null},
      },
    );
    expect(
      ((await h.jsonCall('GET', 'v1/me', token: token))['user']
          as Map)['permissions'],
      {
        'useSharedProviders': false,
        'ownProviders': true,
        'dailyTokenLimit': 10,
      },
    );
    await Future<void>.delayed(Duration.zero);
    expect(events.join(), contains('event: models'));
    expect(events.join(), contains('event: account'));
    await subscription.cancel();
  });
}
