import 'content_block.dart';
import 'message.dart';

/// Operations never mutate stored messages. Editing and regeneration append
/// siblings; changing the active leaf is the only operation needed to rewind.
final class ConversationTree {
  ConversationTree(Iterable<ChatMessage> messages)
    : _nodes = {for (final message in messages) message.id: message} {
    final conversationIds = _nodes.values.map((m) => m.conversationId).toSet();
    if (conversationIds.length > 1) {
      throw ArgumentError('A tree must contain only one conversation.');
    }
    // Resolve each parent chain once. Validating every full path was quadratic
    // for long conversations, and this object is used by every visible row.
    final complete = <String>{};
    for (final message in _nodes.values) {
      final visiting = <String>{};
      String? id = message.id;
      while (id != null && !complete.contains(id)) {
        if (!visiting.add(id)) {
          throw StateError('Conversation tree contains a cycle.');
        }
        final node = _nodes[id];
        if (node == null) {
          throw StateError('Missing message in conversation tree.');
        }
        id = node.parentId;
      }
      complete.addAll(visiting);
      (_children[message.parentId] ??= []).add(message);
    }
    for (final children in _children.values) {
      children.sort((a, b) {
        final time = a.createdAt.compareTo(b.createdAt);
        return time == 0 ? a.id.compareTo(b.id) : time;
      });
    }
  }

  final Map<String, ChatMessage> _nodes;
  final Map<String?, List<ChatMessage>> _children = {};

  List<ChatMessage> pathTo(String? leafId) {
    final path = <ChatMessage>[];
    final visited = <String>{};
    var id = leafId;
    while (id != null) {
      if (!visited.add(id)) {
        throw StateError('Conversation tree contains a cycle.');
      }
      final node = _nodes[id];
      if (node == null) {
        throw StateError('Missing message in conversation tree.');
      }
      path.add(node);
      id = node.parentId;
    }
    return path.reversed.toList(growable: false);
  }

  List<ChatMessage> childrenOf(String? id) {
    return List.unmodifiable(_children[id] ?? const <ChatMessage>[]);
  }

  List<ChatMessage> siblingsOf(String id) {
    final node = _nodes[id];
    if (node == null) throw ArgumentError.value(id, 'id', 'Unknown message');
    return childrenOf(node.parentId).where((m) => m.role == node.role).toList();
  }

  List<ChatMessage> descendantsOf(String id) {
    if (!_nodes.containsKey(id)) {
      throw ArgumentError.value(id, 'id', 'Unknown message');
    }
    final descendants = <ChatMessage>[];
    final pending = <String>[id];
    while (pending.isNotEmpty) {
      final children = childrenOf(pending.removeLast());
      descendants.addAll(children);
      pending.addAll(children.map((m) => m.id));
    }
    return descendants;
  }

  /// Pick the most recently created continuation when switching a branch.
  String preferredLeafFrom(String id) {
    if (!_nodes.containsKey(id)) {
      throw ArgumentError.value(id, 'id', 'Unknown message');
    }
    var leaf = id;
    while (true) {
      final children = childrenOf(leaf);
      if (children.isEmpty) return leaf;
      leaf = children.last.id;
    }
  }

  List<SideEffect> sideEffectsAfter(String? leafId, String rewindId) {
    final path = pathTo(leafId);
    final index = path.indexWhere((m) => m.id == rewindId);
    if (index < 0) {
      throw ArgumentError('Rewind target is not on the active path.');
    }
    return [
      for (final message in path.skip(index + 1))
        for (final result in message.content.whereType<ToolResultBlock>())
          ...result.sideEffects,
    ];
  }
}
