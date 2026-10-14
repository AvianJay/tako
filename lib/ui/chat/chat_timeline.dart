import 'package:markdown/markdown.dart' as md;

import '../../core/chat/content_block.dart';
import '../../core/chat/message.dart';
import '../render/message_parser.dart';

/// A presentation row. Stored messages and their branch identities stay intact.
final class ChatTimelineEntry {
  ChatTimelineEntry({
    required List<ChatMessage> messages,
    required this.isAssistantTurn,
  }) : messages = List.unmodifiable(messages) {
    if (messages.isEmpty) {
      throw ArgumentError('A timeline entry cannot be empty');
    }
  }

  final List<ChatMessage> messages;
  final bool isAssistantTurn;

  ChatMessage get anchor => messages.first;

  ChatMessage? get lastAssistant {
    for (final message in messages.reversed) {
      if (message.role == MessageRole.assistant) return message;
    }
    return null;
  }
}

sealed class AssistantSegment {
  const AssistantSegment();
}

final class AssistantContentSegment extends AssistantSegment {
  AssistantContentSegment({
    required this.message,
    required List<ContentBlock> blocks,
  }) : blocks = List.unmodifiable(blocks);

  final ChatMessage message;
  final List<ContentBlock> blocks;
}

final class ToolRunSegment extends AssistantSegment {
  ToolRunSegment({required this.id, required List<ToolRunStep> steps})
    : steps = List.unmodifiable(steps);

  /// Based on the first call's original position, so appending stream content
  /// or receiving results does not replace an open tool-details drawer.
  final String id;
  final List<ToolRunStep> steps;
}

final class ToolRunStep {
  const ToolRunStep({required this.message, required this.call, this.result});

  final ChatMessage message;
  final ToolCallBlock call;
  final ToolResultBlock? result;
}

/// Consecutive assistant/tool nodes share one header and footer. Tool receipts
/// belong to their preceding turn and never create blank rows of their own.
List<ChatTimelineEntry> buildChatTimeline(List<ChatMessage> visiblePath) {
  final entries = <ChatTimelineEntry>[];
  var turn = <ChatMessage>[];
  ChatMessage? lastAssistant;

  void flush() {
    if (turn.isEmpty) return;
    entries.add(ChatTimelineEntry(messages: turn, isAssistantTurn: true));
    turn = [];
    lastAssistant = null;
  }

  for (final message in visiblePath) {
    switch (message.role) {
      case MessageRole.user:
        flush();
        entries.add(
          ChatTimelineEntry(messages: [message], isAssistantTurn: false),
        );
      case MessageRole.assistant:
        if (turn.isNotEmpty &&
            (message.parentId != turn.last.id ||
                !_sameTurn(lastAssistant!, message))) {
          flush();
        }
        turn.add(message);
        lastAssistant = message;
      case MessageRole.tool:
        if (turn.isNotEmpty &&
            message.parentId == turn.last.id &&
            message.conversationId == turn.last.conversationId) {
          turn.add(message);
        } else {
          flush();
        }
    }
  }
  flush();
  return List.unmodifiable(entries);
}

bool _sameTurn(ChatMessage previous, ChatMessage next) =>
    previous.conversationId == next.conversationId &&
    previous.providerId == next.providerId &&
    previous.model == next.model &&
    previous.wallTime.year == next.wallTime.year &&
    previous.wallTime.month == next.wallTime.month &&
    previous.wallTime.day == next.wallTime.day;

/// Keeps visible content in original order and groups only consecutive calls.
/// Reasoning accompanying a tool round is available in each step's message
/// for the details drawer, without breaking the compact run in the main chat.
List<AssistantSegment> buildAssistantSegments(List<ChatMessage> messages) {
  final results = _visibleReceipts(messages);
  final segments = <AssistantSegment>[];
  var steps = <ToolRunStep>[];
  String? runId;
  var blocks = <ContentBlock>[];
  ChatMessage? contentMessage;

  void flushContent() {
    if (blocks.isEmpty) return;
    segments.add(
      AssistantContentSegment(message: contentMessage!, blocks: blocks),
    );
    blocks = [];
    contentMessage = null;
  }

  void flushRun() {
    if (steps.isEmpty) return;
    segments.add(ToolRunSegment(id: runId!, steps: steps));
    steps = [];
    runId = null;
  }

  for (final message in messages) {
    if (message.role == MessageRole.tool) continue;
    if (message.role != MessageRole.assistant) {
      flushContent();
      flushRun();
      continue;
    }
    final hasCalls = message.content.any((block) => block is ToolCallBlock);
    var rendered = false;
    for (var index = 0; index < message.content.length; index++) {
      final block = message.content[index];
      if (block is ToolCallBlock) {
        flushContent();
        runId ??= 'tool-run:${message.id}:$index:${block.id}';
        steps.add(
          ToolRunStep(
            message: message,
            call: block,
            result: results[message.id]?[block.id],
          ),
        );
        rendered = true;
        continue;
      }
      final visible = switch (block) {
        TextBlock(:final text) =>
          text.trim().isNotEmpty || blocks.isNotEmpty && text.isNotEmpty,
        ReasoningBlock(:final text) => text.trim().isNotEmpty && !hasCalls,
        ImageBlock() || FileBlock() => true,
        _ => false,
      };
      if (!visible) continue;
      flushRun();
      contentMessage = message;
      blocks.add(block);
      rendered = true;
    }
    flushContent();
    if (!rendered && message.status != MessageStatus.done) {
      flushRun();
      segments.add(AssistantContentSegment(message: message, blocks: const []));
    }
  }
  flushRun();
  // The reply places generated images itself. Any it leaves out follow the
  // reply, so they never interrupt the tool run that produced them.
  final generated = _generatedImages(messages, results);
  if (generated.isNotEmpty) {
    final all = [for (final (_, images) in generated) ...images];
    final placed = <String>{
      for (final message in messages)
        if (message.role == MessageRole.assistant)
          for (final source in _imageSources(message))
            ?placedGeneratedImage(source, all)?.path,
    };
    for (final (receipt, images) in generated) {
      final rest = [
        for (final image in images)
          if (!placed.contains(image.path)) image,
      ];
      if (rest.isNotEmpty) {
        segments.add(AssistantContentSegment(message: receipt, blocks: rest));
      }
    }
  }
  return List.unmodifiable(segments);
}

/// Images that generate_image returned during this turn.
List<ImageBlock> generatedImages(List<ChatMessage> messages) => [
  for (final (_, images) in _generatedImages(
    messages,
    _visibleReceipts(messages),
  ))
    ...images,
];

List<(ChatMessage, List<ImageBlock>)> _generatedImages(
  List<ChatMessage> messages,
  Map<String, Map<String, ToolResultBlock>> results,
) {
  final generated = <(ChatMessage, List<ImageBlock>)>[];
  for (final message in messages) {
    if (message.role != MessageRole.tool) continue;
    final images = [
      for (final result in message.content.whereType<ToolResultBlock>())
        if (result.toolName == 'generate_image' &&
            identical(results[message.parentId]?[result.toolCallId], result))
          ...result.attachments.whereType<ImageBlock>(),
    ];
    if (images.isNotEmpty) generated.add((message, images));
  }
  return generated;
}

/// Resolves a reply's image reference to one of [images]. Models vary the
/// path (./, a leading slash, backslashes, file:, only the file name), so a
/// unique file name matches too. Remote URLs never do.
ImageBlock? placedGeneratedImage(String source, List<ImageBlock> images) {
  String normalize(String path) => path
      .trim()
      .replaceAll(r'\', '/')
      .replaceFirst(RegExp(r'^file:', caseSensitive: false), '')
      .replaceFirst(RegExp(r'^(?:\.?/)+'), '');
  final wanted = normalize(source);
  if (wanted.isEmpty || wanted.contains('://')) return null;
  for (final image in images) {
    if (normalize(image.path) == wanted) return image;
  }
  final name = wanted.split('/').last;
  final named = {
    for (final image in images)
      if (image.path.split('/').last == name) image.path: image,
  };
  return named.length == 1 ? named.values.single : null;
}

/// Image references exactly as MessageMarkdown renders them, so a tag inside
/// code, or one still streaming in, does not count as placed.
Iterable<String> _imageSources(ChatMessage message) sync* {
  final text = message.content.whereType<TextBlock>().map((b) => b.text).join();
  if (text.isEmpty) return;
  final parsed = parseMessageMarkup(
    text,
    isStreaming: message.status == MessageStatus.streaming,
  );
  for (final fragment in parsed.fragments.values) {
    if (fragment case RenderTag(name: 'image' || 'file', :final attributes)) {
      if (attributes['src'] ?? attributes['path'] case final source?) {
        yield source;
      }
    }
  }
  Iterable<md.Element> elements(Iterable<md.Node> nodes) sync* {
    for (final node in nodes) {
      if (node is! md.Element) continue;
      yield node;
      yield* elements(node.children ?? const []);
    }
  }

  for (final element in elements(parsed.nodes)) {
    if (element.tag == 'img') yield element.attributes['src'] ?? '';
  }
}

/// A result must be on this visible path and its actual edge must point to the
/// assistant that made the call. IDs reused by a later round cannot steal it.
Map<String, Map<String, ToolResultBlock>> _visibleReceipts(
  List<ChatMessage> messages,
) {
  final results = <String, Map<String, ToolResultBlock>>{};
  for (var index = 1; index < messages.length; index++) {
    final receipt = messages[index];
    final parent = messages[index - 1];
    if (receipt.role != MessageRole.tool ||
        parent.role != MessageRole.assistant ||
        receipt.parentId != parent.id ||
        receipt.conversationId != parent.conversationId) {
      continue;
    }
    final calls = <String, ToolCallBlock>{};
    final duplicateCalls = <String>{};
    for (final call in parent.content.whereType<ToolCallBlock>()) {
      if (calls.containsKey(call.id)) duplicateCalls.add(call.id);
      calls[call.id] = call;
    }
    final matches = <String, ToolResultBlock>{};
    final duplicateResults = <String>{};
    for (final result in receipt.content.whereType<ToolResultBlock>()) {
      final call = calls[result.toolCallId];
      if (call == null ||
          duplicateCalls.contains(call.id) ||
          call.name != result.toolName) {
        continue;
      }
      if (matches.containsKey(call.id)) duplicateResults.add(call.id);
      matches[call.id] = result;
    }
    for (final id in duplicateResults) {
      matches.remove(id);
    }
    results[parent.id] = matches;
  }
  return results;
}
