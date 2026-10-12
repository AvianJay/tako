import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../l10n/gen/app_localizations.dart';

class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key});
  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  late final _workspace = ref.read(appControllerProvider).services.workspace;
  String _path = '';
  late var _entries = _workspace.list();
  void _open(String path) => setState(() {
    _path = path;
    _entries = _workspace.list(path: path);
  });
  Future<void> _run(Future<void> Function() task) async {
    try {
      await task();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).fileUnavailable)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.files),
        actions: [
          IconButton(
            tooltip: l.importFiles,
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: () => _run(() async {
              await _workspace.importFiles();
              if (mounted) _open(_path);
            }),
          ),
        ],
      ),
      body: Column(
        children: [
          ListTile(
            leading: IconButton(
              tooltip: l.workspace,
              icon: const Icon(Icons.arrow_upward),
              onPressed: _path.isEmpty
                  ? null
                  : () {
                      final parts = _path.split('/')..removeLast();
                      _open(parts.join('/'));
                    },
            ),
            title: Text(_path.isEmpty ? l.workspace : _path),
          ),
          Expanded(
            child: FutureBuilder(
              future: _entries,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Center(
                    child: snapshot.hasError
                        ? Text(l.fileUnavailable)
                        : const CircularProgressIndicator(),
                  );
                }
                if (snapshot.data!.isEmpty) {
                  return Center(child: Text(l.emptyFiles));
                }
                return ListView(
                  children: [
                    for (final entry in snapshot.data!)
                      ListTile(
                        leading: Icon(
                          entry.isDirectory
                              ? Icons.folder_outlined
                              : Icons.description_outlined,
                        ),
                        title: Text(entry.name),
                        subtitle: entry.isDirectory
                            ? null
                            : Text('${entry.sizeBytes} B'),
                        onTap: () => entry.isDirectory
                            ? _open(entry.path)
                            : _run(() async {
                                final result = await _workspace.read(
                                  entry.path,
                                  maxCharacters: 30000,
                                );
                                if (!context.mounted) return;
                                await showDialog<void>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text(entry.name),
                                    content: SizedBox(
                                      width: 600,
                                      child: SingleChildScrollView(
                                        child: result.image?.data != null
                                            ? InteractiveViewer(
                                                child: Image.memory(
                                                  base64Decode(
                                                    result.image!.data!,
                                                  ),
                                                ),
                                              )
                                            : SelectableText(result.text),
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => _run(
                                          () =>
                                              _workspace.shareFile(entry.path),
                                        ),
                                        child: Text(l.share),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: Text(l.close),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                        trailing: entry.isDirectory
                            ? null
                            : PopupMenuButton<String>(
                                onSelected: (action) => _run(() async {
                                  if (action == 'share') {
                                    await _workspace.shareFile(entry.path);
                                    return;
                                  }
                                  final yes = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: Text(l.delete),
                                      content: Text(
                                        entry.path.startsWith('attachments/')
                                            ? l.deleteAttachmentBody
                                            : l.deleteFileBody,
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: Text(l.cancel),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: Text(l.delete),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (yes == true) {
                                    final effect = await _workspace.delete(
                                      entry.path,
                                    );
                                    if (context.mounted &&
                                        effect.backupPath != null) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(entry.name),
                                          duration: const Duration(seconds: 12),
                                          action: SnackBarAction(
                                            label: l.undo,
                                            onPressed: () => _run(() async {
                                              await _workspace.restoreBackup(
                                                effect.backupPath!,
                                              );
                                              if (mounted) _open(_path);
                                            }),
                                          ),
                                        ),
                                      );
                                    }
                                    if (mounted) _open(_path);
                                  }
                                }),
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'share',
                                    child: Text(l.share),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text(l.delete),
                                  ),
                                ],
                              ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
