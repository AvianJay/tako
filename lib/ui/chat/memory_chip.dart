import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/chat/content_block.dart';
import '../../core/memory/memory.dart';
import '../../l10n/gen/app_localizations.dart';
import 'chat_timeline.dart';

/// "Saved to memory" chips for each completed memory_save in a tool run.
class MemorySavedChips extends StatelessWidget {
  const MemorySavedChips({required this.app, required this.run, super.key});
  final AppController app;
  final ToolRunSegment run;

  @override
  Widget build(BuildContext context) {
    final saved = [
      for (final step in run.steps)
        if (step.call.name == 'memory_save' && step.result?.isError == false)
          for (final effect in step.result!.sideEffects)
            if (MemoryUndo.fromJson(effect.memoryUndo) case final undo?)
              (undo, effect),
    ];
    if (saved.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final (undo, effect) in saved)
          MemorySavedChip(
            key: ValueKey('memory-chip-${undo.id}'),
            app: app,
            undo: undo,
            effect: effect,
          ),
      ],
    );
  }
}

enum _ChipState { checking, undoable, undone, changed }

class MemorySavedChip extends StatefulWidget {
  const MemorySavedChip({
    required this.app,
    required this.undo,
    required this.effect,
    super.key,
  });
  final AppController app;
  final MemoryUndo undo;
  final SideEffect effect;
  @override
  State<MemorySavedChip> createState() => _MemorySavedChipState();
}

class _MemorySavedChipState extends State<MemorySavedChip> {
  var _state = _ChipState.checking;

  @override
  void initState() {
    super.initState();
    _check();
  }

  /// Undo is offered only while the entry is still the saved revision.
  Future<void> _check() async {
    try {
      final entry = await widget.app.memory.get(widget.undo.id);
      if (!mounted) return;
      setState(
        () => _state = entry?.revision == widget.undo.revision
            ? _ChipState.undoable
            : _ChipState.changed,
      );
    } catch (_) {
      if (mounted) setState(() => _state = _ChipState.changed);
    }
  }

  Future<void> _undo() async {
    setState(() => _state = _ChipState.checking);
    var removed = false;
    try {
      removed = await widget.app.undoMemorySave(widget.undo);
    } catch (_) {
      // Reported as changed below; the entry is left as it is.
    }
    if (mounted) {
      setState(() => _state = removed ? _ChipState.undone : _ChipState.changed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final undone = _state == _ChipState.undone;
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            undone ? Icons.bookmark_remove_outlined : Icons.bookmark_added,
            size: 18,
            color: colors.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '${undone ? l.memoryUndone : l.memorySaved} · ${widget.effect.summary}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSecondaryContainer,
                ),
              ),
            ),
          ),
          switch (_state) {
            _ChipState.undoable => TextButton(
              onPressed: _undo,
              child: Text(l.undo),
            ),
            _ChipState.checking => const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
            ),
            _ChipState.changed => Tooltip(
              message: l.memoryChanged,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.info_outline, size: 16),
              ),
            ),
            _ChipState.undone => const SizedBox(width: 8),
          },
        ],
      ),
    );
  }
}
