import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/conversation.dart';
import 'package:tako/core/chat/conversation_tree.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/providers/provider_config.dart';
import 'package:tako/data/chat_repository.dart';
import 'package:tako/data/database.dart';
import 'package:tako/data/provider_repository.dart';
import 'package:tako/data/settings_repository.dart';

Conversation conversation(String id) => Conversation(
  id: id,
  title: 'Chat',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  systemPrompt: 'frozen <prompt>',
);

ChatMessage message(
  String id,
  String? parent,
  MessageRole role, {
  MessageStatus status = MessageStatus.done,
  String conversationId = 'c',
}) => ChatMessage(
  id: id,
  conversationId: conversationId,
  parentId: parent,
  role: role,
  content: [TextBlock(id)],
  createdAt: DateTime.utc(2026),
  status: status,
  contextEnvelope: role == MessageRole.user ? '<ctx time="original"/>' : null,
);

void main() {
  test(
    'branches, rewind, frozen prompt and envelopes survive reopening',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tako_database_test_',
      );
      final file = File('${directory.path}/chat.sqlite');
      var database = AppDatabase(NativeDatabase(file));
      try {
        var repository = ChatRepository(database);
        await repository.createConversation(conversation('c'));
        await repository.saveMessage(message('u', null, MessageRole.user));
        await repository.saveMessage(message('a', 'u', MessageRole.assistant));
        await repository.saveMessage(message('a2', 'u', MessageRole.assistant));
        await repository.saveMessage(message('u2', 'a2', MessageRole.user));
        await repository.saveMessage(
          message('u2-edit', 'a2', MessageRole.user),
        );
        await repository.saveMessage(
          message(
            'partial',
            'u2-edit',
            MessageRole.assistant,
            status: MessageStatus.streaming,
          ),
        );
        await repository.setActiveLeaf('c', 'a');
        await database.close();

        database = AppDatabase(NativeDatabase(file));
        repository = ChatRepository(database);
        expect(await repository.recoverInterruptedMessages(), 1);
        expect(
          (await repository.getMessage('partial'))?.status,
          MessageStatus.stopped,
        );
        final restored = (await repository.getConversation('c'))!;
        expect(restored.activeLeafId, 'a');
        expect(restored.systemPrompt, 'frozen <prompt>');
        expect(
          (await repository.getMessage('u'))?.contextEnvelope,
          '<ctx time="original"/>',
        );
        final tree = ConversationTree(await repository.getMessages('c'));
        expect(tree.siblingsOf('a').map((m) => m.id), ['a', 'a2']);
        expect(tree.siblingsOf('u2').map((m) => m.id), ['u2', 'u2-edit']);
        await repository.switchBranch('c', 'a2');
        expect(
          (await repository.getConversation('c'))?.activeLeafId,
          'partial',
        );
        await repository.deleteDescendants('c', 'a2');
        expect(
          (await repository.getMessages('c')).map((m) => m.id),
          unorderedEquals(['u', 'a', 'a2']),
        );
        expect((await repository.getConversation('c'))?.activeLeafId, 'a2');
        await database.close();
        database = AppDatabase(NativeDatabase(file));
        expect((await ChatRepository(database).getMessages('c')), hasLength(3));
        expect(
          (await ChatRepository(database).getConversation('c'))?.activeLeafId,
          'a2',
        );
      } finally {
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'invalid parents, cross-chat leaves and mutation are rejected atomically',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ChatRepository(database);
      await repository.createConversation(conversation('c'));
      await repository.createConversation(conversation('other'));
      await repository.saveMessage(message('u', null, MessageRole.user));
      await expectLater(
        repository.saveMessage(message('a', 'missing', MessageRole.assistant)),
        throwsArgumentError,
      );
      await expectLater(
        repository.saveMessage(
          message('x', 'u', MessageRole.user, conversationId: 'other'),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.setActiveLeaf('other', 'u'),
        throwsArgumentError,
      );
      await expectLater(
        repository.saveMessage(message('u', 'u', MessageRole.user)),
        throwsArgumentError,
      );
      expect((await repository.getMessages('c')).map((m) => m.id), ['u']);
      expect((await repository.getConversation('c'))?.activeLeafId, 'u');
      await repository.deleteConversation('c');
      expect(await repository.getMessages('c'), isEmpty);
      expect(await repository.getConversation('c'), isNull);
    },
  );

  test(
    'provider data persists references without credential headers; settings roundtrip',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final providers = ProviderRepository(database);
      await providers.save(
        ProviderConfig(
          id: 'local',
          displayName: 'Local',
          apiType: ApiType.chatCompletions,
          baseUrl: 'http://127.0.0.1:8080',
          model: 'model',
          apiKeyRef: 'provider.local.key',
          extraHeadersRef: 'provider.local.headers',
          extraHeaders: {'X-Private': 'fixture-secret'},
          capabilities: const ProviderCapabilities(contextWindow: 8192),
        ),
      );
      final raw = await database.select(database.providerRecords).getSingle();
      expect(raw.data, isNot(contains('fixture-secret')));
      final config = (await providers.list()).single;
      expect(config.apiKeyRef, 'provider.local.key');
      expect(config.extraHeaders, isEmpty);
      expect(config.capabilities.contextWindow, 8192);
      final settings = SettingsRepository(database);
      await settings.setString('theme', 'dark');
      expect(await settings.getString('theme'), 'dark');
      expect(await settings.readAll(), {'theme': 'dark'});
      await settings.setString('theme', null);
      expect(await settings.getString('theme'), isNull);
    },
  );
}
