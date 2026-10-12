import 'dart:io';

import 'package:path/path.dart' as p;

/// Workspace paths have one portable spelling; internal history is inaccessible
/// to ordinary file operations. Every existing ancestor is checked, including
/// when the eventual write target does not yet exist.
class WorkspacePathGuard {
  WorkspacePathGuard(this.root);
  final Directory root;

  static String normalize(
    String relative, {
    bool allowRoot = false,
    bool internal = false,
  }) {
    if (relative.isEmpty && allowRoot) return '';
    if (relative.isEmpty ||
        relative.startsWith('/') ||
        relative.contains('\\') ||
        RegExp(r'[\x00-\x1f\x7f:<>"|?*]').hasMatch(relative) ||
        Uri.tryParse(relative)?.hasScheme == true) {
      throw const FormatException('Invalid workspace path');
    }
    final parts = relative.split('/');
    if (parts.any(
      (part) =>
          part.isEmpty ||
          part == '.' ||
          part == '..' ||
          part.endsWith('.') ||
          part.endsWith(' ') ||
          RegExp(
            r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
            caseSensitive: false,
          ).hasMatch(part),
    )) {
      throw const FormatException('Invalid workspace path');
    }
    if (!internal && parts.first.toLowerCase() == '.tako') {
      throw const FormatException('Reserved workspace path');
    }
    return parts.join('/');
  }

  Future<String> resolve(
    String relative, {
    bool allowRoot = false,
    bool internal = false,
  }) async {
    final normalized = normalize(
      relative,
      allowRoot: allowRoot,
      internal: internal,
    );
    await root.create(recursive: true);
    final realRoot = await root.resolveSymbolicLinks();
    if (normalized.isEmpty) return realRoot;
    var current = realRoot;
    for (final component in normalized.split('/')) {
      current = p.join(current, component);
      final type = await FileSystemEntity.type(current, followLinks: false);
      // Reject even in-workspace links: writes/deletes must not affect aliases.
      if (type == FileSystemEntityType.link) {
        throw const FormatException(
          'Symbolic links are not allowed in workspace paths',
        );
      }
      if (type != FileSystemEntityType.notFound) {
        final canonical = await (type == FileSystemEntityType.directory
            ? Directory(current).resolveSymbolicLinks()
            : File(current).resolveSymbolicLinks());
        if (!p.isWithin(realRoot, canonical)) {
          throw const FormatException('Workspace path escapes the workspace');
        }
      }
    }
    if (!p.isWithin(realRoot, current)) {
      throw const FormatException('Workspace path escapes the workspace');
    }
    return current;
  }
}
