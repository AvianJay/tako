import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:tako_den/tako_den.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late Store store;
  late DenServer server;
  late List<http.Request> upstreamRequests;

  setUp(() {
    final root = Directory('build/test')..createSync(recursive: true);
    temp = root.createTempSync('tako_den_test');
    store = Store.memory();
    store.createUser('ana', 'correct horse', isAdmin: true);
    upstreamRequests = [];
    final upstream = MockClient((request) async {
      upstreamRequests.add(request);
      if (request.url.path.endsWith('/models')) {
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'qwen3:8b'},
            ],
          }),
          200,
        );
      }
      return http.Response(
        'data: {"choices":[{"delta":{"content":"Hi"}}]}\n\n'
        'data: {"choices":[],"usage":{"prompt_tokens":12,"completion_tokens":3}}\n\n'
        'data: [DONE]\n\n',
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    const config = DenConfig(
      upstreams: [
        Upstream(
          name: 'home',
          baseUrl: 'http://ollama.local:11434/v1',
          apiKey: 'upstream-secret',
        ),
        Upstream(
          name: 'fixed',
          baseUrl: 'https://example.com/v1',
          models: ['m1', 'm2'],
        ),
      ],
    );
    server = DenServer(
      config: config,
      store: store,
      blobDir: temp.path,
      gateway: Gateway(config.upstreams, store, client: upstream),
    );
  });

  tearDown(() async {
    await server.close();
    store.close();
    temp.deleteSync(recursive: true);
  });

  Future<Response> call(
    String method,
    String path, {
    Object? body,
    String? token,
    List<int>? bytes,
  }) async => server.handler(
    Request(
      method,
      Uri.parse('http://den.test/$path'),
      body: bytes ?? (body == null ? null : jsonEncode(body)),
      headers: {'authorization': ?(token == null ? null : 'Bearer $token')},
    ),
  );

  Future<Map<String, Object?>> read(Response response) async =>
      jsonDecode(await response.readAsString()) as Map<String, Object?>;

  Future<String> login({String device = 'Pixel'}) async {
    final response = await call(
      'POST',
      'v1/auth/login',
      body: {
        'username': 'ana',
        'password': 'correct horse',
        'deviceName': device,
      },
    );
    expect(response.statusCode, 200);
    return (await read(response))['token'] as String;
  }

  test('signs in with a password and rejects a wrong one', () async {
    final token = await login();
    expect(token, startsWith('tako_'));
    final me = await read(await call('GET', 'v1/me', token: token));
    expect((me['user'] as Map)['username'], 'ana');

    final wrong = await call(
      'POST',
      'v1/auth/login',
      body: {'username': 'ana', 'password': 'nope'},
    );
    expect(wrong.statusCode, 401);
    expect((await call('GET', 'v1/me')).statusCode, 401);
    expect((await call('GET', 'v1/me', token: 'tako_forged')).statusCode, 401);
  });

  test('a pairing code signs in a new device exactly once', () async {
    final web = await login(device: 'Web');
    final code = await read(await call('POST', 'v1/pair/codes', token: web));
    expect(code['uri'], startsWith('tako://den/pair?server='));
    expect(code['qrSvg'], startsWith('<svg'));

    final claim = await call(
      'POST',
      'v1/pair/claim',
      body: {
        'code': (code['code'] as String).toLowerCase(),
        'deviceName': 'Phone',
      },
    );
    expect(claim.statusCode, 200);
    final phone = (await read(claim))['token'] as String;
    expect((await call('GET', 'v1/me', token: phone)).statusCode, 200);

    final again = await call(
      'POST',
      'v1/pair/claim',
      body: {'code': code['code']},
    );
    expect(again.statusCode, 400);

    final devices = await read(await call('GET', 'v1/devices', token: web));
    expect(devices['devices'] as List, hasLength(2));
  });

  test('locks sign-in after ten failures and caps open bodies', () async {
    for (var i = 0; i < 10; i++) {
      final wrong = await call(
        'POST',
        'v1/auth/login',
        body: {'username': 'ana', 'password': 'wrong $i'},
      );
      expect(wrong.statusCode, 401);
    }
    final locked = await call(
      'POST',
      'v1/auth/login',
      body: {'username': 'ana', 'password': 'correct horse'},
    );
    expect(locked.statusCode, 429);

    final huge = await call(
      'POST',
      'v1/pair/claim',
      body: {'code': 'x' * 70000},
    );
    expect(huge.statusCode, 413);
  });

  test('behind a trusted proxy, limits sign-in per real client', () async {
    final proxied = DenServer(
      config: const DenConfig(trustProxy: true),
      store: store,
      blobDir: temp.path,
    );
    addTearDown(proxied.close);
    Future<int> signIn(String forwardedFor, String password) async {
      final response = await proxied.handler(
        Request(
          'POST',
          Uri.parse('http://den.test/v1/auth/login'),
          body: jsonEncode({'username': 'ana', 'password': password}),
          headers: {'x-forwarded-for': forwardedFor},
        ),
      );
      return response.statusCode;
    }

    // The proxy appends the real address; the client controls the rest.
    for (var i = 0; i < 10; i++) {
      expect(await signIn('forged-$i, 10.0.0.1', 'wrong'), 401);
    }
    expect(await signIn('forged-new, 10.0.0.1', 'correct horse'), 429);
    expect(await signIn('10.0.0.2', 'correct horse'), 200);
  });

  test('creates a named key that works for the gateway', () async {
    final web = await login(device: 'Web');
    final created = await read(
      await call('POST', 'v1/devices', token: web, body: {'name': 'Tako app'}),
    );
    final key = created['token'] as String;
    expect(key, startsWith('tako_'));
    expect((created['device'] as Map)['name'], 'Tako app');
    expect((await call('GET', 'v1/models', token: key)).statusCode, 200);
  });

  test('revoking a device invalidates its token', () async {
    final web = await login(device: 'Web');
    final phone = await login(device: 'Phone');
    final me = await read(await call('GET', 'v1/me', token: phone));
    final id = (me['device'] as Map)['id'];
    expect(
      (await call('DELETE', 'v1/devices/$id', token: web)).statusCode,
      200,
    );
    expect((await call('GET', 'v1/me', token: phone)).statusCode, 401);
  });

  group('sync', () {
    Map<String, Object?> conversation(String id, String title) => {
      'id': id,
      'title': title,
      'createdAt': '2026-11-03T00:00:00.000Z',
      'updatedAt': '2026-11-03T00:00:00.000Z',
      'systemPrompt': '',
    };

    test('pushes, pulls from a sequence, and detects conflicts', () async {
      final phone = await login(device: 'Phone');
      final laptop = await login(device: 'Laptop');

      final first = await read(
        await call(
          'POST',
          'v1/sync/push',
          token: phone,
          body: {
            'changes': [
              {
                'collection': 'conversations',
                'id': 'c1',
                'baseVersion': 0,
                'data': conversation('c1', 'Trip'),
              },
              {
                'collection': 'messages',
                'id': 'm1',
                'baseVersion': 0,
                'data': {'id': 'm1', 'conversationId': 'c1', 'role': 'user'},
              },
            ],
          },
        ),
      );
      expect(first['seq'], 2);
      expect(
        [for (final r in first['results'] as List) (r as Map)['status']],
        ['ok', 'ok'],
      );

      final pulled = await read(
        await call('GET', 'v1/sync/pull?since=0', token: laptop),
      );
      expect(pulled['changes'] as List, hasLength(2));
      expect(pulled['seq'], 2);

      // The laptop renames; the phone, still at version 1, then loses.
      final rename = await read(
        await call(
          'POST',
          'v1/sync/push',
          token: laptop,
          body: {
            'changes': [
              {
                'collection': 'conversations',
                'id': 'c1',
                'baseVersion': 1,
                'data': conversation('c1', 'Trip to Tainan'),
              },
            ],
          },
        ),
      );
      expect(((rename['results'] as List).single as Map)['version'], 2);

      final stale = await read(
        await call(
          'POST',
          'v1/sync/push',
          token: phone,
          body: {
            'changes': [
              {
                'collection': 'conversations',
                'id': 'c1',
                'baseVersion': 1,
                'data': conversation('c1', 'Trip!'),
              },
            ],
          },
        ),
      );
      final conflict = (stale['results'] as List).single as Map;
      expect(conflict['status'], 'conflict');
      expect(
        ((conflict['current'] as Map)['data'] as Map)['title'],
        'Trip to Tainan',
      );

      final since = await read(
        await call('GET', 'v1/sync/pull?since=2', token: phone),
      );
      expect(since['changes'] as List, hasLength(1));
      expect(since['seq'], 3);
    });

    test('deletions arrive as tombstones', () async {
      final token = await login();
      Future<Map<String, Object?>> push(Map<String, Object?> change) async =>
          read(
            await call(
              'POST',
              'v1/sync/push',
              token: token,
              body: {
                'changes': [change],
              },
            ),
          );
      await push({
        'collection': 'memories',
        'id': 'x',
        'baseVersion': 0,
        'data': {'text': 'Likes tea'},
      });
      await push({
        'collection': 'memories',
        'id': 'x',
        'baseVersion': 1,
        'deleted': true,
      });
      final pulled = await read(
        await call('GET', 'v1/sync/pull', token: token),
      );
      final record = (pulled['changes'] as List).single as Map;
      expect(record['deleted'], isTrue);
      expect(record.containsKey('data'), isFalse);
    });

    test('rejects unknown collections and non-object bodies', () async {
      final token = await login();
      final result = await read(
        await call(
          'POST',
          'v1/sync/push',
          token: token,
          body: {
            'changes': [
              {'collection': 'secrets', 'id': 'a', 'data': {}},
              {'collection': 'messages', 'id': 'b', 'data': 'text'},
            ],
          },
        ),
      );
      expect(
        [for (final r in result['results'] as List) (r as Map)['reason']],
        ['unknown_collection', 'data_must_be_object'],
      );
      expect(result['seq'], 0);
    });

    test('tells a device that missed pruned deletions to start over', () async {
      final token = await login();
      Future<void> push(Map<String, Object?> change) => call(
        'POST',
        'v1/sync/push',
        token: token,
        body: {
          'changes': [change],
        },
      );
      for (final id in ['a', 'b']) {
        await push({
          'collection': 'memories',
          'id': id,
          'baseVersion': 0,
          'data': {'text': id},
        });
      }
      await push({
        'collection': 'memories',
        'id': 'b',
        'baseVersion': 1,
        'deleted': true,
      });
      store.db.execute('UPDATE records SET updated_at = 0 WHERE deleted = 1');
      expect(store.pruneTombstones(), 1);

      // Seen up to seq 2: the deletion at seq 3 is gone, so start over.
      final behind = await read(
        await call('GET', 'v1/sync/pull?since=2', token: token),
      );
      expect(behind['reset'], isTrue);
      expect(behind['changes'], isEmpty);

      final fresh = await read(
        await call('GET', 'v1/sync/pull?since=0', token: token),
      );
      expect(fresh.containsKey('reset'), isFalse);
      expect(
        [for (final r in fresh['changes'] as List) (r as Map)['id']],
        ['a'],
      );

      final upToDate = await read(
        await call('GET', 'v1/sync/pull?since=3', token: token),
      );
      expect(upToDate.containsKey('reset'), isFalse);
    });

    test('keeps users apart', () async {
      final ana = await login();
      store.createUser('ben', 'another password');
      final ben = (await read(
        await call(
          'POST',
          'v1/auth/login',
          body: {'username': 'ben', 'password': 'another password'},
        ),
      ))['token'];
      await call(
        'POST',
        'v1/sync/push',
        token: ana,
        body: {
          'changes': [
            {
              'collection': 'memories',
              'id': 'private',
              'baseVersion': 0,
              'data': {'text': 'secret'},
            },
          ],
        },
      );
      final pulled = await read(
        await call('GET', 'v1/sync/pull', token: ben as String),
      );
      expect(pulled['changes'], isEmpty);
    });

    test('pages through long histories', () async {
      final token = await login();
      await call(
        'POST',
        'v1/sync/push',
        token: token,
        body: {
          'changes': [
            for (var i = 0; i < 5; i++)
              {
                'collection': 'messages',
                'id': 'm$i',
                'baseVersion': 0,
                'data': {'i': i},
              },
          ],
        },
      );
      final page = await read(
        await call('GET', 'v1/sync/pull?since=0&limit=2', token: token),
      );
      expect(page['more'], isTrue);
      expect(page['seq'], 2);
      final rest = await read(
        await call('GET', 'v1/sync/pull?since=2&limit=10', token: token),
      );
      expect(rest['changes'] as List, hasLength(3));
      expect(rest['more'], isFalse);
    });
  });

  group('gateway', () {
    test('lists upstream models with their prefix', () async {
      final token = await login();
      final models = await read(await call('GET', 'v1/models', token: token));
      expect(
        [for (final m in models['data'] as List) (m as Map)['id']],
        ['home/qwen3:8b', 'fixed/m1', 'fixed/m2'],
      );
      expect(
        upstreamRequests.single.headers['authorization'],
        'Bearer upstream-secret',
      );
    });

    test('forwards chat to the upstream and records usage', () async {
      final token = await login();
      final response = await call(
        'POST',
        'v1/chat/completions',
        token: token,
        body: {
          'model': 'home/qwen3:8b',
          'stream': true,
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        },
      );
      expect(response.statusCode, 200);
      expect(await response.readAsString(), contains('"Hi"'));

      final sent = upstreamRequests.singleWhere(
        (request) => request.method == 'POST',
      );
      expect(
        sent.url.toString(),
        'http://ollama.local:11434/v1/chat/completions',
      );
      expect((jsonDecode(sent.body) as Map)['model'], 'qwen3:8b');
      // The device token never reaches the upstream.
      expect(sent.headers['authorization'], 'Bearer upstream-secret');

      final usage = await read(await call('GET', 'v1/usage', token: token));
      final row = (usage['usage'] as List).single as Map;
      expect(row['model'], 'home/qwen3:8b');
      expect(row['inputTokens'], 12);
      expect(row['outputTokens'], 3);
    });

    test('explains an unknown model', () async {
      final token = await login();
      final response = await call(
        'POST',
        'v1/chat/completions',
        token: token,
        body: {'model': 'gpt-5.5', 'messages': []},
      );
      expect(response.statusCode, 404);
      expect(
        ((await read(response))['error'] as Map)['code'],
        'model_not_found',
      );
    });
  });

  test('stores blobs by their SHA-256', () async {
    final token = await login();
    final bytes = utf8.encode('a generated image');
    final hash = sha256.convert(bytes).toString();

    final bad = await call(
      'PUT',
      'v1/blobs/${sha256.convert([1]).toString()}',
      token: token,
      bytes: bytes,
    );
    expect(bad.statusCode, 400);

    expect(
      (await call(
        'PUT',
        'v1/blobs/$hash',
        token: token,
        bytes: bytes,
      )).statusCode,
      200,
    );
    final got = await call('GET', 'v1/blobs/$hash', token: token);
    expect(await got.read().expand((c) => c).toList(), bytes);
  });

  test('serves the web app without a token', () async {
    final page = await call('GET', '');
    expect(page.statusCode, 200);
    expect(await page.readAsString(), contains('Tako Den'));
    expect(page.headers['content-security-policy'], contains("'self'"));
  });
}
