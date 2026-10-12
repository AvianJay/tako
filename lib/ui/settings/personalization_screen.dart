import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../app/app_info.dart';
import '../../core/memory/settings.dart';
import '../../l10n/gen/app_localizations.dart';

class PersonalizationScreen extends ConsumerStatefulWidget {
  const PersonalizationScreen({super.key});
  @override
  ConsumerState<PersonalizationScreen> createState() =>
      _PersonalizationScreenState();
}

class _PersonalizationScreenState extends ConsumerState<PersonalizationScreen> {
  late final _app = ref.read(appControllerProvider);
  late final _name = TextEditingController(
    text: _app.personalization.displayName,
  );
  late final _notes = TextEditingController(
    text: _app.personalization.userNotes,
  );
  late var _style = _app.personalization.replyStyle;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    try {
      await _app.savePersonalization(
        PersonalizationSettings(
          displayName: _name.text.trim(),
          userNotes: _notes.text.trim(),
          replyStyle: _style,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.operationFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final busy = ref.watch(appControllerProvider.select((app) => app.busy));
    return Scaffold(
      appBar: AppBar(
        title: Text(l.personalization),
        actions: [
          TextButton(onPressed: busy ? null : _save, child: Text(l.save)),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(l.personalizationHelp),
              const SizedBox(height: 20),
              TextField(
                key: const ValueKey('personalization-name'),
                controller: _name,
                maxLength: PersonalizationSettings.maxNameLength,
                decoration: InputDecoration(labelText: l.displayName(kAppName)),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('personalization-notes'),
                controller: _notes,
                minLines: 4,
                maxLines: 12,
                maxLength: PersonalizationSettings.maxNotesLength,
                decoration: InputDecoration(
                  labelText: l.customInstructions,
                  hintText: l.customInstructionsHint(kAppName),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              Text(l.replyStyle, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 10),
              SegmentedButton<ReplyStyle>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: ReplyStyle.concise,
                    label: Text(l.replyConcise),
                  ),
                  ButtonSegment(
                    value: ReplyStyle.normal,
                    label: Text(l.replyNormal),
                  ),
                  ButtonSegment(
                    value: ReplyStyle.detailed,
                    label: Text(l.replyDetailed),
                  ),
                ],
                selected: {_style},
                onSelectionChanged: (value) =>
                    setState(() => _style = value.single),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
