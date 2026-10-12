import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../l10n/gen/app_localizations.dart';

/// The Shortcuts the model may list and run. iOS cannot list a user's
/// Shortcuts to apps, so the user types their names.
class ShortcutsScreen extends ConsumerStatefulWidget {
  const ShortcutsScreen({super.key});
  @override
  ConsumerState<ShortcutsScreen> createState() => _ShortcutsScreenState();
}

class _ShortcutsScreenState extends ConsumerState<ShortcutsScreen> {
  late final _app = ref.read(appControllerProvider);
  late List<String> _names = List.of(_app.services.shortcuts.names);

  Future<void> _save(List<String> names) async {
    await _app.saveShortcutNames(names);
    if (mounted) setState(() => _names = _app.services.shortcuts.names);
  }

  Future<void> _add() async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.addShortcut),
        content: TextField(
          key: const ValueKey('shortcut-name'),
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l.shortcutName),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(l.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) {
      await _save([..._names, name]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.shortcuts)),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add-shortcut'),
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(l.addShortcut),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
            children: [
              Text(l.shortcutsIntro),
              const SizedBox(height: 16),
              if (_names.isEmpty) Text(l.noShortcuts),
              for (final name in _names)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bolt_outlined),
                  title: Text(name),
                  trailing: IconButton(
                    tooltip: l.delete,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _save([
                      for (final n in _names)
                        if (n != name) n,
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
