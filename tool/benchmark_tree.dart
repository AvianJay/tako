import 'dart:io';

import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/conversation_tree.dart';
import 'package:tako/core/chat/message.dart';

void main() {
  for (final count in [500, 2000]) {
    final nodes = [
      for (var i = 0; i < count; i++)
        ChatMessage(
          id: '$i',
          conversationId: 'benchmark',
          parentId: i == 0 ? null : '${i - 1}',
          role: i.isEven ? MessageRole.user : MessageRole.assistant,
          content: const [TextBlock('benchmark')],
          createdAt: DateTime.utc(2026),
        ),
    ];
    final watch = Stopwatch()..start();
    for (var run = 0; run < 5; run++) {
      final tree = ConversationTree(nodes);
      tree.pathTo('${count - 1}');
      for (var i = count - 20; i < count; i++) {
        tree.siblingsOf('$i');
      }
    }
    watch.stop();
    // Synthetic data only. Never benchmark by printing a user's conversations.
    stdout.writeln(
      '$count nodes: ${(watch.elapsedMicroseconds / 5000).toStringAsFixed(2)} ms per tree + path + 20 sibling lookups',
    );
  }
}
