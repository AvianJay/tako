import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tako_den/src/schema.dart';
import 'package:tako_den/src/web.dart';
import 'package:tako_den/tako_den.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('version-1 CREATE statements migrate all data and remain usable', () async {
    final db = sqlite3.openInMemory();
    db.execute(schemaV1);
    db.execute('PRAGMA user_version = 1');
    db.execute(
      'INSERT INTO users (id, username, password_hash, is_admin, seq, pruned_seq, created_at) VALUES (?, ?, ?, 1, 2, 1, 1)',
      ['old-user', 'legacy', hashPassword('password123')],
    );
    db.execute('INSERT INTO devices VALUES (?, ?, ?, ?, 1, 2)', [
      'old-device',
      'old-user',
      'Phone',
      sha256.convert(utf8.encode('tako_legacy')).toString(),
    ]);
    db.execute(
      "INSERT INTO records VALUES ('old-user', 'memories', 'r1', 1, 2, 0, '{}', 1, 'old-device')",
    );
    db.execute(
      "INSERT INTO pair_codes VALUES ('pairhash', 'old-user', 9999999999999)",
    );
    db.execute("INSERT INTO blobs VALUES ('old-user', 'hash', 42, 1)");
    db.execute(
      "INSERT INTO usage VALUES ('old-user', 'old/model', '2026-01-01', 2, 3, 4)",
    );
    final store = Store(db);
    final h = Harness(database: store, admin: false);
    addTearDown(h.close);
    expect(db.select('PRAGMA user_version').first.values.single, 2);
    expect(db.select('PRAGMA foreign_key_check'), isEmpty);
    final me = await h.jsonCall('GET', 'v1/me', token: 'tako_legacy');
    expect((me['user'] as Map)['role'], 'admin');
    expect((me['user'] as Map)['displayName'], 'legacy');
    expect(me['seq'], 2);
    expect(
      (await h.jsonCall('GET', 'v1/sync/pull', token: 'tako_legacy'))['changes']
          as List,
      hasLength(1),
    );
    expect(store.checkPassword('legacy', 'password123'), isNotNull);
    expect(db.select('SELECT * FROM pair_codes'), hasLength(1));
    expect(db.select('SELECT * FROM blobs').single['size'], 42);
    expect(db.select('SELECT * FROM usage').single['shared'], 1);
    expect(store.currentSeq(store.users.single), 2);
    store.push(store.deviceForToken('tako_legacy')!, [
      const SyncChange(
        collection: 'memories',
        id: 'r1',
        baseVersion: 1,
        data: {'text': 'new'},
      ),
    ]);
    expect(store.currentSeq(store.users.single), 3);
  });

  test(
    'AES-GCM persists keys and authenticates ciphertext and context',
    () async {
      final root = Directory('build/test')..createSync(recursive: true);
      final directory = root.createTempSync('secrets_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final first = Secrets.load(directory.path);
      final encrypted = await first.encrypt('test-secret', 'provider:id');
      expect(encrypted, isNot(contains('test-secret')));
      final reopened = Secrets.load(directory.path);
      expect(await reopened.decrypt(encrypted, 'provider:id'), 'test-secret');
      await expectLater(
        reopened.decrypt(encrypted, 'provider:other'),
        throwsA(anything),
      );
      final bytes = base64.decode(encrypted)..[15] ^= 1;
      await expectLater(
        reopened.decrypt(base64.encode(bytes), 'provider:id'),
        throwsA(anything),
      );
      expect(
        () => Secrets.load(directory.path, encodedKey: 'bad'),
        throwsFormatException,
      );
      final fromEnv = Secrets.load(
        directory.path,
        encodedKey: base64.encode(List.filled(32, 7)),
      );
      expect(
        await fromEnv.decrypt(await fromEnv.encrypt('value', 'test'), 'test'),
        'value',
      );
      if (!Platform.isWindows) {
        expect(
          (await Process.run('stat', [
            '-c',
            '%a',
            '${directory.path}/secret.key',
          ])).stdout.toString().trim(),
          '600',
        );
      }
    },
  );

  test('embedded files, SPA routes and exact security headers', () async {
    final h = Harness();
    addTearDown(h.close);
    for (final file in Directory(
      'web',
    ).listSync(recursive: true).whereType<File>()) {
      final path = file.path.replaceAll(r'\', '/').substring(4);
      final response = await h.call('GET', path);
      expect(response.statusCode, 200);
      expect(
        await response.read().expand((bytes) => bytes).toList(),
        file.readAsBytesSync(),
      );
      for (final header in webHeaders.entries) {
        expect(response.headers[header.key], header.value);
      }
    }
    for (final route in [
      'login',
      'link',
      'setup',
      'oauth',
      'settings',
      'admin',
      'unknown/path',
    ]) {
      expect(
        await (await h.call('GET', route)).readAsString(),
        File('web/index.html').readAsStringSync(),
      );
    }
    for (final path in ['js/missing.js', 'app.css.map', 'favicon.ico']) {
      final response = await h.call('GET', path);
      expect(response.statusCode, 404);
      expect(await response.readAsString(), isNot(contains('<html')));
    }
    expect((await h.call('GET', 'v1/unknown', asAdmin: true)).statusCode, 404);
    expect(await (await h.call('GET', 'healthz')).readAsString(), 'ok');
  });

  test(
    'development assets and SPA fallback stay inside the configured root',
    () async {
      final root = Directory('build/test')..createSync(recursive: true);
      final directory = root.createTempSync('devweb_');
      addTearDown(() => directory.deleteSync(recursive: true));
      File('${directory.path}/index.html').writeAsStringSync('dev app');
      File('${directory.path}/fresh.js').writeAsStringSync('dev script');
      Directory('${directory.path}/js').createSync();
      File('${directory.path}/js/module.js').writeAsStringSync('nested script');
      final h = Harness(config: DenConfig(webDir: directory.path));
      addTearDown(h.close);
      expect(
        await (await h.call('GET', 'fresh.js')).readAsString(),
        'dev script',
      );
      expect(await (await h.call('GET', 'settings')).readAsString(), 'dev app');
      expect(await (await h.call('GET', 'admin')).readAsString(), 'dev app');
      expect(
        await (await h.call('GET', 'js/module.js')).readAsString(),
        'nested script',
      );
      for (final path in ['js/missing.js', 'app.css.map', 'favicon.ico']) {
        final response = await h.call('GET', path);
        expect(response.statusCode, 404);
        expect(await response.readAsString(), isNot('dev app'));
      }
      expect((await h.call('GET', '%2e%2e/pubspec.yaml')).statusCode, 404);
    },
  );
}
