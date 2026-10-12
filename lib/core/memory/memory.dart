import '../../platform/capabilities.dart';
import '../providers/cancel_token.dart';
import '../util/json.dart';

enum MemoryKind { profile, preference, fact }

class MemoryEntry {
  const MemoryEntry({
    required this.id,
    required this.text,
    required this.kind,
    required this.pinned,
    required this.createdAt,
    required this.updatedAt,
    required this.revision,
    this.sourceMessageId,
  });

  final String id;
  final String text;
  final MemoryKind kind;
  final bool pinned;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Changes on every write. Undo receipts and UI edits are revision-checked.
  final String revision;

  /// The assistant message whose tool call saved this entry, if any.
  final String? sourceMessageId;

  /// Only pinned profile and preference entries reach the system prompt.
  bool get inProfile => pinned && kind != MemoryKind.fact;

  JsonMap toJson() => {
    'id': id,
    'text': text,
    'kind': kind.name,
    'pinned': pinned,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'revision': revision,
    if (sourceMessageId != null) 'sourceMessageId': sourceMessageId,
  };
}

/// A saved memory may be undone only while it is still that exact revision.
/// Editing, pinning or importing must never let an old Undo delete newer data.
class MemoryUndo {
  const MemoryUndo({required this.id, required this.revision});
  final String id;
  final String revision;

  JsonMap toJson() => {'id': id, 'revision': revision};

  static MemoryUndo? fromJson(JsonMap? json) {
    final id = asString(json?['id']);
    final revision = asString(json?['revision']);
    return id == null || id.isEmpty || revision == null || revision.isEmpty
        ? null
        : MemoryUndo(id: id, revision: revision);
  }
}

class MemorySaveResult {
  const MemorySaveResult(this.entry, {this.duplicate = false});
  final MemoryEntry entry;

  /// An identical entry already existed; nothing new was written.
  final bool duplicate;
}

class MemoryFailure implements Exception {
  const MemoryFailure(this.code);
  final String code;
  @override
  String toString() => code;
}

MemoryKind? memoryKindNamed(Object? value) =>
    MemoryKind.values.where((kind) => kind.name == value).firstOrNull;

abstract interface class MemoryCapability implements Capability {
  Future<List<MemoryEntry>> search(String query, {int limit = 10});
  Future<MemoryEntry?> get(String id);
  Future<MemorySaveResult> save({
    required String text,
    MemoryKind kind = MemoryKind.fact,
    bool? pinned,
    String? sourceMessageId,
    CancelToken? cancel,
  });
  Future<MemoryEntry> update(
    String id, {
    String? text,
    MemoryKind? kind,
    bool? pinned,
    String? expectedRevision,
    CancelToken? cancel,
  });
  Future<MemoryEntry?> delete(
    String id, {
    String? expectedRevision,
    CancelToken? cancel,
  });
  Future<bool> undoSaved(MemoryUndo undo);
  Future<String> profileSnapshot({int maxWords});
}
