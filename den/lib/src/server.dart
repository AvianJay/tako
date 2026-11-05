import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:qr/qr.dart';
import 'package:shelf/shelf.dart';

import 'body.dart';
import 'api.dart' as api;
import 'account_store.dart';
import 'admin.dart';
import 'auth.dart';
import 'grants.dart';
import 'invites.dart';
import 'network_guard.dart';
import 'oauth.dart';
import 'oauth_store.dart';
import 'profile.dart';
import 'providers.dart';
import 'secrets.dart';
import 'settings.dart';
import 'config.dart';
import 'events.dart';
import 'gateway.dart';
import 'store.dart';
import 'web.dart';

const serverVersion = '0.2.0';

/// The largest file body accepted at `PUT /v1/blobs/<sha256>`.
const maxBlobBytes = 64 * 1024 * 1024;

final class DenServer {
  DenServer({
    required this.config,
    required this.store,
    required this.blobDir,
    Gateway? gateway,
    Secrets? secrets,
    http.Client? oauthClient,
    HostResolver? resolver,
  }) : gateway = gateway ?? Gateway(config.upstreams, store) {
    final databaseFile =
        store.db.select('PRAGMA database_list').first['file'] as String;
    this.secrets =
        secrets ??
        (databaseFile.isEmpty
            ? Secrets.memory()
            : Secrets.load(
                p.dirname(databaseFile),
                encodedKey: config.secretKey,
              ));
    settings = Settings(store, config);
    accounts = AccountStore(store);
    grants = Grants(store);
    invites = Invites(store, this.secrets);
    auth = Auth(store, settings, invites, grants, config);
    providers = Providers(
      store,
      settings,
      this.secrets,
      NetworkGuard(resolver: resolver),
      config.upstreams,
    );
    this.gateway.configure(providers);
    oauthStore = OAuthStore(store, settings, this.secrets, config.oauth);
    oauth = OAuth(store, oauthStore, auth, grants, client: oauthClient);
    admin = Admin(
      store,
      settings,
      accounts,
      providers,
      oauthStore,
      invites,
      events,
      this.gateway,
      blobDir,
    );
    profile = Profile(store, admin, oauth, oauthStore, events);
  }

  final DenConfig config;
  final Store store;
  final String blobDir;
  final Gateway gateway;
  final events = EventHub();
  late final Secrets secrets;
  late final Settings settings;
  late final AccountStore accounts;
  late final Grants grants;
  late final Invites invites;
  late final Auth auth;
  late final Providers providers;
  late final OAuthStore oauthStore;
  late final OAuth oauth;
  late final Admin admin;
  late final Profile profile;
  String? get setupToken => auth.setupToken;

  Handler get handler =>
      const Pipeline().addMiddleware(_errors).addHandler(_route);

  Future<Response> _route(Request request) async {
    final path = request.url.path;
    final method = request.method;

    if (method == 'GET' &&
        path != 'v1' &&
        !path.startsWith('v1/') &&
        path != 'healthz') {
      return serveWeb(request, config.webDir);
    }
    if (path == 'healthz' && method == 'GET') {
      return Response.ok('ok', headers: {'content-type': 'text/plain'});
    }
    if (method == 'GET' && path == 'v1/info') return _info();
    if (method == 'POST') {
      switch (path) {
        case 'v1/setup':
          return auth.setup(request);
        case 'v1/auth/login':
          return auth.login(request);
        case 'v1/auth/register':
          return auth.register(request);
        case 'v1/auth/device':
          return auth.startDevice(request);
        case 'v1/auth/device/poll':
          return auth.poll(request);
        case 'v1/auth/ticket':
          return auth.redeemTicket(request);
        case 'v1/pair/claim':
          return _claim(request);
      }
    }
    final parts = request.url.pathSegments;
    if (method == 'GET' &&
        parts.length == 5 &&
        parts.take(3).join('/') == 'v1/auth/oauth') {
      auth.limiter.check('oauth:${auth.address(request)}', limit: 60);
      if (parts[4] == 'start') {
        final url = await oauth.start(parts[3], request.url.queryParameters);
        return Response.found(url, headers: oauth.browserHeaders(url));
      }
      if (parts[4] == 'callback') {
        return oauth.callback(
          parts[3],
          request.url.queryParameters,
          request.headers['cookie'] ?? '',
        );
      }
    }

    final device = _authenticate(request);
    if (device == null) {
      return _error(401, 'unauthorized', 'Sign in or pair this device first.');
    }

    if (device.user.disabled) return api.error(403, 'account_disabled');
    if (path.startsWith('v1/admin/')) return admin.route(request, device.user);
    if (parts.length >= 4 &&
        parts.take(3).join('/') == 'v1/auth/device' &&
        parts.length <= 5) {
      return auth.device(
        request,
        device.user,
        parts[3],
        parts.length == 5 ? parts[4] : null,
      );
    }
    final profileResponse = await profile.route(request, device.user);
    if (profileResponse != null) return profileResponse;

    switch ((method, path)) {
      case ('GET', 'v1/me'):
        return _json({
          'user': device.user.toJson(),
          'device': {'id': device.id, 'name': device.name},
          'seq': store.currentSeq(device.user),
        });
      case ('POST', 'v1/auth/logout'):
        store.deleteDevice(device.user, device.id);
        return _json({'ok': true});
      case ('GET', 'v1/devices'):
        return _json({
          'devices': store.listDevices(device.user),
          'current': device.id,
        });
      // A key for another app, such as Tako's provider settings.
      case ('POST', 'v1/devices'):
        final body = await _body(request);
        final (created, token) = store.createDevice(
          device.user,
          api.string(body, 'name', fallback: 'Tako app', max: 64),
        );
        return _json(_session(created, token));
      case ('POST', 'v1/pair/codes'):
        return _pairCode(request, device);
      case ('POST', 'v1/sync/push'):
        return _push(request, device);
      case ('GET', 'v1/sync/pull'):
        return _pull(request, device);
      case ('GET', 'v1/events'):
        return Response.ok(
          events.subscribe(device.user.id),
          headers: {
            'content-type': 'text/event-stream',
            'cache-control': 'no-cache',
          },
          context: {'shelf.io.buffer_output': false},
        );
      case ('GET', 'v1/models'):
        return gateway.models(device.user);
      case ('POST', 'v1/chat/completions'):
        return gateway.chatCompletions(request, device);
      case ('GET', 'v1/usage'):
        return _json({
          'usage': store.usage(device.user),
          'today': {
            'sharedTokens': accounts.sharedToday(device.user),
            'limit': device.user.permissions['dailyTokenLimit'],
          },
        });
    }
    if (method == 'DELETE' && path.startsWith('v1/devices/')) {
      final removed = store.deleteDevice(
        device.user,
        path.substring('v1/devices/'.length),
      );
      return removed
          ? _json({'ok': true})
          : _error(404, 'not_found', 'No such device.');
    }
    if (path.startsWith('v1/blobs/')) {
      final hash = path.substring('v1/blobs/'.length);
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
        return _error(400, 'invalid_hash', 'Use the lowercase SHA-256.');
      }
      if (method == 'PUT') return _putBlob(request, device, hash);
      if (method == 'GET' || method == 'HEAD') {
        return _getBlob(device, hash, head: method == 'HEAD');
      }
    }
    return _error(404, 'not_found', 'No such route.');
  }

  Device? _authenticate(Request request) {
    final header = request.headers['authorization'] ?? '';
    if (!header.toLowerCase().startsWith('bearer ')) return null;
    return store.deviceForToken(header.substring(7).trim());
  }

  Response _info() => _json({
    'name': settings.data['serverName'],
    'version': serverVersion,
    'setupRequired': store.userCount == 0,
    'registration': settings.registration,
    'passwordLogin': settings.passwordLogin,
    'oauth': [
      for (final provider in oauthStore.providers)
        if (provider.enabled)
          {
            'id': provider.id,
            'type': provider.type,
            'name': provider.data['name'],
          },
    ],
    'features': [
      'sync',
      'gateway',
      'pairing',
      'events',
      'blobs',
      'device-login',
      'oauth',
    ],
  });

  Future<Response> _pairCode(Request request, Device device) async {
    final code = store.createPairCode(device.user);
    final server = settings.publicUrl ?? request.requestedUri.origin;
    final uri = Uri(
      scheme: 'tako',
      host: 'den',
      path: '/pair',
      queryParameters: {'server': server, 'code': code.code},
    ).toString();
    return _json({
      'code': code.code,
      'expiresAt': code.expiresAt.toUtc().toIso8601String(),
      'server': server,
      'uri': uri,
      'qrSvg': qrSvg(uri),
    });
  }

  Future<Response> _claim(Request request) async {
    final body = await _body(request, max: _signInBodyLimit);
    auth.limiter.check('pair:${auth.address(request)}');
    final claimed = store.claimPairCode(
      api.string(body, 'code', fallback: ''),
      api.string(body, 'deviceName', fallback: 'Phone', max: 64),
    );
    if (claimed == null) {
      return _error(400, 'invalid_code', 'The code is wrong or has expired.');
    }
    return _json(_session(claimed.$1, claimed.$2));
  }

  Map<String, Object?> _session(Device device, String token) => {
    'token': token,
    'device': {'id': device.id, 'name': device.name},
    'user': device.user.toJson(),
  };

  Future<Response> _push(Request request, Device device) async {
    final body = await _body(request);
    final list = body['changes'];
    if (list is! List || list.isEmpty || list.length > 500) {
      return _error(400, 'invalid_changes', 'Send 1 to 500 changes.');
    }
    final changes = <SyncChange>[];
    for (final item in list) {
      if (item is! Map) {
        return _error(400, 'invalid_changes', 'Each change is an object.');
      }
      if (item['baseVersion'] != null && item['baseVersion'] is! int) {
        return api.error(400, 'invalid_changes');
      }
      if (item['collection'] is! String ||
          item['id'] is! String ||
          (item.containsKey('deleted') && item['deleted'] is! bool)) {
        return api.error(400, 'invalid_changes');
      }
      changes.add(
        SyncChange(
          collection: '${item['collection'] ?? ''}',
          id: '${item['id'] ?? ''}',
          baseVersion: (item['baseVersion'] as num?)?.toInt() ?? 0,
          deleted: item['deleted'] == true,
          data: item['data'],
        ),
      );
    }
    final results = store.push(device, changes);
    final seq = store.currentSeq(device.user);
    if (results.any((r) => r is PushApplied)) {
      events.publish(device.user.id, 'sync', {
        'seq': seq,
        'deviceId': device.id,
      });
    }
    return _json({
      'seq': seq,
      'results': [
        for (final result in results)
          switch (result) {
            PushApplied(:final record) => {
              'status': 'ok',
              'collection': record.collection,
              'id': record.id,
              'version': record.version,
              'seq': record.seq,
            },
            PushConflict(:final collection, :final id, :final current) => {
              'status': 'conflict',
              'collection': collection,
              'id': id,
              'current': current?.toJson(),
            },
            PushRejected(:final collection, :final id, :final reason) => {
              'status': 'rejected',
              'collection': collection,
              'id': id,
              'reason': reason,
            },
          },
      ],
    });
  }

  Response _pull(Request request, Device device) {
    final query = request.url.queryParameters;
    final since = int.tryParse(query['since'] ?? '0');
    final limit = int.tryParse(query['limit'] ?? '500');
    if (since == null ||
        since < 0 ||
        limit == null ||
        limit < 1 ||
        limit > 1000) {
      return api.error(400, 'invalid_request');
    }
    final collections = query['collections']?.split(',').toSet();
    final page = store.pull(
      device.user,
      since: since,
      limit: limit,
      collections: collections,
    );
    return _json({
      'changes': [for (final r in page.records) r.toJson()],
      'seq': page.seq,
      'more': page.more,
      if (page.reset) 'reset': true,
    });
  }

  File _blobFile(Device device, String hash) =>
      File(p.join(blobDir, device.user.id, hash.substring(0, 2), hash));

  Future<Response> _putBlob(Request request, Device device, String hash) async {
    final file = _blobFile(device, hash);
    if (store.hasBlob(device.user, hash) && file.existsSync()) {
      var length = 0;
      await for (final chunk in request.read()) {
        length += chunk.length;
        if (length > maxBlobBytes) return api.error(413, 'blob_too_large');
      }
      return _json({'ok': true, 'existed': true});
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in request.read()) {
      bytes.add(chunk);
      if (bytes.length > maxBlobBytes) {
        return _error(413, 'blob_too_large', 'Files are limited to 64 MB.');
      }
    }
    final data = bytes.takeBytes();
    if (sha256.convert(data).toString() != hash) {
      return _error(400, 'hash_mismatch', 'The body does not match its hash.');
    }
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.${newId()}.tmp');
    await temp.writeAsBytes(data, flush: true);
    await temp.rename(file.path);
    store.addBlob(device.user, hash, data.length);
    return _json({'ok': true, 'size': data.length});
  }

  Response _getBlob(Device device, String hash, {required bool head}) {
    final file = _blobFile(device, hash);
    if (!store.hasBlob(device.user, hash) || !file.existsSync()) {
      return _error(404, 'not_found', 'No such blob.');
    }
    return Response.ok(
      head ? null : file.openRead(),
      headers: {
        'content-type': 'application/octet-stream',
        'content-length': '${file.lengthSync()}',
        'cache-control': 'private, max-age=31536000, immutable',
      },
    );
  }

  Future<void> close() async {
    await events.close();
    gateway.close();
    oauth.close();
  }
}

Middleware get _errors =>
    (inner) => (request) async {
      try {
        return await inner(request);
      } on BodyTooLarge catch (e) {
        return _error(
          413,
          'body_too_large',
          'Bodies are limited to ${e.limit} bytes here.',
        );
      } on api.ApiException catch (e) {
        return api.error(e.status, e.code);
      } on StoreException catch (e) {
        return api.error(e.code == 'account_disabled' ? 403 : 400, e.code);
      } on FormatException {
        return _error(400, 'invalid_json', 'The request body is not JSON.');
      } on Object {
        // Never log request paths, upstream exceptions or bodies: they may hold credentials.
        return _error(500, 'internal_error', 'Something went wrong.');
      }
    };

/// Routes open to anyone accept only small bodies.
const _signInBodyLimit = 64 * 1024;

Future<Map<String, Object?>> _body(
  Request request, {
  int max = 16 * 1024 * 1024,
}) async {
  final value = jsonDecode(await readBody(request, max));
  if (value is! Map<String, Object?>) throw const FormatException();
  return value;
}

/// The pairing link as an SVG, drawn here so the web page needs no script.
String qrSvg(String data) {
  final image = QrImage(
    QrCode(
      payload: QrPayload.fromString(data),
      errorCorrectLevel: QrErrorCorrectLevel.medium,
    ),
  );
  final size = image.moduleCount + 8;
  final path = StringBuffer();
  for (var y = 0; y < image.moduleCount; y++) {
    for (var x = 0; x < image.moduleCount; x++) {
      if (image.isDark(y, x)) path.write('M${x + 4} ${y + 4}h1v1h-1z');
    }
  }
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $size $size" '
      'shape-rendering="crispEdges"><rect width="$size" height="$size" '
      'fill="#fff"/><path d="$path" fill="#000"/></svg>';
}

Response _json(Object body, {int status = 200}) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
);

Response _error(int status, String code, String message) => _json({
  'error': {'code': code, 'message': message},
}, status: status);
