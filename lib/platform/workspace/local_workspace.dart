import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/chat/content_block.dart';
import '../../core/files/workspace.dart';
import '../../core/providers/cancel_token.dart';
import 'path_guard.dart';

/// Files and decoder plugins live at the platform boundary. Initialization and
/// PDFium loading are lazy so neither delays the first chat frame.
class LocalWorkspace implements WorkspaceCapability {
  LocalWorkspace({
    Directory? rootDirectory,
    this.maxHistoryBytes = 64 * 1024 * 1024,
  }) : _rootDirectory = rootDirectory;

  final Directory? _rootDirectory;
  final int maxHistoryBytes;
  static const maxFileBytes = 20 * 1024 * 1024;
  static const _maxAttachmentCharacters = 30000;
  Future<WorkspacePathGuard>? _guardFuture;
  Future<void> _mutations = Future.value();
  final Set<String> _activeBackups = {};
  final Map<String, ImageBlock> _imageCache = {};
  int _imageCacheCharacters = 0;
  final Random _random = Random.secure();

  @override
  bool get isAvailable => Platform.isAndroid || _rootDirectory != null;

  Future<WorkspacePathGuard> get _guard => _guardFuture ??= () async {
    final root =
        _rootDirectory ??
        Directory(
          p.join((await getApplicationDocumentsDirectory()).path, 'workspace'),
        );
    await root.create(recursive: true);
    return WorkspacePathGuard(root);
  }();

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final next = _mutations.then((_) => operation());
    _mutations = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  String _id() =>
      '${DateTime.now().toUtc().microsecondsSinceEpoch}-${_random.nextInt(0x7fffffff).toRadixString(16)}';

  @override
  Future<List<WorkspaceEntry>> list({
    String path = '',
    CancelToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    final guard = await _guard;
    final directory = Directory(await guard.resolve(path, allowRoot: true));
    final result = <WorkspaceEntry>[];
    await for (final entity in directory.list(followLinks: false)) {
      cancel?.throwIfCancelled();
      final name = p.basename(entity.path);
      if (name.toLowerCase() == '.tako' || entity is Link) continue;
      final relative = path.isEmpty ? name : '$path/$name';
      try {
        await guard.resolve(relative);
      } on FormatException {
        continue;
      }
      final stat = await entity.stat();
      result.add(
        WorkspaceEntry(
          path: relative,
          name: name,
          isDirectory: stat.type == FileSystemEntityType.directory,
          sizeBytes: stat.size,
          modifiedAt: stat.modified.toUtc(),
        ),
      );
      if (result.length >= 1000) break;
    }
    result.sort(
      (a, b) => a.isDirectory != b.isDirectory
          ? (a.isDirectory ? -1 : 1)
          : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return result;
  }

  @override
  Future<Uint8List> readBytes(String path, {CancelToken? cancel}) async {
    cancel?.throwIfCancelled();
    final file = File(await (await _guard).resolve(path));
    if (await file.length() > maxFileBytes) {
      throw const FormatException('File exceeds 20 MB limit');
    }
    final data = await _readLimited(file.openRead(), cancel);
    cancel?.throwIfCancelled();
    return data;
  }

  @override
  Future<WorkspaceReadResult> read(
    String path, {
    int maxCharacters = 6000,
    CancelToken? cancel,
  }) async {
    if (maxCharacters < 1 || maxCharacters > 100000) {
      throw const FormatException('Invalid text limit');
    }
    final mime = mimeTypeFor(path);
    if (mime.startsWith('image/')) {
      cancel?.throwIfCancelled();
      final stat = await File(await (await _guard).resolve(path)).stat();
      final cacheKey =
          '$path|${stat.modified.microsecondsSinceEpoch}|${stat.size}';
      final cached = _imageCache.remove(cacheKey);
      if (cached != null) {
        _imageCache[cacheKey] = cached;
        return WorkspaceReadResult(text: 'Image: $path', image: cached);
      }
      final bytes = await readBytes(path, cancel: cancel);
      final data = await Isolate.run(() => _prepareImage(bytes));
      cancel?.throwIfCancelled();
      final image = ImageBlock(
        path: path,
        mimeType: 'image/jpeg',
        alt: p.posix.basename(path),
        data: base64Encode(data),
      );
      _imageCache[cacheKey] = image;
      _imageCacheCharacters += image.data!.length;
      while (_imageCacheCharacters > 6 * 1024 * 1024 &&
          _imageCache.length > 1) {
        _imageCacheCharacters -= _imageCache
            .remove(_imageCache.keys.first)!
            .data!
            .length;
      }
      return WorkspaceReadResult(text: 'Image: $path', image: image);
    }
    final bytes = await readBytes(path, cancel: cancel);
    final text = mime == 'application/pdf'
        ? await extractPdfText(
            bytes,
            maxCharacters: maxCharacters,
            cancel: cancel,
          )
        : _decodeText(bytes, mime);
    cancel?.throwIfCancelled();
    final truncated = text.length > maxCharacters;
    return WorkspaceReadResult(
      text: truncated
          ? '${text.substring(0, maxCharacters)}\n[truncated]'
          : text,
      truncated: truncated,
    );
  }

  static String _decodeText(Uint8List bytes, String mime) {
    if (mime == 'application/octet-stream' || bytes.take(8192).contains(0)) {
      throw const FormatException(
        'Unsupported file format; use text, PDF, or an image',
      );
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static Future<String> extractPdfText(
    Uint8List bytes, {
    int maxCharacters = 30000,
    CancelToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    await pdfrxFlutterInitialize();
    final document = await PdfDocument.openData(bytes);
    try {
      final output = StringBuffer();
      for (final page in document.pages) {
        cancel?.throwIfCancelled();
        final text = await page.loadText();
        if (text != null) output.writeln(text.fullText);
        if (output.length > maxCharacters) break;
      }
      final text = output.toString();
      if (text.trim().isEmpty) {
        return '[No extractable PDF text; scanned documents require OCR]';
      }
      return text;
    } finally {
      await document.dispose();
    }
  }

  @override
  Future<SideEffect> write(String path, String text, {CancelToken? cancel}) =>
      _exclusive(() async {
        cancel?.throwIfCancelled();
        final bytes = utf8.encode(text);
        if (bytes.length > maxFileBytes) {
          throw const FormatException('File exceeds 20 MB limit');
        }
        final guard = await _guard;
        final destination = await guard.resolve(path);
        final backup = await _backup(path, cancel: cancel);
        _activeBackups.add(backup);
        try {
          await _atomicWrite(destination, bytes, cancel: cancel);
          return SideEffect(
            kind: 'file_written',
            summary: path,
            backupPath: backup,
          );
        } finally {
          await _maintainHistory(backup);
          _activeBackups.remove(backup);
        }
      });

  @override
  Future<SideEffect> delete(String path, {CancelToken? cancel}) =>
      _exclusive(() async {
        cancel?.throwIfCancelled();
        final file = File(await (await _guard).resolve(path));
        if (!await file.exists()) {
          throw const FormatException('File does not exist');
        }
        final backup = await _backup(path, cancel: cancel);
        _activeBackups.add(backup);
        try {
          cancel?.throwIfCancelled();
          await file.delete();
          return SideEffect(
            kind: 'file_deleted',
            summary: path,
            backupPath: backup,
          );
        } finally {
          await _maintainHistory(backup);
          _activeBackups.remove(backup);
        }
      });

  @override
  Future<void> removeAttachments(Iterable<String> paths) =>
      _exclusive(() async {
        final guard = await _guard;
        for (final path in paths) {
          if (path.split('/').first.toLowerCase() != 'attachments') continue;
          try {
            final file = File(await guard.resolve(path));
            if (await file.exists()) await file.delete();
          } on Exception {
            // Best effort: an invalid or already removed path is skipped.
          }
        }
      });

  Future<String> _backup(String path, {CancelToken? cancel}) async {
    final guard = await _guard;
    final source = File(await guard.resolve(path));
    final exists = await source.exists();
    if (exists && await source.length() > maxFileBytes) {
      throw const FormatException('File exceeds 20 MB limit');
    }
    final id = _id();
    final metadata = '.tako/history/$id.json';
    final metadataPath = await guard.resolve(metadata, internal: true);
    await File(metadataPath).parent.create(recursive: true);
    if (exists) {
      final bytes = await source.readAsBytes();
      cancel?.throwIfCancelled();
      await _atomicWrite(
        await guard.resolve('.tako/history/$id.bin', internal: true),
        bytes,
        cancel: cancel,
      );
    }
    await _atomicWrite(
      metadataPath,
      utf8.encode(
        jsonEncode({
          'path': path,
          'existed': exists,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        }),
      ),
      cancel: cancel,
    );
    return metadata;
  }

  Future<void> _atomicWrite(
    String destination,
    List<int> bytes, {
    CancelToken? cancel,
  }) async {
    await File(destination).parent.create(recursive: true);
    // Temporary files remain internal and cannot be listed or read by tools.
    final guard = await _guard;
    final temporary = File(
      await guard.resolve('.tako/tmp/${_id()}.tmp', internal: true),
    );
    await temporary.parent.create(recursive: true);
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      cancel?.throwIfCancelled();
      // rename replaces an existing regular file atomically on supported OSes.
      await temporary.rename(destination);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  @override
  Future<void> restoreBackup(
    String backupPath, {
    CancelToken? cancel,
  }) => _exclusive(() async {
    cancel?.throwIfCancelled();
    if (!RegExp(
      r'^\.tako/history/[0-9]+-[0-9a-f]+\.json$',
    ).hasMatch(backupPath)) {
      throw const FormatException('Invalid backup path');
    }
    final guard = await _guard;
    final backupFile = File(await guard.resolve(backupPath, internal: true));
    if (await backupFile.length() > 8192) {
      throw const FormatException('Invalid backup metadata');
    }
    final metadata = jsonDecode(await backupFile.readAsString());
    if (metadata is! Map ||
        metadata['path'] is! String ||
        metadata['existed'] is! bool) {
      throw const FormatException('Invalid backup metadata');
    }
    final destination = File(await guard.resolve(metadata['path'] as String));
    if (metadata['existed'] == true) {
      final dataPath = '${backupPath.substring(0, backupPath.length - 5)}.bin';
      final data = File(await guard.resolve(dataPath, internal: true));
      if (await data.length() > maxFileBytes) {
        throw const FormatException('Backup exceeds size limit');
      }
      await _atomicWrite(
        destination.path,
        await data.readAsBytes(),
        cancel: cancel,
      );
    } else if (await destination.exists()) {
      cancel?.throwIfCancelled();
      await destination.delete();
    }
  });

  @override
  Future<void> pruneHistory({Set<String> protectedPaths = const {}}) =>
      _exclusive(() => _pruneHistory(protectedPaths: protectedPaths));

  Future<void> _pruneHistory({Set<String> protectedPaths = const {}}) async {
    final guard = await _guard;
    final directory = Directory(
      await guard.resolve('.tako/history', internal: true),
    );
    if (!await directory.exists()) return;
    final groups = <String, List<File>>{};
    var total = 0;
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File) continue;
      await guard.resolve(
        '.tako/history/${p.basename(entry.path)}',
        internal: true,
      );
      total += await entry.length();
      groups
          .putIfAbsent(p.basenameWithoutExtension(entry.path), () => [])
          .add(entry);
    }
    final ids = groups.keys.toList()..sort();
    final protected = {
      ...protectedPaths,
      ..._activeBackups,
    }.map(p.posix.basenameWithoutExtension).toSet();
    for (final id in ids) {
      if (total <= maxHistoryBytes) break;
      if (protected.contains(id)) continue;
      for (final file in groups[id]!) {
        final size = await file.length();
        await file.delete();
        total -= size;
      }
    }
  }

  Future<void> _maintainHistory(String protectedPath) async {
    // Maintenance must never discard the receipt for an already committed tool.
    try {
      await _pruneHistory(protectedPaths: {protectedPath});
    } on FileSystemException {
      // A later explicit prune can retry after storage becomes writable.
    } on FormatException {
      // Internal path validation still rejects tampered history directories.
    }
  }

  Future<Uint8List> _readLimited(
    Stream<List<int>> stream,
    CancelToken? cancel,
  ) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      cancel?.throwIfCancelled();
      if (builder.length + chunk.length > maxFileBytes) {
        throw const FormatException('File exceeds 20 MB limit');
      }
      builder.add(chunk);
    }
    cancel?.throwIfCancelled();
    return builder.takeBytes();
  }

  @override
  Future<List<ContentBlock>> importFiles({CancelToken? cancel}) async {
    cancel?.throwIfCancelled();
    final files = await FilePicker.pickFiles();
    cancel?.throwIfCancelled();
    final imported = <ContentBlock>[];
    for (final file in files) {
      cancel?.throwIfCancelled();
      if ((await file.length() ?? 0) > maxFileBytes) {
        throw const FormatException('File exceeds 20 MB limit');
      }
      imported.add(
        await importBytes(
          file.name,
          await _readLimited(file.readAsByteStream(), cancel),
          cancel: cancel,
        ),
      );
    }
    return imported;
  }

  @override
  Future<ImageBlock> importImageBytes(
    String name,
    Uint8List bytes, {
    CancelToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    if (bytes.isEmpty || bytes.length > maxFileBytes) {
      throw const FormatException('Invalid image or file exceeds 20 MB limit');
    }
    // Decode before storing: keyboard MIME labels and picker names are hints,
    // not proof that the payload is a supported image. Normalize once off-thread
    // so GIFs, orientation metadata and provider formats share one send path.
    final normalized = await Isolate.run(() => _prepareImage(bytes));
    cancel?.throwIfCancelled();
    final imageName = '${p.basenameWithoutExtension(name)}.jpg';
    return await importBytes(imageName, normalized, cancel: cancel)
        as ImageBlock;
  }

  @override
  Future<ContentBlock> importBytes(
    String name,
    Uint8List bytes, {
    CancelToken? cancel,
  }) => _exclusive(() async {
    cancel?.throwIfCancelled();
    if (bytes.length > maxFileBytes) {
      throw const FormatException('File exceeds 20 MB limit');
    }
    var safeName = name
        .replaceAll(RegExp(r'[\x00-\x1f\x7f/\\:<>"|?*]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '');
    if (safeName.isEmpty || safeName == '.' || safeName == '..') {
      safeName = 'attachment';
    }
    if (safeName.length > 120) {
      safeName =
          '${safeName.substring(0, 96)}${p.extension(safeName).substring(0, min(20, p.extension(safeName).length))}';
    }
    final relative = 'attachments/${_id()}-$safeName';
    final guard = await _guard;
    final mime = mimeTypeFor(name);
    final extractedText = mime.startsWith('image/')
        ? null
        : await _attachmentText(bytes, mime, cancel);
    await _atomicWrite(await guard.resolve(relative), bytes, cancel: cancel);
    return mime.startsWith('image/')
        ? ImageBlock(path: relative, mimeType: mime, alt: name)
        : FileBlock(
            path: relative,
            name: name,
            mimeType: mime,
            sizeBytes: bytes.length,
            extractedText: extractedText,
          );
  });

  @override
  Future<List<ContentBlock>> hydrateBlocks(
    List<ContentBlock> blocks, {
    required bool vision,
    CancelToken? cancel,
  }) async {
    final hydrated = <ContentBlock>[];
    for (final block in blocks) {
      cancel?.throwIfCancelled();
      if (block is ImageBlock) {
        if (!vision) {
          hydrated.add(
            TextBlock(
              '[Image attachment: ${block.path}; current model does not support vision]',
            ),
          );
        } else {
          hydrated.add((await read(block.path, cancel: cancel)).image!);
        }
      } else if (block is FileBlock) {
        hydrated.add(
          block.extractedText != null
              ? block
              : FileBlock(
                  path: block.path,
                  name: block.name,
                  mimeType: block.mimeType,
                  sizeBytes: block.sizeBytes,
                  extractedText: await _attachmentText(
                    await readBytes(block.path, cancel: cancel),
                    block.mimeType,
                    cancel,
                  ),
                ),
        );
      } else if (block is ToolResultBlock && block.attachments.isNotEmpty) {
        hydrated.add(
          ToolResultBlock(
            toolCallId: block.toolCallId,
            toolName: block.toolName,
            content: block.content,
            isError: block.isError,
            sideEffects: block.sideEffects,
            attachments: await hydrateBlocks(
              block.attachments,
              vision: vision,
              cancel: cancel,
            ),
          ),
        );
      } else {
        hydrated.add(block);
      }
    }
    return hydrated;
  }

  Future<String> _attachmentText(
    Uint8List bytes,
    String mime,
    CancelToken? cancel,
  ) async {
    try {
      final text = mime == 'application/pdf'
          ? await extractPdfText(
              bytes,
              maxCharacters: _maxAttachmentCharacters,
              cancel: cancel,
            )
          : _decodeText(bytes, mime);
      return text.length > _maxAttachmentCharacters
          ? '${text.substring(0, _maxAttachmentCharacters)}\n[truncated]'
          : text;
    } on FormatException catch (error) {
      return '[${error.message}]';
    }
  }

  @override
  Future<void> shareFile(String path) async {
    final file = File(await (await _guard).resolve(path));
    if (!await file.exists()) {
      throw const FormatException('File does not exist');
    }
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }
}

Uint8List _prepareImage(Uint8List bytes) {
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null || info.width * info.height > 40000000) {
    throw const FormatException(
      'Unsupported image or image exceeds 40 megapixels',
    );
  }
  final image = decoder!.decodeFrame(0);
  if (image == null) throw const FormatException('Invalid image');
  final oriented = img.bakeOrientation(image);
  final resized = max(oriented.width, oriented.height) <= 1568
      ? oriented
      : img.copyResize(
          oriented,
          width: oriented.width >= oriented.height ? 1568 : null,
          height: oriented.height > oriented.width ? 1568 : null,
        );
  return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
}

String mimeTypeFor(String path) => switch (p.extension(path).toLowerCase()) {
  '.png' => 'image/png',
  '.jpg' || '.jpeg' => 'image/jpeg',
  '.webp' => 'image/webp',
  '.gif' => 'image/gif',
  '.bmp' => 'image/bmp',
  '.tif' || '.tiff' => 'image/tiff',
  '.pdf' => 'application/pdf',
  '.json' => 'application/json',
  '.xml' || '.svg' => 'application/xml',
  '.txt' ||
  '.md' ||
  '.markdown' ||
  '.csv' ||
  '.tsv' ||
  '.log' ||
  '.yaml' ||
  '.yml' ||
  '.html' ||
  '.htm' ||
  '.dart' ||
  '.py' ||
  '.js' ||
  '.ts' ||
  '.css' ||
  '.java' ||
  '.kt' ||
  '.c' ||
  '.cpp' ||
  '.h' ||
  '.rs' ||
  '.go' ||
  '.sql' ||
  '.sh' ||
  '.toml' ||
  '.ini' => 'text/plain',
  _ => 'application/octet-stream',
};
