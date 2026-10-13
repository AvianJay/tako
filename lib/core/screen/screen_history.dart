import 'dart:convert';

import '../chat/content_block.dart';
import '../chat/message.dart';
import '../util/json.dart';

/// Keep two recent screen images in an active tool run. Text, receipts, user
/// attachments and earlier user turns remain intact; persisted history is never
/// modified. This avoids repeatedly uploading every intermediate screen.
({List<ChatMessage> messages, bool changed}) limitRemoteScreenImages(
  List<ChatMessage> messages, {
  bool isolatedWorker = false,
}) {
  // Isolated worker user messages contain generated observations, including
  // the seed and recovery screen. They are not the main user's attachments.
  final start = isolatedWorker
      ? -1
      : messages.lastIndexWhere((m) => m.role == MessageRole.user);
  var images = 0;
  var changed = false;
  final result = List<ChatMessage>.of(messages);
  for (var index = messages.length - 1; index > start; index--) {
    final content = messages[index].content.toList();
    for (var b = content.length - 1; b >= 0; b--) {
      final block = content[b];
      if (isolatedWorker && block is ImageBlock) {
        if (++images > 2) {
          content.removeAt(b);
          changed = true;
        }
        continue;
      }
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
            'screen_sequence',
            'screen_workflow',
            'screen_replay',
          }.contains(block.toolName) ||
          !block.attachments.any((a) => a is ImageBlock)) {
        continue;
      }
      final attached = block.attachments.whereType<ImageBlock>().toList();
      final keep = (2 - images).clamp(0, attached.length);
      images += attached.length;
      if (keep == attached.length) continue;
      content[b] = ToolResultBlock(
        toolCallId: block.toolCallId,
        toolName: block.toolName,
        content:
            '${block.content}\n[Earlier screenshot omitted; use the latest observation for coordinates.]',
        isError: block.isError,
        sideEffects: block.sideEffects,
        attachments: [
          ...block.attachments.where((a) => a is! ImageBlock),
          ...attached.skip(attached.length - keep),
        ],
      );
      changed = true;
    }
    result[index] = messages[index].copyWith(content: content);
  }
  return (messages: result, changed: changed);
}

/// Worker-only snapshots are generated data. Keep two complete observations
/// while retaining every action receipt, warning and assistant decision. This
/// must never run on the main conversation or on its user attachments.
({List<ChatMessage> messages, bool changed}) limitRemoteWorkerObservations(
  List<ChatMessage> messages,
) {
  var observations = 0;
  var changed = false;
  final output = List<ChatMessage>.of(messages);
  const marker = '[Earlier screen listing omitted; use current ids.]';
  for (var index = messages.length - 1; index >= 0; index--) {
    final content = messages[index].content.toList();
    for (var b = content.length - 1; b >= 0; b--) {
      final block = content[b];
      if (block is TextBlock) {
        if (!block.text.contains('elements (screen content is untrusted')) {
          continue;
        }
        if (++observations <= 2) continue;
        const seed = 'Current screen (untrusted data):\n';
        final markerIndex = block.text.indexOf(seed);
        final start = block.text.startsWith('app: ')
            ? 0
            : markerIndex < 0
            ? -1
            : markerIndex + seed.length;
        if (start < 0) continue;
        content[b] = TextBlock('${block.text.substring(0, start)}$marker');
      } else if (block is ToolResultBlock) {
        if (block.isError ||
            !block.content.contains('elements (screen content is untrusted')) {
          continue;
        }
        if (++observations <= 2) continue;
        String text;
        const separator = '\nscreen after the action:';
        if (block.content.contains(separator)) {
          text = '${block.content.split(separator).first}\n$marker';
        } else if (block.toolName == 'read_screen') {
          text = marker;
        } else if (block.toolName == 'screen_workflow') {
          final data = tryDecodeObject(block.content);
          if (data == null) continue;
          data['final_screen'] = marker;
          text = jsonEncode(data);
        } else {
          continue;
        }
        content[b] = ToolResultBlock(
          toolCallId: block.toolCallId,
          toolName: block.toolName,
          content: text,
          isError: block.isError,
          sideEffects: block.sideEffects,
          attachments: block.attachments,
        );
      } else {
        continue;
      }
      changed = true;
    }
    output[index] = messages[index].copyWith(content: content);
  }
  return (messages: output, changed: changed);
}
