import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app_controller.dart';
import '../../app/app_info.dart';
import '../../core/memory/memory.dart';
import '../../core/memory/settings.dart';
import '../../data/memory_repository.dart';
import '../../l10n/gen/app_localizations.dart';

String memoryKindLabel(MemoryKind kind, AppLocalizations l) => switch (kind) {
  MemoryKind.profile => l.memoryKindProfile,
  MemoryKind.preference => l.memoryKindPreference,
  MemoryKind.fact => l.memoryKindFact,
};

class MemoryScreen extends ConsumerStatefulWidget {
  const MemoryScreen({super.key});
  @override
  ConsumerState<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends ConsumerState<MemoryScreen> {
  late final _app = ref.read(appControllerProvider);
  late final MemoryRepository _memory = _app.memory;
  final _search = TextEditingController();
  // Separate subscriptions: the profile usage and the (filtered) list.
  late final Stream<List<MemoryEntry>> _all = _memory.watch();
  late Stream<List<MemoryEntry>> _results = _memory.watch();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _query(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _results = _memory.watch(query: value));
    });
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() action, {String? failure}) async {
    try {
      await action();
    } on MemoryFailure catch (error) {
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      _message(
        error.code == 'memory_changed' || error.code == 'memory_not_found'
            ? l.memoryChanged
            : failure ?? l.operationFailed,
      );
    } catch (_) {
      if (mounted) {
        _message(failure ?? AppLocalizations.of(context).operationFailed);
      }
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final l = AppLocalizations.of(context);
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.delete),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _edit([MemoryEntry? entry]) async {
    final result = await showDialog<_MemoryDraft>(
      context: context,
      builder: (_) => _MemoryEditor(entry: entry),
    );
    if (result == null || !mounted) return;
    await _run(() async {
      if (entry == null) {
        await _memory.save(
          text: result.text,
          kind: result.kind,
          pinned: result.pinned,
        );
      } else {
        await _memory.update(
          entry.id,
          text: result.text,
          kind: result.kind,
          pinned: result.pinned,
          expectedRevision: entry.revision,
        );
      }
    });
  }

  Future<void> _delete(MemoryEntry entry) async {
    final l = AppLocalizations.of(context);
    if (!await _confirm(l.delete, l.deleteMemoryBody)) return;
    await _run(() async {
      await _memory.delete(entry.id, expectedRevision: entry.revision);
    });
  }

  Future<void> _menu(String action) async {
    final l = AppLocalizations.of(context);
    switch (action) {
      case 'export':
        await _run(() async {
          final date = DateFormat('yyyyMMdd').format(DateTime.now());
          await _app.services.shareTextFile(
            '${kAppName.toLowerCase()}-memories-$date.json',
            await _memory.exportJson(),
          );
        });
      case 'import':
        await _run(() async {
          final source = await _app.services.pickTextFile(
            maxBytes: MemoryRepository.maxImportBytes,
          );
          if (source == null) return;
          final count = await _memory.importJson(source);
          _message(l.memoriesImported(count));
        }, failure: l.memoryImportFailed(kAppName));
      case 'clear':
        if (await _confirm(l.deleteAllMemories, l.deleteAllMemoriesBody)) {
          await _run(_memory.clear);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final app = ref.watch(appControllerProvider);
    final enabled = app.memorySettings.enabled;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.memory),
        actions: [
          IconButton(
            tooltip: l.addMemory,
            onPressed: _edit,
            icon: const Icon(Icons.add),
          ),
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => [
              PopupMenuItem(value: 'export', child: Text(l.exportMemories)),
              PopupMenuItem(value: 'import', child: Text(l.importMemories)),
              PopupMenuItem(value: 'clear', child: Text(l.deleteAllMemories)),
            ],
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              SwitchListTile(
                title: Text(l.memoryEnabled),
                subtitle: Text(
                  enabled ? l.memoryEnabledHelp(kAppName) : l.memoryOff,
                ),
                value: enabled,
                onChanged: app.busy
                    ? null
                    : (value) => _run(
                        () => app.saveMemorySettings(
                          MemorySettings(enabled: value),
                        ),
                      ),
              ),
              StreamBuilder<List<MemoryEntry>>(
                stream: _all,
                builder: (context, snapshot) {
                  final entries = [...?snapshot.data]
                    ..sort((a, b) {
                      final time = a.createdAt.compareTo(b.createdAt);
                      return time != 0 ? time : a.id.compareTo(b.id);
                    });
                  final profile = MemoryRepository.buildProfile(entries);
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.memoryProfileUsage(
                            profile.words,
                            MemoryRepository.profileWordLimit,
                          ),
                          style: theme.textTheme.labelMedium,
                        ),
                        if (profile.truncated)
                          Text(
                            l.memoryProfileTruncated,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: _query,
                  decoration: InputDecoration(
                    hintText: l.memorySearchHint,
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<MemoryEntry>>(
                  stream: _results,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(child: Text(l.operationFailed));
                    }
                    final entries = snapshot.data;
                    if (entries == null) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (entries.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _search.text.trim().isEmpty
                                ? l.memoryEmpty(kAppName)
                                : l.memoryNoMatches,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      itemCount: entries.length,
                      itemBuilder: (context, index) => _MemoryTile(
                        key: ValueKey(entries[index].id),
                        entry: entries[index],
                        onEdit: _edit,
                        onDelete: _delete,
                        onPin: (entry) => _run(
                          () => _memory.update(
                            entry.id,
                            pinned: !entry.pinned,
                            expectedRevision: entry.revision,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemoryTile extends StatelessWidget {
  const _MemoryTile({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
    required this.onPin,
    super.key,
  });
  final MemoryEntry entry;
  final ValueChanged<MemoryEntry> onEdit;
  final ValueChanged<MemoryEntry> onDelete;
  final ValueChanged<MemoryEntry> onPin;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final details = [
      memoryKindLabel(entry.kind, l),
      DateFormat.yMMMd(l.localeName).format(entry.updatedAt.toLocal()),
      if (entry.sourceMessageId != null) l.memoryFromChat,
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        onTap: () => onEdit(entry),
        title: Text(entry.text, maxLines: 4, overflow: TextOverflow.ellipsis),
        subtitle: Text(details, style: theme.textTheme.bodySmall),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: entry.pinned ? l.memoryUnpin : l.memoryPin,
              isSelected: entry.pinned,
              onPressed: () => onPin(entry),
              icon: const Icon(Icons.push_pin_outlined),
              selectedIcon: const Icon(Icons.push_pin),
            ),
            IconButton(
              tooltip: l.delete,
              onPressed: () => onDelete(entry),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoryDraft {
  const _MemoryDraft(this.text, this.kind, this.pinned);
  final String text;
  final MemoryKind kind;
  final bool pinned;
}

class _MemoryEditor extends StatefulWidget {
  const _MemoryEditor({this.entry});
  final MemoryEntry? entry;
  @override
  State<_MemoryEditor> createState() => _MemoryEditorState();
}

class _MemoryEditorState extends State<_MemoryEditor> {
  late final _text = TextEditingController(text: widget.entry?.text ?? '');
  late var _kind = widget.entry?.kind ?? MemoryKind.fact;
  late var _pinned = widget.entry?.pinned ?? false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.entry == null ? l.addMemory : l.editMemory),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _text,
                autofocus: widget.entry == null,
                minLines: 2,
                maxLines: 8,
                maxLength: MemoryRepository.maxTextLength,
                decoration: InputDecoration(labelText: l.memoryText),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Text(l.memoryKind, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<MemoryKind>(
                showSelectedIcon: false,
                segments: [
                  for (final kind in MemoryKind.values)
                    ButtonSegment(
                      value: kind,
                      label: Text(memoryKindLabel(kind, l)),
                    ),
                ],
                selected: {_kind},
                onSelectionChanged: (value) =>
                    setState(() => _kind = value.single),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.memoryPinned),
                subtitle: Text(l.memoryPinHelp),
                value: _pinned,
                onChanged: (value) => setState(() => _pinned = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: _text.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  _MemoryDraft(_text.text, _kind, _pinned),
                ),
          child: Text(l.save),
        ),
      ],
    );
  }
}
