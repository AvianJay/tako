import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:jose/jose.dart';
import 'package:shelf/shelf.dart';

import 'api.dart';
import 'auth.dart';
import 'grants.dart';
import 'oauth_store.dart';
import 'secrets.dart';
import 'store.dart';

final class OAuth {
  OAuth(
    this.store,
    this.providers,
    this.auth,
    this.grants, {
    http.Client? client,
  }) : _client = client ?? http.Client();
  final Store store;
  final OAuthStore providers;
  final Auth auth;
  final Grants grants;
  final http.Client _client;

  Future<Map<String, Object?>> _request(
    String url, {
    Map<String, String>? form,
    String? token,
    String? basic,
  }) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.host.isEmpty) {
      fail(400, 'oauth_failed');
    }
    final request = http.Request(form == null ? 'GET' : 'POST', uri)
      ..followRedirects = false;
    request.headers.addAll({
      'accept': 'application/json',
      'user-agent': 'Tako-Den/0.2.0',
      if (token != null) 'authorization': 'Bearer $token',
      if (basic != null) 'authorization': 'Basic $basic',
    });
    if (form != null) request.bodyFields = form;
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      fail(400, 'oauth_failed');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > 1024 * 1024) fail(400, 'oauth_failed');
    }
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map<String, Object?>) fail(400, 'oauth_failed');
    return data;
  }

  Future<Map<String, Object?>> _endpoints(OAuthProvider provider) async {
    switch (provider.type) {
      case 'google':
        return {
          'issuer': 'https://accounts.google.com',
          'authorization_endpoint':
              'https://accounts.google.com/o/oauth2/v2/auth',
          'token_endpoint': 'https://oauth2.googleapis.com/token',
          'jwks_uri': 'https://www.googleapis.com/oauth2/v3/certs',
          'userinfo_endpoint':
              'https://openidconnect.googleapis.com/v1/userinfo',
        };
      case 'discord':
        return {
          'authorization_endpoint': 'https://discord.com/oauth2/authorize',
          'token_endpoint': 'https://discord.com/api/oauth2/token',
          'userinfo_endpoint': 'https://discord.com/api/users/@me',
        };
      case 'github':
        return {
          'authorization_endpoint': 'https://github.com/login/oauth/authorize',
          'token_endpoint': 'https://github.com/login/oauth/access_token',
          'userinfo_endpoint': 'https://api.github.com/user',
        };
      default:
        final issuer = provider.data['issuer'] as String;
        final data = await _request('$issuer/.well-known/openid-configuration');
        if (data['issuer'] != issuer) fail(400, 'oauth_failed');
        for (final key in [
          'authorization_endpoint',
          'token_endpoint',
          'jwks_uri',
        ]) {
          httpUrl(string(data, key), httpsOnly: true);
        }
        return data;
    }
  }

  Future<String> start(
    String id,
    Map<String, String> query, {
    User? linkUser,
  }) async {
    final provider = providers.get(id);
    if (!provider.enabled) fail(404, 'not_found');
    final redirect = providers.redirectUri(id);
    if (redirect == null) fail(400, 'public_url_required');
    final returnPath = localReturn(query['return']);
    final device = query['device'];
    if (device != null &&
        (device.length > 32 ||
            grants.get('device_user', normalizeCode(device)) == null)) {
      fail(404, 'not_found');
    }
    final endpoints = await _endpoints(provider);
    final verifier = randomToken();
    final nonce = randomToken();
    final state = grants.create('oauth', {
      'providerId': id,
      'return': returnPath,
      'device': device == null
          ? null
          : await providers.secrets.encrypt(device, 'device:$nonce'),
      'invite': digest(query['invite'] ?? ''),
      'verifier': await providers.secrets.encrypt(verifier, 'pkce:$nonce'),
      'nonce': nonce,
      'redirect': redirect,
      'endpoints': endpoints,
      'providerFingerprint': digest(jsonEncode(provider.data)),
    }, userId: linkUser?.id);
    final challenge = base64Url
        .encode(hexBytes(digest(verifier)))
        .replaceAll('=', '');
    return Uri.parse(endpoints['authorization_endpoint'] as String)
        .replace(
          queryParameters: {
            'client_id': provider.clientId,
            'redirect_uri': redirect,
            'response_type': 'code',
            'scope': (provider.data['scopes'] as List).join(' '),
            'state': state,
            'code_challenge': challenge,
            'code_challenge_method': 'S256',
            if (['google', 'oidc'].contains(provider.type)) 'nonce': nonce,
          },
        )
        .toString();
  }

  Future<Map<String, Object?>> _identity(
    OAuthProvider provider,
    Map<String, Object?> state,
    String code,
  ) async {
    final endpoints = state['endpoints'] as Map;
    final verifier = await providers.secrets.decrypt(
      state['verifier'] as String,
      'pkce:${state['nonce']}',
    );
    final clientSecret = await providers.secret(provider);
    final methods = endpoints['token_endpoint_auth_methods_supported'];
    final basic =
        provider.type == 'oidc' &&
        (methods == null ||
            (methods is List &&
                !methods.contains('client_secret_post') &&
                methods.contains('client_secret_basic')));
    final token = await _request(
      endpoints['token_endpoint'] as String,
      basic: basic
          ? base64.encode(
              utf8.encode(
                '${Uri.encodeQueryComponent(provider.clientId)}:${Uri.encodeQueryComponent(clientSecret)}',
              ),
            )
          : null,
      form: {
        'grant_type': 'authorization_code',
        'code': code,
        'client_id': provider.clientId,
        if (!basic) 'client_secret': clientSecret,
        'redirect_uri': state['redirect'] as String,
        'code_verifier': verifier,
      },
    );
    if (['google', 'oidc'].contains(provider.type)) {
      final jwks = await _request(endpoints['jwks_uri'] as String);
      final keys = JsonWebKeyStore();
      for (final key in jwks['keys'] as List) {
        if (key is Map<String, Object?> &&
            ['RSA', 'EC'].contains(key['kty']) &&
            (key['use'] == null || key['use'] == 'sig')) {
          keys.addKey(JsonWebKey.fromJson(key));
        }
      }
      final jwt = await JsonWebToken.decodeAndVerify(
        string(token, 'id_token', max: 65536),
        keys,
        allowedArguments: [
          'RS256',
          'RS384',
          'RS512',
          'ES256',
          'ES384',
          'ES512',
        ],
      );
      final claims = jwt.claims;
      final seconds = now() ~/ 1000;
      final audience = claims.audience ?? [];
      // Google documents both forms; generic OIDC must match discovery exactly.
      final issuerMatches =
          claims['iss'] == endpoints['issuer'] ||
          (provider.type == 'google' && claims['iss'] == 'accounts.google.com');
      if (!issuerMatches ||
          !audience.contains(provider.clientId) ||
          (audience.length > 1 && claims['azp'] != provider.clientId) ||
          (claims['azp'] != null && claims['azp'] != provider.clientId) ||
          claims['exp'] is! num ||
          (claims['exp'] as num) <= seconds ||
          claims['iat'] is! num ||
          (claims['iat'] as num) > seconds + 60 ||
          (claims['nbf'] is num && (claims['nbf'] as num) > seconds + 60) ||
          claims['nonce'] is! String ||
          !constantTimeEquals(
            utf8.encode(digest(claims['nonce'] as String)),
            utf8.encode(digest(state['nonce'] as String)),
          ) ||
          claims.subject == null ||
          claims.subject!.isEmpty) {
        fail(400, 'oauth_failed');
      }
      final info = endpoints['userinfo_endpoint'] is String
          ? await _request(
              endpoints['userinfo_endpoint'] as String,
              token: string(token, 'access_token'),
            )
          : <String, Object?>{};
      if (info.isNotEmpty && info['sub'] != claims.subject) {
        fail(400, 'oauth_failed');
      }
      return {
        'subject': claims.subject,
        'email': info['email'] ?? claims['email'],
        'name': info['name'] ?? claims['name'],
        'username': info['preferred_username'] ?? claims['preferred_username'],
      };
    }
    final identity = await _request(
      endpoints['userinfo_endpoint'] as String,
      token: string(token, 'access_token'),
    );
    final subject = identity['id'];
    if ((subject is! String && subject is! int) || '$subject'.isEmpty) {
      fail(400, 'oauth_failed');
    }
    return {
      'subject': '$subject',
      'email': identity['email'],
      'name': identity['name'] ?? identity['global_name'],
      'username': identity['login'] ?? identity['username'],
    };
  }

  Map<String, String> browserHeaders(String url) {
    final state = Uri.parse(url).queryParameters['state']!;
    return {
      'cache-control': 'no-store',
      'referrer-policy': 'no-referrer',
      'set-cookie':
          'tako_oauth=${digest(state)}; HttpOnly; SameSite=Lax; Path=/v1/auth/oauth; Max-Age=600${providers.settings.publicUrl?.startsWith('https:') == true ? '; Secure' : ''}',
    };
  }

  Future<Response> callback(
    String id,
    Map<String, String> query,
    String cookie,
  ) async {
    final expected = digest(query['state'] ?? '');
    final actual =
        cookie
            .split(';')
            .map((c) => c.trim())
            .where((c) => c.startsWith('tako_oauth='))
            .firstOrNull
            ?.substring(11) ??
        '';
    if (!constantTimeEquals(utf8.encode(expected), utf8.encode(actual))) {
      return _redirect('/login', {'error': 'invalid_state'});
    }
    final state = grants.get('oauth', query['state'] ?? '', consume: true);
    if (state == null || state['providerId'] != id) {
      return _redirect('/login', {'error': 'invalid_state'});
    }
    final linking = state['userId'] != null;
    try {
      if (query['error'] != null || (query['code']?.isEmpty ?? true)) {
        fail(400, 'access_denied');
      }
      final provider = providers.get(id);
      if (!provider.enabled ||
          digest(jsonEncode(provider.data)) != state['providerFingerprint']) {
        fail(400, 'oauth_failed');
      }
      final identity = await _identity(provider, state, query['code']!);
      final subject = identity['subject'] as String;
      final rows = store.db.select(
        'SELECT user_id FROM identities WHERE provider_id = ? AND subject = ?',
        [id, subject],
      );
      final owner = rows.isEmpty ? null : rows.first['user_id'] as String;
      User user;
      if (linking) {
        user =
            store.userById(state['userId'] as String) ??
            (throw const ApiException(403, 'account_disabled'));
        if (owner != null && owner != user.id) fail(400, 'identity_in_use');
      } else if (owner != null) {
        user = store.userById(owner)!;
      } else {
        final hint =
            identity['username'] ??
            (identity['email'] is String
                ? (identity['email'] as String).split('@').first
                : 'user');
        var name = '$hint'
            .replaceAll(RegExp('[^A-Za-z0-9_.-]'), '')
            .toLowerCase();
        if (name.length < 2) name = 'user';
        if (name.length > 24) name = name.substring(0, 24);
        final base = name;
        var suffix = 1;
        while (store.db.select('SELECT 1 FROM users WHERE username = ?', [
          name,
        ]).isNotEmpty) {
          name = '$base${suffix++}';
        }
        user = auth.registerUser(
          name,
          null,
          _text(identity['name'], fallback: name),
          state['invite'] as String,
          inviteHashed: true,
        );
      }
      if (user.disabled) fail(403, 'account_disabled');
      if (owner == null) {
        store.db.execute(
          'INSERT INTO identities (id, user_id, provider_id, subject, email, name, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            newId(),
            user.id,
            id,
            subject,
            _text(identity['email']),
            _text(identity['name']),
            now(),
          ],
        );
      }
      if (linking) return _redirect('/settings', {'linked': id});
      final ticket = auth.ticket(user);
      if (state['device'] case final String encryptedDevice) {
        final device = await providers.secrets.decrypt(
          encryptedDevice,
          'device:${state['nonce']}',
        );
        return _redirect('/link', {'code': device, 'ticket': ticket});
      }
      return _redirect('/oauth', {
        'ticket': ticket,
        'return': localReturn(state['return'] as String?),
      });
    } on ApiException catch (e) {
      return _redirect(linking ? '/settings' : '/login', {'error': e.code});
    } on Object {
      return _redirect(linking ? '/settings' : '/login', {
        'error': 'oauth_failed',
      });
    }
  }

  void close() => _client.close();
}

List<int> hexBytes(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];
String _text(Object? value, {String fallback = ''}) =>
    value is String ? value.substring(0, value.length.clamp(0, 128)) : fallback;
Response _redirect(String path, Map<String, String> query) => Response.found(
  Uri(path: path, queryParameters: query).toString(),
  headers: {'cache-control': 'no-store', 'referrer-policy': 'no-referrer'},
);
