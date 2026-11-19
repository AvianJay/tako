import 'dart:convert';

import '../chat/content_block.dart';
import '../chat/message.dart';

abstract final class ContextBudget {
  static int estimateTokens(String text) {
    var units = 0;
    for (var i = 0; i < text.length; i++) {
      units += text.codeUnitAt(i) < 128 ? 1 : 3;
    }
    return (units + 2) ~/ 3;
  }

  static int messageTokens(ChatMessage message) =>
      8 +
      estimateTokens(message.contextEnvelope ?? '') +
      message.content.fold(0, (total, block) => total + _blockTokens(block));

  static int _blockTokens(ContentBlock block) =>
      4 +
      switch (block) {
        TextBlock(:final text) ||
        ReasoningBlock(:final text) => estimateTokens(text),
        ImageBlock(:final path, :final alt) =>
          512 + estimateTokens(path) + estimateTokens(alt ?? ''),
        FileBlock(:final name, :final extractedText) =>
          estimateTokens(name) + estimateTokens(extractedText ?? ''),
        ToolCallBlock(:final id, :final name, :final arguments) =>
          estimateTokens(id) + estimateTokens(name) + estimateTokens(arguments),
        ToolResultBlock(
          :final toolCallId,
          :final toolName,
          :final content,
          :final attachments,
        ) =>
          estimateTokens(toolCallId) +
              estimateTokens(toolName) +
              estimateTokens(content) +
              attachments.fold(0, (total, item) => total + _blockTokens(item)),
        ProviderStateBlock(:final content) => estimateTokens(
          jsonEncode(content),
        ),
      };
}
