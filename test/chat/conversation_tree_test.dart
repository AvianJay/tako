import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/conversation_tree.dart';
import 'package:tako/core/chat/message.dart';

ChatMessage node(
  String id,
  String? parent,
  MessageRole role, {
  int minute = 0,
}) => ChatMessage(
  id: id,
  conversationId: 'chat',
  parentId: parent,
  role: role,
  content: [TextBlock(id)],
  createdAt: DateTime.utc(2026, 10, 10, 1, minute),
);

void main() {
  test('edit and regenerate preserve original paths and sibling positions', () {
    final tree = ConversationTree([
      node('u1', null, MessageRole.user),
      node('a1', 'u1', MessageRole.assistant),
      node('a2', 'u1', MessageRole.assistant, minute: 1),
      node('u2', 'a1', MessageRole.user, minute: 2),
      node('u2-edited', 'a1', MessageRole.user, minute: 3),
      node('a3', 'u2-edited', MessageRole.assistant, minute: 4),
    ]);
    expect(tree.pathTo('u2').map((m) => m.id), ['u1', 'a1', 'u2']);
    expect(tree.pathTo('a3').map((m) => m.id), ['u1', 'a1', 'u2-edited', 'a3']);
    expect(tree.siblingsOf('a2').map((m) => m.id), ['a1', 'a2']);
    expect(tree.siblingsOf('u2').map((m) => m.id), ['u2', 'u2-edited']);
    expect(tree.preferredLeafFrom('a1'), 'a3');
    expect(tree.preferredLeafFrom('a2'), 'a2');
    expect(tree.pathTo(null), isEmpty);
  });

  test('descendants include nested alternate branches but not siblings', () {
    final tree = ConversationTree([
      node('u', null, MessageRole.user),
      node('a', 'u', MessageRole.assistant),
      node('b', 'u', MessageRole.assistant),
      node('c', 'a', MessageRole.user),
      node('d', 'c', MessageRole.assistant),
    ]);
    expect(
      tree.descendantsOf('a').map((m) => m.id),
      unorderedEquals(['c', 'd']),
    );
    expect(tree.descendantsOf('d'), isEmpty);
  });

  test('malformed trees fail instead of looping or mixing conversations', () {
    expect(
      () => ConversationTree([node('a', 'missing', MessageRole.user)]),
      throwsStateError,
    );
    expect(
      () => ConversationTree([
        node('a', 'b', MessageRole.user),
        node('b', 'a', MessageRole.assistant),
      ]),
      throwsStateError,
    );
  });

  test(
    'message JSON preserves blocks, metadata, envelope and immutable lists',
    () {
      final message = ChatMessage(
        id: 'u',
        conversationId: 'c',
        role: MessageRole.user,
        content: const [
          TextBlock('hello'),
          ImageBlock(
            path: 'attachments/a.png',
            mimeType: 'image/png',
            data: 'runtime-only',
          ),
        ],
        createdAt: DateTime.parse('2026-10-10T01:31:00+08:00'),
        timezoneOffsetMinutes: 480,
        contextEnvelope: '<ctx time="frozen"/>',
        usage: const TokenUsage(
          inputTokens: 3,
          outputTokens: 4,
          totalTokens: 7,
        ),
      );
      final restored = ChatMessage.fromJson(message.toJson());
      expect(restored.createdAt.isUtc, isTrue);
      expect(restored.wallTime.hour, 1);
      expect(restored.requestText, '<ctx time="frozen"/>\nhello');
      expect((restored.content.last as ImageBlock).data, isNull);
      expect(restored.usage?.totalTokens, 7);
      expect(
        () => restored.content.add(const TextBlock('x')),
        throwsUnsupportedError,
      );
    },
  );
}
