import '../chat/content_block.dart';
import '../chat/message.dart';

/// Keep two recent screen images in an active tool run. Text, receipts, user
/// attachments and earlier user turns remain intact; persisted history is never
/// modified. This avoids repeatedly uploading every intermediate screen.
({List<ChatMessage> messages, bool changed}) limitRemoteScreenImages(
  List<ChatMessage> messages,
) {
  final start = messages.lastIndexWhere((m) => m.role == MessageRole.user);
  var images = 0;
  var changed = false;
  final result = List<ChatMessage>.of(messages);
  for (var index = messages.length - 1; index > start; index--) {
    final content = messages[index].content.toList();
    for (var b = content.length - 1; b >= 0; b--) {
      final block = content[b];
      if (block is! ToolResultBlock ||
          block.isError ||
          !const {
            'read_screen',
            'tap',
            'long_press',
            'scroll',
            'swipe',
            'drag',
            'type_text',
            'press_key',
            'open_app',
            'open_url',
          }.contains(block.toolName) ||
          !block.attachments.any((a) => a is ImageBlock)) {
        continue;
      }
      if (++images <= 2) continue;
      content[b] = ToolResultBlock(
        toolCallId: block.toolCallId,
        toolName: block.toolName,
        content:
            '${block.content}\n[Earlier screenshot omitted; use the latest observation for coordinates.]',
        isError: block.isError,
        sideEffects: block.sideEffects,
        attachments: block.attachments.where((a) => a is! ImageBlock).toList(),
      );
      changed = true;
    }
    result[index] = messages[index].copyWith(content: content);
  }
  return (messages: result, changed: changed);
}
