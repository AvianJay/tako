import 'dart:convert';

import '../chat/content_block.dart';
import '../chat/message.dart';

final class ContextBudgetResult {
  const ContextBudgetResult({
    required this.messages,
    required this.estimatedTokens,
    required this.removedMessages,
    required this.removedToolOutputs,
    required this.exceedsBudget,
  });

  final List<ChatMessage> messages;
  final int estimatedTokens;
  final int removedMessages;
  final int removedToolOutputs;
  final bool exceedsBudget;
  bool get wasTrimmed => removedMessages > 0 || removedToolOutputs > 0;
}

abstract final class ContextBudget {
  static int estimateTokens(String text) => (text.runes.length / 3).ceil();

  static ContextBudgetResult trim({
    required String systemPrompt,
    required List<ChatMessage> messages,
    required int contextWindow,
    int reserveOutputTokens = 4096,
  }) {
    if (contextWindow <= 0 || reserveOutputTokens < 0) {
      throw ArgumentError('Context and output token limits must be valid.');
    }
    final budget = contextWindow - reserveOutputTokens;
    final request = List<ChatMessage>.of(messages);
    var removedMessages = 0;
    var removedToolOutputs = 0;
    int count() =>
        estimateTokens(systemPrompt) +
        request.fold<int>(
          0,
          (sum, message) =>
              sum +
              4 +
              estimateTokens(
                '${message.contextEnvelope ?? ''}${jsonEncode(message.content.map((b) => b.toJson()).toList())}',
              ),
        );

    var tokens = count();
    final latestUser = request.lastIndexWhere(
      (m) => m.role == MessageRole.user,
    );
    // Only older turns may lose tool outputs; the current turn remains intact.
    for (var i = 0; i < latestUser && tokens > budget; i++) {
      final content = <ContentBlock>[];
      var changed = false;
      for (final block in request[i].content) {
        if (block is ToolResultBlock && block.content.length > 27) {
          content.add(block.withContent('[older tool output removed]'));
          removedToolOutputs++;
          changed = true;
        } else {
          content.add(block);
        }
      }
      if (changed) {
        request[i] = request[i].copyWith(content: content);
        tokens = count();
      }
    }
    // Drop complete turns, keeping call/result pairs together. Never split the
    // newest turn: report an over-budget request so the caller can explain it.
    while (tokens > budget && request.isNotEmpty) {
      final nextUser = request.indexWhere((m) => m.role == MessageRole.user, 1);
      if (nextUser < 0) break;
      request.removeRange(0, nextUser);
      removedMessages += nextUser;
      tokens = count();
    }
    return ContextBudgetResult(
      messages: List.unmodifiable(request),
      estimatedTokens: tokens,
      removedMessages: removedMessages,
      removedToolOutputs: removedToolOutputs,
      exceedsBudget: tokens > budget,
    );
  }
}
