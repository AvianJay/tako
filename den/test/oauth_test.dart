import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jose/jose.dart';
import 'package:tako_den/src/secrets.dart';
import 'package:tako_den/tako_den.dart';
import 'package:test/test.dart';

import 'support.dart';

final _signingKey = JsonWebKey.generate('RS256', keyBitLength: 2048);

final class FakeOAuth {
  String type = 'oidc';
  String subject = 'subject-1';
  String email = 'ana@example.test';
  String username = 'ana';
  Uri? authorization;
  final tokenRequests = <http.Request>[];
  Map<String, Object?> claims = {};
  bool wrongSignature = false;
  bool discoveryMismatch = false;
  bool basicAuth = false;

  late final client = MockClient((request) async {
    expect(request.followRedirects, false);
    if (request.url.path.endsWith('/.well-known/openid-configuration')) {
      return reply({
        'issuer': discoveryMismatch ? 'https://other.test' : 'https://id.test',
        'authorization_endpoint': 'https://id.test/authorize',
        'token_endpoint': 'https://id.test/token',
        'jwks_uri': 'https://id.test/keys',
        'token_endpoint_auth_methods_supported': [
          basicAuth ? 'client_secret_basic' : 'client_secret_post',
        ],
      });
    }
    if (request.url.path.endsWith('/keys') ||
        request.url.path.endsWith('/certs')) {
      final key = Map<String, Object?>.from(_signingKey.toJson())
        ..removeWhere((k, _) => ['d', 'p', 'q', 'dp', 'dq', 'qi'].contains(k));
      return reply({
        'keys': [key],
      });
    }
    if (request.method == 'POST') {
      tokenRequests.add(request);
      final form = request.bodyFields;
      expect(form['code_verifier'], isNotEmpty);
      expect(
        base64Url
            .encode(sha256.convert(utf8.encode(form['code_verifier']!)).bytes)
            .replaceAll('=', ''),
        authorization!.queryParameters['code_challenge'],
      );
      expect(
        form['redirect_uri'],
        'https://den.test/v1/auth/oauth/$type/callback',
      );
      if (basicAuth) {
        expect(
          request.headers['authorization'],
          'Basic ${base64.encode(utf8.encode('test-client:oauth-secret'))}',
        );
        expect(form.containsKey('client_secret'), false);
      } else {
        expect(form['client_secret'], 'oauth-secret');
      }
      final time = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final builder = JsonWebSignatureBuilder()
        ..jsonContent = {
          'iss': type == 'google'
              ? 'https://accounts.google.com'
              : 'https://id.test',
          'aud': 'test-client',
          'sub': subject,
          'exp': time + 300,
          'iat': time,
          'nonce': authorization!.queryParameters['nonce'],
          'email': email,
          'name': 'Ana',
          'preferred_username': username,
          ...claims,
        };
      builder.addRecipient(
        wrongSignature
            ? JsonWebKey.generate('RS256', keyBitLength: 2048)
            : _signingKey,
        algorithm: 'RS256',
      );
      return reply({
        'access_token': 'access-secret',
        'id_token': builder.build().toCompactSerialization(),
      });
    }
    expect(request.headers['authorization'], 'Bearer access-secret');
    return reply({
      'id': subject,
      'sub': subject,
      'preferred_username': username,
      'email': email,
      'name': 'Ana',
      'username': username,
      'login': username,
    });
  });

  http.Response reply(Object data) => http.Response(
    jsonEncode(data),
    200,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  late Harness h;
  late FakeOAuth fake;
  setUp(() {
    fake = FakeOAuth();
    h = Harness(oauth: fake.client);
  });
  tearDown(() => h.close());

  Future<void> add(String type) async {
    fake.type = type;
    await h.jsonCall(
      'POST',
      'v1/admin/oauth',
      asAdmin: true,
      data: {
        'type': type,
        'clientId': 'test-client',
        'clientSecret': 'oauth-secret',
        if (type == 'oidc') 'issuer': 'https://id.test',
      },
    );
  }

  Future<Uri> start(String type, {String extra = ''}) async {
    fake.type = type;
    final response = await h.call('GET', 'v1/auth/oauth/$type/start$extra');
    expect(response.statusCode, 302);
    fake.authorization = Uri.parse(response.headers['location']!);
    expect(fake.authorization!.queryParameters['state'], isNotEmpty);
    expect(
      fake.authorization!.queryParameters['code_challenge_method'],
      'S256',
    );
    return fake.authorization!;
  }

  Future<Uri> callback(String type, Uri authorization, {String? state}) async {
    final response = await h.call(
      'GET',
      'v1/auth/oauth/$type/callback?code=provider-code&state=${state ?? authorization.queryParameters['state']}',
    );
    expect(response.statusCode, 302);
    return Uri.parse(response.headers['location']!);
  }

  Future<Map<String, Object?>> redeem(Uri redirect) async {
    expect(redirect.path, '/oauth', reason: redirect.toString());
    return h.jsonCall(
      'POST',
      'v1/auth/ticket',
      data: {
        'ticket': redirect.queryParameters['ticket'],
        'deviceName': 'Browser',
      },
    );
  }

  for (final type in ['google', 'discord', 'github', 'oidc']) {
    test(
      '$type: signed-in session, PKCE, known identity and no email merging',
      () async {
        await add(type);
        await h.jsonCall(
          'PATCH',
          'v1/admin/settings',
          asAdmin: true,
          data: {'registration': 'open'},
        );
        final authorization = await start(type, extra: '?return=%2Fsettings');
        if (type == 'google' || type == 'oidc') {
          expect(authorization.queryParameters['nonce'], isNotEmpty);
        }
        final redirect = await callback(type, authorization);
        expect(redirect.queryParameters['return'], '/settings');
        final session = await redeem(redirect);
        final user = session['user'] as Map;
        expect(user['username'], 'ana');
        expect(user['hasPassword'], false);
        expect(user['role'], 'user');
        expect(fake.tokenRequests, hasLength(1));
        if (type == 'google') fake.claims = {'iss': 'accounts.google.com'};
        expect(
          h.store.db.select('SELECT * FROM grants').toString(),
          isNot(contains(authorization.queryParameters['state'])),
        );
        await h.jsonCall(
          'PATCH',
          'v1/admin/settings',
          asAdmin: true,
          data: {'registration': 'closed'},
        );
        final known = await redeem(await callback(type, await start(type)));
        expect((known['user'] as Map)['id'], user['id']);
        fake.subject = 'new-subject-same-email';
        final closed = await callback(type, await start(type));
        expect(closed.queryParameters['error'], 'registration_closed');
        await h.jsonCall(
          'PATCH',
          'v1/admin/settings',
          asAdmin: true,
          data: {'registration': 'open'},
        );
        final separate = await redeem(await callback(type, await start(type)));
        expect((separate['user'] as Map)['id'], isNot(user['id']));
        expect((separate['user'] as Map)['username'], 'ana1');
      },
    );
  }

  test(
    'OIDC supports issuers requiring HTTP Basic client authentication',
    () async {
      fake.basicAuth = true;
      await add('oidc');
      await h.jsonCall(
        'PATCH',
        'v1/admin/settings',
        asAdmin: true,
        data: {'registration': 'open'},
      );
      final result = await redeem(await callback('oidc', await start('oidc')));
      expect((result['user'] as Map)['hasPassword'], false);
    },
  );

  test(
    'state mismatch, provider mismatch, expiry, replay and browser binding',
    () async {
      await add('github');
      await add('discord');
      await h.jsonCall(
        'PATCH',
        'v1/admin/settings',
        asAdmin: true,
        data: {'registration': 'open'},
      );
      final first = await start('github');
      expect(
        (await callback(
          'github',
          first,
          state: 'wrong',
        )).queryParameters['error'],
        'invalid_state',
      );
      expect(fake.tokenRequests, isEmpty);
      final cookie = h.cookie;
      h.cookie = null;
      expect(
        (await callback('github', first)).queryParameters['error'],
        'invalid_state',
      );
      h.cookie = cookie;
      expect(
        (await callback('discord', first)).queryParameters['error'],
        'invalid_state',
      );
      expect(
        (await callback('github', first)).queryParameters['error'],
        'invalid_state',
      );
      final second = await start('github');
      await redeem(await callback('github', second));
      expect(
        (await callback('github', second)).queryParameters['error'],
        'invalid_state',
      );
      final expired = await start('github');
      h.store.db.execute('UPDATE grants SET expires_at = 0 WHERE kind = ?', [
        'oauth',
      ]);
      expect(
        (await callback('github', expired)).queryParameters['error'],
        'invalid_state',
      );
    },
  );

  test(
    'OIDC validates nonce, issuer, audience, expiry, issued time and signature',
    () async {
      await add('oidc');
      await h.jsonCall(
        'PATCH',
        'v1/admin/settings',
        asAdmin: true,
        data: {'registration': 'open'},
      );
      for (final badClaims in [
        {'nonce': 'wrong'},
        {'iss': 'https://other.test'},
        {'aud': 'another-client'},
        {'exp': 1},
        {'iat': 9999999999},
        {
          'aud': ['test-client', 'other'],
          'azp': 'other',
        },
        {'sub': ''},
      ]) {
        fake.claims = badClaims;
        expect(
          (await callback(
            'oidc',
            await start('oidc'),
          )).queryParameters['error'],
          'oauth_failed',
        );
      }
      fake.claims = {};
      fake.wrongSignature = true;
      expect(
        (await callback('oidc', await start('oidc'))).queryParameters['error'],
        'oauth_failed',
      );
      expect(h.store.userCount, 1);
    },
  );

  test(
    'OAuth invitation usage, disabled account and device continuation',
    () async {
      await add('google');
      await h.jsonCall(
        'PATCH',
        'v1/admin/settings',
        asAdmin: true,
        data: {'registration': 'invite'},
      );
      expect(
        (await callback(
          'google',
          await start('google'),
        )).queryParameters['error'],
        'invalid_invite',
      );
      final invite = await h.jsonCall(
        'POST',
        'v1/admin/invites',
        asAdmin: true,
        data: {},
      );
      final device = await h.jsonCall(
        'POST',
        'v1/auth/device',
        data: {'deviceName': 'Pixel'},
      );
      final authorization = await start(
        'google',
        extra: '?invite=${invite['code']}&device=${device['userCode']}',
      );
      final stateRows = h.store.db.select('SELECT * FROM grants').toString();
      expect(stateRows, isNot(contains(invite['code'])));
      expect(stateRows, isNot(contains(device['userCode'])));
      final redirect = await callback('google', authorization);
      expect(redirect.path, '/link');
      expect(redirect.queryParameters['code'], device['userCode']);
      final session = await h.jsonCall(
        'POST',
        'v1/auth/ticket',
        data: {'ticket': redirect.queryParameters['ticket']},
      );
      final user = session['user'] as Map;
      expect(h.store.db.select('SELECT uses FROM invites').single['uses'], 1);
      await h.jsonCall(
        'PATCH',
        'v1/admin/users/${user['id']}',
        asAdmin: true,
        data: {'disabled': true},
      );
      expect(
        (await callback(
          'google',
          await start('google'),
        )).queryParameters['error'],
        'account_disabled',
      );
      fake.subject = 'new-subject';
      expect(
        (await callback(
          'google',
          await start('google', extra: '?invite=${invite['code']}'),
        )).queryParameters['error'],
        'invalid_invite',
      );
    },
  );

  test(
    'linking, identity ownership conflict, unlink guard and adding a password',
    () async {
      await add('github');
      await h.jsonCall(
        'PATCH',
        'v1/admin/settings',
        asAdmin: true,
        data: {'registration': 'open'},
      );
      final signedIn = await redeem(
        await callback('github', await start('github')),
      );
      final token = signedIn['token'] as String;
      final identities =
          (await h.jsonCall(
                'GET',
                'v1/me/identities',
                token: token,
              ))['identities']
              as List;
      final identityId = (identities.single as Map)['id'];
      await h.expectError(
        'DELETE',
        'v1/me/identities/$identityId',
        400,
        'last_sign_in_method',
        token: token,
      );
      final linked = await h.jsonCall(
        'POST',
        'v1/me/identities/github/link',
        asAdmin: true,
      );
      fake.authorization = Uri.parse(linked['url'] as String);
      final conflict = await callback('github', fake.authorization!);
      expect(conflict.path, '/settings');
      expect(conflict.queryParameters['error'], 'identity_in_use');
      fake.subject = 'admin-identity';
      final second = await h.jsonCall(
        'POST',
        'v1/me/identities/github/link',
        asAdmin: true,
      );
      fake.authorization = Uri.parse(second['url'] as String);
      expect(
        (await callback(
          'github',
          fake.authorization!,
        )).queryParameters['linked'],
        'github',
      );
      expect(
        (await h.jsonCall(
              'GET',
              'v1/me/identities',
              asAdmin: true,
            ))['identities']
            as List,
        hasLength(1),
      );
      await h.jsonCall(
        'POST',
        'v1/me/password',
        token: token,
        data: {'newPassword': 'added-password'},
      );
      await h.jsonCall('DELETE', 'v1/me/identities/$identityId', token: token);
      await h.jsonCall(
        'POST',
        'v1/auth/login',
        data: {'username': 'ana', 'password': 'added-password'},
      );
    },
  );

  test(
    'return validation, public URL requirement, secrets, config read-only and discovery',
    () async {
      await add('oidc');
      final listed = await h.jsonCall('GET', 'v1/admin/oauth', asAdmin: true);
      expect(jsonEncode(listed), isNot(contains('oauth-secret')));
      expect(
        h.store.db.select('SELECT * FROM oauth_providers').toString(),
        isNot(contains('oauth-secret')),
      );
      expect(
        ((listed['providers'] as List).single as Map)['hasClientSecret'],
        true,
      );
      await h.jsonCall(
        'PATCH',
        'v1/admin/oauth/oidc',
        asAdmin: true,
        data: {'name': 'Identity'},
      );
      for (final path in [
        '//evil.test',
        '/\\evil.test',
        '/%2fevil.test',
        '/%5cevil.test',
        'https://evil.test',
        '/\nevil.test',
      ]) {
        await h.expectError(
          'GET',
          'v1/auth/oauth/oidc/start?return=${Uri.encodeQueryComponent(path)}',
          400,
          'invalid_return',
        );
      }
      fake.discoveryMismatch = true;
      await h.expectError(
        'GET',
        'v1/auth/oauth/oidc/start',
        400,
        'oauth_failed',
      );
      await h.jsonCall(
        'PATCH',
        'v1/admin/settings',
        asAdmin: true,
        data: {'publicUrl': null},
      );
      await h.expectError(
        'GET',
        'v1/auth/oauth/oidc/start',
        400,
        'public_url_required',
      );
      expect(
        ((await h.jsonCall('GET', 'v1/admin/oauth', asAdmin: true))['providers']
                    as List)
                .single
            as Map,
        containsPair('redirectUri', null),
      );
      final cleared = await h.jsonCall(
        'PATCH',
        'v1/admin/oauth/oidc',
        asAdmin: true,
        data: {'clientSecret': ''},
      );
      expect(cleared['hasClientSecret'], false);
      await h.jsonCall('DELETE', 'v1/admin/oauth/oidc', asAdmin: true);
      expect((await h.jsonCall('GET', 'v1/info'))['oauth'], isEmpty);
      final config = DenConfig.load(
        file: '${h.temp.path}/absent.yaml',
        environment: {
          'TAKO_OAUTH_GOOGLE_CLIENT_ID': 'id',
          'TAKO_OAUTH_GOOGLE_CLIENT_SECRET': 'config-secret',
          'TAKO_OAUTH_DISCORD_CLIENT_ID': 'discord-id',
          'TAKO_OAUTH_GITHUB_CLIENT_ID': 'github-id',
          'TAKO_OAUTH_OIDC_CLIENT_ID': 'oidc-id',
          'TAKO_OAUTH_OIDC_ISSUER': 'https://id.test',
          'TAKO_OAUTH_OIDC_NAME': 'Company',
        },
      );
      final other = Harness(config: config);
      addTearDown(other.close);
      expect(
        (await other.jsonCall('GET', 'v1/info'))['oauth'] as List,
        hasLength(4),
      );
      await other.expectError(
        'DELETE',
        'v1/admin/oauth/google',
        400,
        'read_only',
        asAdmin: true,
      );
      await other.expectError(
        'PATCH',
        'v1/admin/oauth/google',
        400,
        'read_only',
        asAdmin: true,
        data: {'enabled': false},
      );
      expect(
        jsonEncode(
          await other.jsonCall('GET', 'v1/admin/oauth', asAdmin: true),
        ),
        isNot(contains('config-secret')),
      );
    },
  );

  test(
    'deleting and re-adding an OAuth provider preserves identities',
    () async {
      await add('github');
      await h.jsonCall(
        'PATCH',
        'v1/admin/settings',
        asAdmin: true,
        data: {'registration': 'open'},
      );
      final first = await redeem(
        await callback('github', await start('github')),
      );
      await h.jsonCall('DELETE', 'v1/admin/oauth/github', asAdmin: true);
      expect(h.store.db.select('SELECT * FROM identities'), hasLength(1));
      await add('github');
      await h.jsonCall(
        'PATCH',
        'v1/admin/settings',
        asAdmin: true,
        data: {'registration': 'closed'},
      );
      final again = await redeem(
        await callback('github', await start('github')),
      );
      expect((again['user'] as Map)['id'], (first['user'] as Map)['id']);
      expect(
        h.store.db.select('SELECT * FROM grants').toString(),
        isNot(contains(digest('oauth-secret'))),
      );
    },
  );
}
