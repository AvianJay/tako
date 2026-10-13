import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/screen/screen_history.dart';

void main() {
  test(
    'only superseded remote images are omitted from outgoing active turn',
    () {
      ChatMessage message(
        int id,
        List<ContentBlock> blocks, {
        bool user = false,
      }) => ChatMessage(
        id: '$id',
        conversationId: 'c',
        role: user ? MessageRole.user : MessageRole.tool,
        content: blocks,
        createdAt: DateTime(2026),
      );
      const image = ImageBlock(path: 'proof.jpg', mimeType: 'image/jpeg');
      ToolResultBlock result(int id, {String name = 'tap'}) => ToolResultBlock(
        toolCallId: '$id',
        toolName: name,
        content: 'receipt $id',
        attachments: [image],
        sideEffects: const [
          SideEffect(kind: 'screen_tapped', summary: 'committed'),
        ],
      );
      final history = [
        message(0, [result(0)]),
        message(1, [image, const TextBlock('Task')], user: true),
        message(2, [result(2)]),
        message(3, [result(3, name: 'read_file')]),
        message(4, [result(4)]),
        message(5, [result(5)]),
      ];
      final limited = limitRemoteScreenImages(history);
      expect(limited.changed, true);
      expect(
        (limited.messages[2].content.single as ToolResultBlock).attachments,
        isEmpty,
      );
      expect(
        (limited.messages[2].content.single as ToolResultBlock)
            .sideEffects
            .single
            .kind,
        'screen_tapped',
      );
      expect(
        (limited.messages[2].content.single as ToolResultBlock).content,
        contains('receipt 2'),
      );
      for (final index in [0, 3, 4, 5]) {
        expect(
          (limited.messages[index].content.single as ToolResultBlock)
              .attachments,
          hasLength(1),
        );
      }
      expect(limited.messages[1].content.first, same(image));
      expect(
        (history[2].content.single as ToolResultBlock).attachments,
        hasLength(1),
      );
    },
  );
}
