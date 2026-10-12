import 'dart:typed_data';

import '../../platform/capabilities.dart';
import '../chat/content_block.dart';
import '../providers/cancel_token.dart';

class WorkspaceEntry {
  const WorkspaceEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final int sizeBytes;
  final DateTime modifiedAt;
}

class WorkspaceReadResult {
  const WorkspaceReadResult({
    required this.text,
    this.image,
    this.truncated = false,
  });
  final String text;
  final ImageBlock? image;
  final bool truncated;
}

/// Relative paths only. Attachment payloads are hydrated for requests, never DB.
abstract interface class WorkspaceCapability implements Capability {
  Future<List<WorkspaceEntry>> list({String path = '', CancelToken? cancel});
  Future<WorkspaceReadResult> read(
    String path, {
    int maxCharacters = 6000,
    CancelToken? cancel,
  });
  Future<SideEffect> write(String path, String text, {CancelToken? cancel});
  Future<SideEffect> delete(String path, {CancelToken? cancel});
  Future<List<ContentBlock>> importFiles({CancelToken? cancel});
  Future<ContentBlock> importBytes(
    String name,
    Uint8List bytes, {
    CancelToken? cancel,
  });
  Future<ImageBlock> importImageBytes(
    String name,
    Uint8List bytes, {
    CancelToken? cancel,
  });
  Future<List<ContentBlock>> hydrateBlocks(
    List<ContentBlock> blocks, {
    required bool vision,
    CancelToken? cancel,
  });
  Future<void> restoreBackup(String backupPath, {CancelToken? cancel});

  /// Permanently deletes files under `attachments/`, without a backup, e.g.
  /// screenshots of a deleted chat. Other paths and missing files are
  /// skipped.
  Future<void> removeAttachments(Iterable<String> paths);
  Future<void> pruneHistory({Set<String> protectedPaths = const {}});
  Future<Uint8List> readBytes(String path, {CancelToken? cancel});
  Future<void> shareFile(String path);
}
