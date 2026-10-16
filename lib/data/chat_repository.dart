import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/chat/conversation.dart';
import '../core/chat/conversation_tree.dart';
import '../core/chat/message.dart';
import '../core/util/json.dart';
import 'database.dart';

final class ChatRepository {
  ChatRepository(this.database);

  final AppDatabase database;

  /// Incognito chats never appear in history.
  Future<List<Conversation>> listConversations() async {
    final rows = await database
        .customSelect(
          '''
      SELECT data FROM conversation_records
      WHERE json_extract(data, '\$.incognito') IS NOT 1
        AND json_extract(data, '\$.automationRuleId') IS NULL
      ORDER BY updated_at DESC
    ''',
          readsFrom: {database.conversationRecords},
        )
        .get();
    return rows
        .map(
          (r) =>
              Conversation.fromJson(tryDecodeObject(r.read<String>('data'))!),
        )
        .toList();
  }

  /// An incognito chat lives only while open. Call at startup, so one left
  /// behind by a process death is removed before anything can display it.
  /// Returns the deleted messages.
  Future<List<ChatMessage>> deleteIncognitoConversations() async {
    final rows = await database
        .customSelect(
          "SELECT id FROM conversation_records WHERE json_extract(data, '\$.incognito') = 1",
          readsFrom: {database.conversationRecords},
        )
        .get();
    final deleted = <ChatMessage>[];
    for (final row in rows) {
      deleted.addAll(await deleteConversation(row.read<String>('id')));
    }
    return deleted;
  }

  /// Whether any stored message mentions [path], e.g. an attachment.
  Future<bool> mentions(String path) async {
    final row = await database
        .customSelect(
          'SELECT 1 FROM message_records WHERE instr(data, ?) > 0 LIMIT 1',
          variables: [Variable.withString(path)],
          readsFrom: {database.messageRecords},
        )
        .getSingleOrNull();
    return row != null;
  }

  Future<Conversation?> getConversation(String id) async {
    final row = await (database.select(
      database.conversationRecords,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null
        ? null
        : Conversation.fromJson(tryDecodeObject(row.data)!);
  }

  Future<void> createConversation(Conversation conversation) async {
    if (conversation.activeLeafId != null) {
      throw ArgumentError('A new conversation cannot have an active leaf.');
    }
    await database
        .into(database.conversationRecords)
        .insert(
          ConversationRecordsCompanion.insert(
            id: conversation.id,
            data: jsonEncode(conversation.toJson()),
            updatedAt: conversation.updatedAt,
          ),
        );
  }

  Future<void> saveConversation(Conversation conversation) =>
      database.transaction(() async {
        if (conversation.activeLeafId case final leafId?) {
          final leaf = await getMessage(leafId);
          if (leaf?.conversationId != conversation.id) {
            throw ArgumentError('Active leaf must belong to its conversation.');
          }
        }
        await database
            .into(database.conversationRecords)
            .insertOnConflictUpdate(
              ConversationRecordsCompanion.insert(
                id: conversation.id,
                data: jsonEncode(conversation.toJson()),
                updatedAt: conversation.updatedAt,
              ),
            );
      });

  Future<List<ChatMessage>> getMessages(String conversationId) async {
    final rows =
        await (database.select(database.messageRecords)
              ..where((t) => t.conversationId.equals(conversationId))
              ..orderBy([
                (t) => OrderingTerm.asc(t.createdAt),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    return rows
        .map((r) => ChatMessage.fromJson(tryDecodeObject(r.data)!))
        .toList();
  }

  Future<ChatMessage?> getMessage(String id) async {
    final row = await (database.select(
      database.messageRecords,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null
        ? null
        : ChatMessage.fromJson(tryDecodeObject(row.data)!);
  }

  /// Saving the node and moving the active leaf happen atomically. A user edit
  /// or assistant regeneration is a new node with the original node's parent.
  Future<void> saveMessage(ChatMessage message, {bool activate = true}) =>
      database.transaction(() async {
        final conversation = await getConversation(message.conversationId);
        if (conversation == null) {
          throw ArgumentError('Conversation does not exist.');
        }
        final previous = await getMessage(message.id);
        if (previous != null &&
            (previous.conversationId != message.conversationId ||
                previous.parentId != message.parentId ||
                previous.role != message.role ||
                previous.createdAt != message.createdAt ||
                previous.contextEnvelope != message.contextEnvelope)) {
          throw ArgumentError(
            'A persisted message cannot be moved or re-timestamped.',
          );
        }
        if (message.parentId == message.id) {
          throw ArgumentError('A message cannot parent itself.');
        }
        if (message.parentId case final parentId?) {
          final parent = await getMessage(parentId);
          if (parent?.conversationId != message.conversationId) {
            throw ArgumentError('Parent must belong to the same conversation.');
          }
        }
        await database
            .into(database.messageRecords)
            .insertOnConflictUpdate(
              MessageRecordsCompanion.insert(
                id: message.id,
                conversationId: message.conversationId,
                parentId: Value(message.parentId),
                status: message.status.name,
                createdAt: message.createdAt,
                data: jsonEncode(message.toJson()),
              ),
            );
        await saveConversation(
          conversation.copyWith(
            activeLeafId: activate ? message.id : conversation.activeLeafId,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
      });

  Future<void> setActiveLeaf(String conversationId, String? messageId) =>
      database.transaction(() async {
        final conversation = await getConversation(conversationId);
        if (conversation == null) {
          throw ArgumentError('Conversation does not exist.');
        }
        if (messageId != null) {
          final message = await getMessage(messageId);
          if (message?.conversationId != conversationId) {
            throw ArgumentError(
              'Active leaf must belong to the same conversation.',
            );
          }
        }
        await saveConversation(
          conversation.copyWith(
            activeLeafId: messageId,
            clearActiveLeaf: messageId == null,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
      });

  Future<void> switchBranch(String conversationId, String messageId) async {
    final tree = ConversationTree(await getMessages(conversationId));
    await setActiveLeaf(conversationId, tree.preferredLeafFrom(messageId));
  }

  /// Background metadata must not restore a deleted chat, overwrite a rename,
  /// or replace the active leaf saved by a newer response.
  Future<bool> updateTitle(
    String conversationId,
    String title, {
    required String expectedTitle,
  }) => database.transaction(() async {
    final current = await getConversation(conversationId);
    if (current == null || current.title != expectedTitle) return false;
    await saveConversation(current.copyWith(title: title));
    return true;
  });

  /// Rewinds to the target and deletes every descendant, including branches
  /// beneath it, while keeping sibling branches at or above the target.
  /// Returns the deleted messages.
  Future<List<ChatMessage>> deleteDescendants(
    String conversationId,
    String messageId,
  ) => database.transaction(() async {
    final tree = ConversationTree(await getMessages(conversationId));
    final deleted = tree.descendantsOf(messageId).toList();
    await setActiveLeaf(conversationId, messageId);
    for (final message in deleted) {
      await (database.delete(
        database.messageRecords,
      )..where((t) => t.id.equals(message.id))).go();
    }
    return deleted;
  });

  /// Returns the deleted messages.
  Future<List<ChatMessage>> deleteConversation(String conversationId) =>
      database.transaction(() async {
        final messages = await getMessages(conversationId);
        await (database.delete(
          database.messageRecords,
        )..where((t) => t.conversationId.equals(conversationId))).go();
        await (database.delete(
          database.conversationRecords,
        )..where((t) => t.id.equals(conversationId))).go();
        return messages;
      });

  /// Call once at startup. A process death must not leave an endless spinner.
  Future<int> recoverInterruptedMessages() => database.transaction(() async {
    final rows = await (database.select(
      database.messageRecords,
    )..where((t) => t.status.equals(MessageStatus.streaming.name))).get();
    for (final row in rows) {
      final message = ChatMessage.fromJson(
        tryDecodeObject(row.data)!,
      ).copyWith(status: MessageStatus.stopped);
      await (database.update(
        database.messageRecords,
      )..where((t) => t.id.equals(row.id))).write(
        MessageRecordsCompanion(
          status: Value(message.status.name),
          data: Value(jsonEncode(message.toJson())),
        ),
      );
    }
    return rows.length;
  });
}
