import 'dart:convert';

import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/conversation.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/den/den_client.dart';
import 'package:tako/core/den/sync_engine.dart';
import 'package:tako/data/chat_repository.dart';
import 'package:tako/data/database.dart';
import 'package:tako/data/memory_repository.dart';
import 'package:tako/data/settings_repository.dart';
import 'package:tako/data/sync_store.dart';

/// The server's sync routes, as API.md describes them.
final class FakeDen {
  final records = <String, Map<String, Object?>>{};
  var seq = 0;
  var pageSize = 500;
  var resetNext = false;
  var pushes = 0;
  late final client = MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    final device = request.headers['authorization']!.replaceFirst(
      'Bearer tako_',
      '',
    );
    if (request.url.path == '/v1/sync/push') {
      pushes++;
      final changes = (jsonDecode(request.body) as Map)['changes'] as List;
      final results = <Object?>[];
      for (final change in changes.cast<Map<String, Object?>>()) {
        final key = '${change['collection']}/${change['id']}';
        final current = records[key];
        final version = (current?['version'] as int?) ?? 0;
        final head = {'collection': change['collection'], 'id': change['id']};
        if (version != change['baseVersion']) {
          results.add({...head, 'status': 'conflict', 'current': current});
          continue;
        }
        seq++;
        records[key] = {
          ...head,
          'version': version + 1,
          'seq': seq,
          if (change['deleted'] == true)
            'deleted': true
          else
            'data': change['data'],
          'deviceId': device,
        };
        results.add({
          ...head,
          'status': 'ok',
          'version': version + 1,
          'seq': seq,
        });
      }
      return _json({'seq': seq, 'results': results});
    }
    if (request.url.path == '/v1/sync/pull') {
      if (resetNext) {
        resetNext = false;
        return _json({'changes': [], 'seq': 0, 'more': true, 'reset': true});
      }
      final since = int.parse(request.url.queryParameters['since']!);
      final after =
          records.values.where((r) => (r['seq']! as int) > since).toList()
            ..sort((a, b) => (a['seq']! as int).compareTo(b['seq']! as int));
      final page = after.take(pageSize).toList();
      final more = after.length > pageSize;
      return _json({
        'changes': page,
        'seq': more ? page.last['seq'] : seq,
        'more': more,
      });
    }
    return http.Response('{"error":{"code":"not_found","message":"?"}}', 404);
  }

  http.Response _json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
}

final class Device {
  Device(this.name, FakeDen den) : db = AppDatabase(NativeDatabase.memory()) {
    engine = SyncEngine(
      client: DenClient(
        Uri.parse('http://den.test'),
        token: 'tako_$name',
        client: den.client,
      ),
      ledger: store,
      deviceId: name,
      onApplied: applied.add,
    );
  }

  final String name;
  final AppDatabase db;
  late final chats = ChatRepository(db);
  late final memory = MemoryRepository(db);
  late final settings = SettingsRepository(db);
  late final store = SyncStore(db);
  late final SyncEngine engine;
  final applied = <ApplyResult>[];

  Future<void> sync() async {
    await engine.sync();
    expect(engine.status.error, isNull, reason: '$name sync failed');
  }

  Future<void> chat(
    String id, {
    String title = 'Chat',
    bool incognito = false,
    List<String> messages = const ['hello'],
  }) async {
    final now = DateTime.now().toUtc();
    await chats.createConversation(
      Conversation(
        id: id,
        title: title,
        createdAt: now,
        updatedAt: now,
        systemPrompt: 'prompt',
        incognito: incognito,
      ),
    );
    String? parent;
    for (final (i, text) in messages.indexed) {
      final message = ChatMessage(
        id: '$id-m$i',
        conversationId: id,
        parentId: parent,
        role: i.isEven ? MessageRole.user : MessageRole.assistant,
        content: [TextBlock(text)],
        createdAt: now.add(Duration(seconds: i)),
      );
      await chats.saveMessage(message);
      parent = message.id;
    }
  }

  Future<List<String>> texts(String conversationId) async => [
    for (final m in await chats.getMessages(conversationId)) m.text,
  ];

  Future<int> tracked() async =>
      (await db
              .customSelect('SELECT count(*) AS n FROM sync_state')
              .getSingle())
          .read<int>('n');

  Future<void> close() async {
    engine.dispose();
    await db.close();
  }
}

void main() {
  // Each device is its own in-memory database, on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late FakeDen den;
  late Device phone;
  late Device laptop;

  setUp(() {
    den = FakeDen();
    phone = Device('phone', den);
    laptop = Device('laptop', den);
  });

  tearDown(() async {
    await phone.close();
    await laptop.close();
  });

  test(
    'tracks nothing until sync is enabled, then merges what exists',
    () async {
      await phone.chat('before', messages: ['one', 'two']);
      expect(await phone.tracked(), 0);

      await phone.store.enable();
      // The conversation and both messages, ready to upload.
      expect(await phone.store.pendingCount(), 3);
      await phone.chat('after');
      expect(await phone.store.pendingCount(), 5);

      await phone.sync();
      expect(await phone.store.pendingCount(), 0);
      expect(
        den.records.keys,
        containsAll([
          'conversations/before',
          'messages/before-m1',
          'conversations/after',
        ]),
      );
    },
  );

  test('incognito chats never leave the device', () async {
    await phone.store.enable();
    await phone.chat('secret', incognito: true, messages: ['a', 'b']);
    await phone.chats.deleteConversation('secret');
    expect(await phone.tracked(), 0);
    await phone.sync();
    expect(den.records, isEmpty);
  });

  test('two devices end up with the union of their chats', () async {
    await phone.chat('p', messages: ['from phone', 'reply']);
    await phone.memory.save(text: 'Likes oolong tea');
    await phone.settings.setString(
      'personalization.settings',
      '{"name":"Ana"}',
    );
    await laptop.chat('l', messages: ['from laptop']);

    await phone.store.enable();
    await laptop.store.enable();
    await phone.sync();
    await laptop.sync();
    await phone.sync();

    for (final device in [phone, laptop]) {
      expect(
        [for (final c in await device.chats.listConversations()) c.id]..sort(),
        ['l', 'p'],
      );
      expect(await device.texts('p'), ['from phone', 'reply']);
      expect(await device.texts('l'), ['from laptop']);
      expect(
        (await device.memory.search('oolong')).single.text,
        'Likes oolong tea',
      );
      expect(
        await device.settings.getString('personalization.settings'),
        '{"name":"Ana"}',
      );
      expect(await device.store.pendingCount(), 0, reason: device.name);
    }
    // Applying remote records does not mark them for upload again.
    final before = den.pushes;
    await laptop.sync();
    await phone.sync();
    expect(den.pushes, before);
    expect(laptop.applied.expand((r) => r.conversations), contains('p'));
  });

  test('a streaming reply is uploaded once it has finished', () async {
    await phone.store.enable();
    await phone.chat('c', messages: ['question']);
    final now = DateTime.now().toUtc();
    final reply = ChatMessage(
      id: 'reply',
      conversationId: 'c',
      parentId: 'c-m0',
      role: MessageRole.assistant,
      content: const [TextBlock('partial')],
      createdAt: now,
      status: MessageStatus.streaming,
    );
    await phone.chats.saveMessage(reply);
    await phone.sync();
    expect(den.records.containsKey('messages/reply'), isFalse);

    await phone.chats.saveMessage(
      reply.copyWith(
        content: const [TextBlock('the whole answer')],
        status: MessageStatus.done,
      ),
    );
    await phone.sync();
    expect(
      ((den.records['messages/reply']!['data']! as Map)['content'] as List)
          .single,
      {'type': 'text', 'text': 'the whole answer'},
    );
  });

  test('deleting a chat on one device deletes it on the other', () async {
    await phone.store.enable();
    await laptop.store.enable();
    await phone.chat('c', messages: ['a', 'b', 'c']);
    await phone.sync();
    await laptop.sync();
    expect(await laptop.texts('c'), ['a', 'b', 'c']);

    await laptop.chats.deleteConversation('c');
    await laptop.sync();
    await phone.sync();
    expect(await phone.chats.getConversation('c'), isNull);
    expect(await phone.chats.getMessages('c'), isEmpty);
    expect(await phone.store.pendingCount(), 0);
  });

  test('the newer rename wins on both devices', () async {
    await phone.store.enable();
    await laptop.store.enable();
    await phone.chat('c');
    await phone.sync();
    await laptop.sync();

    Future<void> rename(Device device, String title, DateTime at) async {
      final c = (await device.chats.getConversation('c'))!;
      await device.chats.saveConversation(
        c.copyWith(title: title, updatedAt: at),
      );
    }

    final now = DateTime.now().toUtc();
    await rename(phone, 'Older', now);
    await rename(laptop, 'Newer', now.add(const Duration(minutes: 1)));
    await laptop.sync();
    await phone.sync(); // conflict: the server copy is newer
    await laptop.sync();
    for (final device in [phone, laptop]) {
      expect((await device.chats.getConversation('c'))!.title, 'Newer');
      expect(await device.store.pendingCount(), 0);
    }
  });

  test('messages that arrive before their conversation wait for it', () async {
    await phone.store.enable();
    await laptop.store.enable();
    await phone.chat('c', messages: ['1', '2', '3', '4']);
    // Saving each message touched the conversation last, so its newest
    // version comes after the messages; small pages split them apart.
    await phone.sync();
    den.pageSize = 2;
    await laptop.sync();
    expect(await laptop.texts('c'), ['1', '2', '3', '4']);
    expect(await laptop.store.cursor(), den.seq);
  });

  test('a reset pulls everything again', () async {
    await phone.store.enable();
    await laptop.store.enable();
    await phone.chat('c', messages: ['kept']);
    await phone.sync();
    await laptop.sync();
    await laptop.db.customStatement('DELETE FROM sync_state');
    den.resetNext = true;
    await laptop.sync();
    expect(await laptop.texts('c'), ['kept']);
    final versions = await laptop.db
        .customSelect(
          'SELECT server_version FROM sync_state WHERE collection = ?',
          variables: [Variable.withString('messages')],
        )
        .get();
    expect(versions.single.read<int>('server_version'), 1);
  });

  test('signing in again on the same device uploads nothing new', () async {
    await phone.store.enable();
    await phone.chat('c', messages: ['a', 'b']);
    await phone.sync();
    final before = Map.of(den.records);

    await phone.store.disable();
    await phone.store.enable();
    await phone.sync();
    for (final key in before.keys) {
      expect(
        den.records[key]!['version'],
        before[key]!['version'],
        reason: key,
      );
    }
    expect(await phone.store.pendingCount(), 0);
  });
}
