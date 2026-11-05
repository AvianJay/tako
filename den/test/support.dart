import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:tako_den/src/network_guard.dart';
import 'package:tako_den/tako_den.dart';
import 'package:test/test.dart';

final _passwordHash = hashPassword('password123');

final class Harness {
  Harness({
    DenConfig config = const DenConfig(publicUrl: 'https://den.test'),
    bool admin = true,
    http.Client? upstream,
    http.Client? oauth,
    HostResolver? resolver,
    Store? database,
  }) {
    final root = Directory('build/test')..createSync(recursive: true);
    temp = root.createTempSync('v1_');
    store = database ?? Store.memory();
    if (admin) {
      adminUser = addUser('admin', admin: true);
      adminToken = store.createDevice(adminUser!, 'Admin browser').$2;
    }
    server = DenServer(
      config: config,
      store: store,
      blobDir: '${temp.path}/blobs',
      resolver: resolver ?? (_) async => [InternetAddress('8.8.8.8')],
      oauthClient: oauth,
      gateway: Gateway(
        config.upstreams,
        store,
        client:
            upstream ??
            MockClient((request) async {
              requests.add(request);
              if (request.url.path.endsWith('/models')) {
                return http.Response(
                  '{"data":[{"id":"model"},{"id":"org/model"}]}',
                  200,
                );
              }
              return http.Response(
                '{"choices":[],"usage":{"prompt_tokens":6,"completion_tokens":4}}',
                200,
              );
            }),
      ),
    );
  }
  late final Directory temp;
  late final Store store;
  late final DenServer server;
  User? adminUser;
  String? adminToken;
  final requests = <http.Request>[];
  String? cookie;

  User addUser(String name, {bool admin = false, bool password = true}) {
    final user = store.createUser(name, null, isAdmin: admin);
    if (password) {
      store.db.execute('UPDATE users SET password_hash = ? WHERE id = ?', [
        _passwordHash,
        user.id,
      ]);
    }
    return store.userById(user.id)!;
  }

  String token(User user) => store.createDevice(user, 'Test device').$2;

  Future<Response> call(
    String method,
    String path, {
    Object? data,
    String? token,
    bool asAdmin = false,
    Map<String, String>? headers,
  }) async {
    final bearer = asAdmin ? adminToken : token;
    final response = await server.handler(
      Request(
        method,
        Uri.parse('https://den.test/$path'),
        headers: {
          if (bearer != null) 'authorization': 'Bearer $bearer',
          'cookie': ?cookie,
          ...?headers,
        },
        body: data == null ? null : jsonEncode(data),
      ),
    );
    if (response.headers['set-cookie'] case final String value) {
      cookie = value.split(';').first;
    }
    return response;
  }

  Future<Map<String, Object?>> jsonCall(
    String method,
    String path, {
    Object? data,
    String? token,
    bool asAdmin = false,
    int status = 200,
  }) async {
    final response = await call(
      method,
      path,
      data: data,
      token: token,
      asAdmin: asAdmin,
    );
    final result = await readJson(response);
    expect(
      response.statusCode,
      status,
      reason: '$method $path: ${jsonEncode(result)}',
    );
    return result;
  }

  Future<void> expectError(
    String method,
    String path,
    int status,
    String code, {
    Object? data,
    String? token,
    bool asAdmin = false,
  }) async {
    final value = await jsonCall(
      method,
      path,
      data: data,
      token: token,
      asAdmin: asAdmin,
      status: status,
    );
    expect((value['error'] as Map)['code'], code);
  }

  Future<Map<String, Object?>> provider({
    String? token,
    Map<String, Object?> changes = const {},
  }) => jsonCall(
    'POST',
    token == null ? 'v1/admin/providers' : 'v1/me/providers',
    token: token,
    asAdmin: token == null,
    data: {
      'name': 'test',
      'baseUrl': 'https://models.test/v1',
      'apiKey': 'provider-secret',
      'models': ['model', 'org/model'],
      ...changes,
    },
  );

  Future<void> close() async {
    await server.close();
    store.close();
    final root = Directory('build/test').absolute.path;
    if (!temp.absolute.path.startsWith('$root${Platform.pathSeparator}')) {
      throw StateError('Unsafe test directory');
    }
    temp.deleteSync(recursive: true);
  }
}

Future<Map<String, Object?>> readJson(Response response) async =>
    jsonDecode(await response.readAsString()) as Map<String, Object?>;
