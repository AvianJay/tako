import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../util/json.dart';

/// A Den answered with an error, or could not be reached ([code]
/// `unreachable`). Branch on [code]; [message] is for people.
final class DenException implements Exception {
  const DenException(this.code, this.message, {this.status});
  final String code;
  final String message;
  final int? status;

  @override
  String toString() => message;
}

final class DenInfo {
  const DenInfo({
    required this.name,
    required this.version,
    required this.setupRequired,
    required this.registration,
    required this.passwordLogin,
    required this.oauth,
  });

  factory DenInfo.fromJson(JsonMap json) => DenInfo(
    name: asString(json['name']) ?? 'Tako Den',
    version: asString(json['version']) ?? '',
    setupRequired: asBool(json['setupRequired']) ?? false,
    registration: asString(json['registration']) ?? 'closed',
    passwordLogin: asBool(json['passwordLogin']) ?? true,
    oauth: [
      for (final item in asList(json['oauth']) ?? const [])
        if (asMap(item) case final m?)
          if (asString(m['id']) case final id?)
            (id: id, name: asString(m['name']) ?? id),
    ],
  );

  final String name;
  final String version;
  final bool setupRequired;

  /// `closed`, `invite` or `open`.
  final String registration;
  final bool passwordLogin;
  final List<({String id, String name})> oauth;
}

final class DenUser {
  const DenUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.isAdmin,
  });

  factory DenUser.fromJson(JsonMap json) => DenUser(
    id: asString(json['id']) ?? '',
    username: asString(json['username']) ?? '',
    displayName: asString(json['displayName']) ?? '',
    isAdmin: json['role'] == 'admin' || json['isAdmin'] == true,
  );

  final String id;
  final String username;
  final String displayName;
  final bool isAdmin;

  String get label => displayName.isEmpty ? username : displayName;

  JsonMap toJson() => {
    'id': id,
    'username': username,
    'displayName': displayName,
    'role': isAdmin ? 'admin' : 'user',
  };
}

final class DenSession {
  const DenSession({
    required this.token,
    required this.deviceId,
    required this.user,
  });

  factory DenSession.fromJson(JsonMap json) => DenSession(
    token: asString(json['token']) ?? '',
    deviceId: asString(asMap(json['device'])?['id']) ?? '',
    user: DenUser.fromJson(asMap(json['user']) ?? const {}),
  );

  final String token;
  final String deviceId;
  final DenUser user;
}

/// The first step of signing in through a browser.
final class DenDeviceLogin {
  const DenDeviceLogin({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.expiresIn,
    required this.interval,
  });

  final String deviceCode;
  final String userCode;
  final Uri verificationUrl;
  final Duration expiresIn;
  final Duration interval;

  /// The OAuth sign-in that continues to [verificationUrl]. Built on that
  /// URL's origin, the Den's public address, since the provider returns
  /// there and the browser keeps the sign-in's state cookie for it; the
  /// address typed into the app may be a different one, such as a LAN IP.
  Uri oauthStart(String providerId) {
    final segments = verificationUrl.pathSegments;
    final base = segments.isNotEmpty && segments.last == 'link'
        ? segments.sublist(0, segments.length - 1)
        : segments;
    return verificationUrl.replace(
      pathSegments: [...base, 'v1', 'auth', 'oauth', providerId, 'start'],
      queryParameters: {'device': userCode},
    );
  }
}

/// A synced record as the server stores it.
final class DenRecord {
  const DenRecord({
    required this.collection,
    required this.id,
    required this.version,
    required this.seq,
    required this.deleted,
    this.data,
    this.deviceId,
  });

  factory DenRecord.fromJson(JsonMap json) => DenRecord(
    collection: asString(json['collection']) ?? '',
    id: asString(json['id']) ?? '',
    version: asInt(json['version']) ?? 0,
    seq: asInt(json['seq']) ?? 0,
    deleted: asBool(json['deleted']) ?? false,
    data: asMap(json['data']),
    deviceId: asString(json['deviceId']),
  );

  final String collection;
  final String id;
  final int version;
  final int seq;
  final bool deleted;
  final JsonMap? data;
  final String? deviceId;
}

/// A local change on its way to the server.
final class DenChange {
  const DenChange({
    required this.collection,
    required this.id,
    required this.baseVersion,
    this.data,
  });

  final String collection;
  final String id;
  final int baseVersion;

  /// Null for a deletion.
  final JsonMap? data;

  JsonMap toJson() => {
    'collection': collection,
    'id': id,
    'baseVersion': baseVersion,
    if (data == null) 'deleted': true else 'data': data,
  };
}

sealed class DenPushResult {
  const DenPushResult(this.collection, this.id);
  final String collection;
  final String id;
}

final class DenPushed extends DenPushResult {
  const DenPushed(super.collection, super.id, this.version);
  final int version;
}

/// The server's copy changed since the base version; [current] is null when
/// the server has no such record.
final class DenPushConflict extends DenPushResult {
  const DenPushConflict(super.collection, super.id, this.current);
  final DenRecord? current;
}

final class DenPushRejected extends DenPushResult {
  const DenPushRejected(super.collection, super.id, this.reason);
  final String reason;
}

final class DenPullPage {
  const DenPullPage(
    this.records,
    this.seq, {
    this.more = false,
    this.reset = false,
  });
  final List<DenRecord> records;
  final int seq;
  final bool more;
  final bool reset;
}

/// One server-sent event from `GET /v1/events`.
final class DenEvent {
  const DenEvent(this.name, this.data);
  final String name;
  final JsonMap data;
}

/// Turns what a person types into a server address: adds a scheme (HTTP only
/// for addresses that stay inside a home network) and drops a pasted `/v1`.
Uri? normalizeDenUrl(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) {
    final host = text.split(RegExp('[:/]')).first;
    text = '${_isLocalHost(host) ? 'http' : 'https'}://$text';
  }
  final uri = Uri.tryParse(text);
  if (uri == null ||
      !(uri.scheme == 'http' || uri.scheme == 'https') ||
      uri.host.isEmpty) {
    return null;
  }
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path.endsWith('/v1')) path = path.substring(0, path.length - 3);
  // Not Uri.replace: a null query or fragment there keeps the old one.
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  );
}

bool _isLocalHost(String host) {
  final h = host.toLowerCase();
  if (h == 'localhost' || h.endsWith('.local') || !h.contains('.')) {
    return true;
  }
  final parts = h.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null)) return false;
  final [a!, b!, ...] = parts;
  return a == 10 ||
      a == 127 ||
      (a == 192 && b == 168) ||
      (a == 172 && b >= 16 && b <= 31) ||
      // Tailscale and other carrier-grade NAT addresses.
      (a == 100 && b >= 64 && b <= 127);
}

final class DenClient {
  DenClient(this.server, {this.token, http.Client? client})
    : _client = client ?? http.Client();

  final Uri server;
  final String? token;
  final http.Client _client;

  static const _timeout = Duration(seconds: 30);

  DenClient withToken(String token) =>
      DenClient(server, token: token, client: _client);

  Uri url(String path, [Map<String, String>? query]) => server.replace(
    path: '${server.path}/$path',
    queryParameters: query == null || query.isEmpty ? null : query,
  );

  Future<DenInfo> info() async {
    final json = await _send('GET', 'v1/info');
    if (json['name'] == null || json['version'] == null) {
      throw const DenException('not_den', 'This address is not a Tako Den.');
    }
    return DenInfo.fromJson(json);
  }

  Future<DenSession> login(
    String username,
    String password,
    String deviceName,
  ) async => DenSession.fromJson(
    await _send('POST', 'v1/auth/login', {
      'username': username,
      'password': password,
      'deviceName': deviceName,
    }),
  );

  Future<DenSession> register(
    String username,
    String password,
    String deviceName, {
    String? inviteCode,
  }) async => DenSession.fromJson(
    await _send('POST', 'v1/auth/register', {
      'username': username,
      'password': password,
      'deviceName': deviceName,
      if (inviteCode != null && inviteCode.isNotEmpty) 'inviteCode': inviteCode,
    }),
  );

  Future<DenSession> claimPairCode(String code, String deviceName) async =>
      DenSession.fromJson(
        await _send('POST', 'v1/pair/claim', {
          'code': code,
          'deviceName': deviceName,
        }),
      );

  Future<DenDeviceLogin> startDeviceLogin(
    String deviceName, {
    String? platform,
  }) async {
    final json = await _send('POST', 'v1/auth/device', {
      'deviceName': deviceName,
      'platform': ?platform,
    });
    return DenDeviceLogin(
      deviceCode: asString(json['deviceCode']) ?? '',
      userCode: asString(json['userCode']) ?? '',
      verificationUrl:
          Uri.tryParse(asString(json['verificationUrl']) ?? '') ?? url('link'),
      expiresIn: Duration(seconds: asInt(json['expiresIn']) ?? 600),
      interval: Duration(seconds: (asInt(json['interval']) ?? 3).clamp(1, 30)),
    );
  }

  /// Null while the user has not decided yet.
  Future<DenSession?> pollDeviceLogin(String deviceCode) async {
    final response = await _raw('POST', 'v1/auth/device/poll', {
      'deviceCode': deviceCode,
    });
    if (response.statusCode == 202) return null;
    return DenSession.fromJson(_decode(response));
  }

  /// The page that starts OAuth with [providerId] and then confirms the
  /// device sign-in [userCode].
  Future<({DenUser user, int seq})> me() async {
    final json = await _send('GET', 'v1/me');
    return (
      user: DenUser.fromJson(asMap(json['user']) ?? const {}),
      seq: asInt(json['seq']) ?? 0,
    );
  }

  Future<void> logout() => _send('POST', 'v1/auth/logout');

  Future<List<String>> models() async {
    final json = await _send('GET', 'v1/models');
    return [
      for (final item in asList(json['data']) ?? const [])
        ?asString(asMap(item)?['id']),
    ];
  }

  Future<List<DenPushResult>> push(List<DenChange> changes) async {
    final json = await _send('POST', 'v1/sync/push', {
      'changes': [for (final c in changes) c.toJson()],
    });
    return [
      for (final item in asList(json['results']) ?? const [])
        if (asMap(item) case final r?) _pushResult(r),
    ];
  }

  DenPushResult _pushResult(JsonMap r) {
    final collection = asString(r['collection']) ?? '';
    final id = asString(r['id']) ?? '';
    return switch (r['status']) {
      'ok' => DenPushed(collection, id, asInt(r['version']) ?? 0),
      'conflict' => DenPushConflict(
        collection,
        id,
        asMap(r['current']) == null
            ? null
            : DenRecord.fromJson(asMap(r['current'])!),
      ),
      _ => DenPushRejected(collection, id, asString(r['reason']) ?? 'rejected'),
    };
  }

  Future<DenPullPage> pull(int since, {int limit = 500}) async {
    final json = await _send('GET', 'v1/sync/pull', null, {
      'since': '$since',
      'limit': '$limit',
    });
    return DenPullPage(
      [
        for (final item in asList(json['changes']) ?? const [])
          if (asMap(item) case final r?) DenRecord.fromJson(r),
      ],
      asInt(json['seq']) ?? since,
      more: asBool(json['more']) ?? false,
      reset: asBool(json['reset']) ?? false,
    );
  }

  /// Server-sent events until the connection ends or [cancel] completes.
  Stream<DenEvent> events({Future<void>? cancel}) async* {
    final request = http.Request('GET', url('v1/events'))
      ..headers.addAll(_headers(json: false));
    final response = await _client.send(request).timeout(_timeout);
    if (response.statusCode != 200) {
      throw _error(response.statusCode, await response.stream.bytesToString());
    }
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final controller = StreamController<String>();
    final subscription = lines.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    unawaited(
      cancel?.then((_) => subscription.cancel()).then((_) {
        if (!controller.isClosed) controller.close();
      }),
    );
    var name = 'message';
    final data = StringBuffer();
    await for (final line in controller.stream) {
      if (line.isEmpty) {
        if (data.isNotEmpty) {
          yield DenEvent(name, tryDecodeObject(data.toString()) ?? const {});
        }
        name = 'message';
        data.clear();
      } else if (line.startsWith('event:')) {
        name = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        data.write(line.substring(5).trim());
      }
    }
  }

  void close() => _client.close();

  Map<String, String> _headers({bool json = true}) => {
    if (json) 'content-type': 'application/json',
    if (token != null) 'authorization': 'Bearer $token',
  };

  Future<http.Response> _raw(
    String method,
    String path, [
    JsonMap? body,
    Map<String, String>? query,
  ]) async {
    final request = http.Request(method, url(path, query))
      ..headers.addAll(_headers())
      ..followRedirects = false;
    if (body != null) request.body = jsonEncode(body);
    try {
      return await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      );
    } on DenException {
      rethrow;
    } on Object catch (e) {
      throw DenException('unreachable', '$e');
    }
  }

  Future<JsonMap> _send(
    String method,
    String path, [
    JsonMap? body,
    Map<String, String>? query,
  ]) async => _decode(await _raw(method, path, body, query));

  JsonMap _decode(http.Response response) {
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return tryDecodeObject(text) ?? const {};
    }
    throw _error(response.statusCode, text);
  }

  DenException _error(int status, String body) {
    final error = asMap(tryDecodeObject(body)?['error']);
    return DenException(
      asString(error?['code']) ?? 'http_$status',
      asString(error?['message']) ?? 'HTTP $status',
      status: status,
    );
  }
}
