import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app_controller.dart';
import '../../core/automation/automation.dart';
import '../../core/automation/condition.dart';
import '../../core/chat/content_block.dart';
import '../../core/chat/message.dart';
import '../../core/util/ids.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../platform/app_services.dart';
import '../chat/tool_widgets.dart';

String automationStatusLabel(AutomationStatus value, AppLocalizations l) =>
    switch (value) {
      AutomationStatus.queued => l.automationQueued,
      AutomationStatus.running => l.automationRunning,
      AutomationStatus.waiting => l.automationWaiting,
      AutomationStatus.completed => l.automationCompleted,
      AutomationStatus.silent => l.automationSilent,
      AutomationStatus.failed => l.automationFailed,
      AutomationStatus.cancelled => l.automationCancelled,
      AutomationStatus.timedOut => l.automationTimedOut,
    };
String automationTriggerLabel(AutomationTrigger value, AppLocalizations l) =>
    switch (value) {
      AutomationTrigger.schedule => l.automationSchedule,
      AutomationTrigger.notification => l.automationNotification,
      AutomationTrigger.shortcut => l.automationShortcut,
    };
String automationReason(String? value, AppLocalizations l) => switch (value) {
  'approval' => l.automationReasonApproval,
  'foreground' => l.automationReasonForeground,
  'interrupted' => l.automationReasonInterrupted,
  'timeout' => l.automationTimedOut,
  'paused' => l.automationReasonPaused,
  null => '',
  _ => l.automationReasonFailed,
};
Future<void> _perform(
  BuildContext context,
  Future<void> Function() work,
) async {
  try {
    await work();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).automationInvalid)),
      );
    }
  }
}

class AutomationsScreen extends ConsumerWidget {
  const AutomationsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appControllerProvider),
        l = AppLocalizations.of(context);
    final automation = app.automation;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.automations),
        actions: [
          IconButton(
            tooltip: l.automationClearHistory,
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(l.automationClearHistory),
                  content: Text(l.automationClearHistoryConfirm),
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
              );
              if (confirmed == true && context.mounted) {
                await _perform(context, automation.clearHistory);
              }
            },
          ),
          IconButton(
            tooltip: l.automationRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: () => _perform(context, automation.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: app.providers.isEmpty
            ? null
            : () => Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const AutomationEditor()),
              ),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: automation.refresh,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(l.automationHelp),
            const SizedBox(height: 12),
            if (automation.platformStatus['canPost'] != true)
              ListTile(
                title: Text(l.automationAllowNotifications),
                leading: const Icon(Icons.notifications_outlined),
                onTap: () => _perform(context, () async {
                  await app.services.automation.requestNotifications();
                  await automation.refresh();
                }),
              ),
            if (app.services.automation.shortcutEntry) ...[
              Text(l.automationIosHelp),
              const SizedBox(height: 8),
              ExpansionTile(
                title: Text(l.automationShortcutGuide),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(l.automationShortcutsHelp),
                  ),
                ],
              ),
            ],
            if (automation.rules.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l.automationNoRules),
              ),
            for (final rule in automation.rules)
              Card(
                child: ListTile(
                  title: Text(rule.name),
                  subtitle: Text(
                    '${rule.model}\n${rule.condition.isEmpty ? automationTriggerLabel(rule.trigger, l) : rule.condition}${rule.schedule.exact && automation.platformStatus['exact'] != true ? '\n${l.automationExactRequired}' : ''}${rule.enabled && rule.trigger == AutomationTrigger.notification && !app.services.notifications.access ? '\n${l.automationNotificationAccess}' : ''}',
                  ),
                  isThreeLine: true,
                  leading: Switch(
                    value: rule.enabled,
                    onChanged: (value) => _perform(context, () async {
                      await automation.saveRule(rule.copyWith(enabled: value));
                    }),
                  ),
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AutomationEditor(rule: rule),
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: l.automationRunNow,
                    icon: const Icon(Icons.play_arrow),
                    onPressed: rule.enabled
                        ? () => _perform(context, () async {
                            final run = await automation.runRule(rule.id);
                            if (context.mounted) {
                              await Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      AutomationRunScreen(runId: run.id),
                                ),
                              );
                            }
                          })
                        : null,
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Text(
              l.automationRuns,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              l.automationRecentRuns,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (automation.runs.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l.automationNoRuns),
              ),
            for (final run in automation.runs)
              ListTile(
                title: Text(run.rule.name),
                subtitle: Text(
                  '${DateFormat.yMd().add_Hm().format(run.createdAt.toLocal())} · ${automationStatusLabel(run.status, l)}',
                ),
                leading: Icon(
                  run.status == AutomationStatus.waiting
                      ? Icons.pause_circle_outline
                      : run.status == AutomationStatus.silent
                      ? Icons.notifications_off_outlined
                      : Icons.history,
                ),
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AutomationRunScreen(runId: run.id),
                  ),
                ),
              ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class AutomationEditor extends ConsumerStatefulWidget {
  const AutomationEditor({this.rule, super.key});
  final AutomationRule? rule;
  @override
  ConsumerState<AutomationEditor> createState() => _AutomationEditorState();
}

class _AutomationEditorState extends ConsumerState<AutomationEditor> {
  late final _name = TextEditingController(text: widget.rule?.name),
      _prompt = TextEditingController(text: widget.rule?.prompt),
      _condition = TextEditingController(text: widget.rule?.condition),
      _package = TextEditingController(),
      _title = TextEditingController(),
      _text = TextEditingController();
  late final _window = TextEditingController(
        text: '${widget.rule?.windowSeconds ?? 60}',
      ),
      _interval = TextEditingController(
        text: '${widget.rule?.schedule.everyMinutes ?? 60}',
      ),
      _timeout = TextEditingController(
        text: widget.rule?.waitTimeoutMinutes?.toString() ?? '',
      );
  late AutomationTrigger _trigger =
      widget.rule?.trigger ?? AutomationTrigger.schedule;
  late AutomationBatch _batch = widget.rule?.batch ?? AutomationBatch.immediate;
  late bool _enabled = widget.rule?.enabled ?? false,
      _continue = widget.rule?.continueConversation ?? false,
      _exact = widget.rule?.schedule.exact ?? false;
  late String _frequency = widget.rule?.schedule.frequency ?? 'daily';
  late TimeOfDay _time = TimeOfDay(
    hour: widget.rule?.schedule.hour ?? 20,
    minute: widget.rule?.schedule.minute ?? 0,
  );
  late DateTime _at =
      widget.rule?.schedule.at?.toLocal() ??
      DateTime.now().add(const Duration(hours: 1));
  late final Set<int> _weekdays =
      (widget.rule?.schedule.weekdays ?? [1, 2, 3, 4, 5, 6, 7]).toSet();
  String? _provider, _model;
  bool _advanced = false, _saving = false;
  @override
  void initState() {
    super.initState();
    final form = NotificationCondition.formValues(_condition.text);
    _advanced = form == null;
    _package.text = form?['package'] ?? '';
    _title.text = form?['title'] ?? '';
    _text.text = form?['text'] ?? '';
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _prompt,
      _condition,
      _package,
      _title,
      _text,
      _window,
      _interval,
      _timeout,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fromForm() {
    _condition.text = NotificationCondition.form(
      package: _package.text.trim(),
      title: _title.text,
      text: _text.text,
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int lines = 1,
    bool number = false,
    void Function(String)? changed,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      minLines: lines,
      maxLines: lines == 1 ? 1 : lines + 4,
      keyboardType: number ? TextInputType.number : null,
      inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
      onChanged: changed,
    ),
  );
  Future<void> _save() async {
    final app = ref.read(appControllerProvider);
    setState(() => _saving = true);
    await _perform(context, () async {
      final rule = AutomationRule(
        id: widget.rule?.id ?? newId(),
        name: _name.text.trim(),
        prompt: _prompt.text.trim(),
        providerId: _provider ?? '',
        model: _model ?? '',
        enabled: _enabled,
        trigger: _trigger,
        condition: _condition.text,
        batch: _batch,
        windowSeconds: int.tryParse(_window.text) ?? 0,
        continueConversation: _continue,
        waitTimeoutMinutes: _timeout.text.trim().isEmpty
            ? null
            : int.parse(_timeout.text),
        schedule: AutomationSchedule(
          frequency: _frequency,
          hour: _time.hour,
          minute: _time.minute,
          weekdays: _weekdays.toList()..sort(),
          everyMinutes: int.tryParse(_interval.text) ?? 0,
          at: _at,
          exact: _exact,
        ),
      );
      await app.automation.saveRule(rule);
      if (mounted) Navigator.pop(context);
    });
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _test() async {
    final l = AppLocalizations.of(context);
    final data = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert({
        'package': _package.text,
        'title': _title.text,
        'text': _text.text,
        'lines': <String>[],
        'ongoing': false,
      }),
    );
    String? outcome;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(l.automationTest),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.automationTestHelp),
                  _field(data, l.automationInput, lines: 6),
                  if (outcome != null) SelectableText(outcome!),
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
              onPressed: () {
                try {
                  final values = (jsonDecode(data.text) as Map)
                      .cast<String, Object?>();
                  final yes = NotificationCondition(
                    _condition.text,
                  ).matches(values);
                  set(
                    () => outcome =
                        '${yes ? l.automationTestMatches : l.automationTestNoMatch}\n${_condition.text}',
                  );
                } catch (_) {
                  set(() => outcome = l.automationInvalid);
                }
              },
              child: Text(l.automationTest),
            ),
          ],
        ),
      ),
    );
    data.dispose();
  }

  Widget _schedule(AppController app, AppLocalizations l) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DropdownButtonFormField<String>(
        initialValue: _frequency,
        decoration: InputDecoration(labelText: l.automationSchedule),
        items: [
          for (final entry in {
            'once': l.automationOnce,
            'daily': l.automationDaily,
            'weekly': l.automationWeekly,
            'interval': l.automationInterval,
          }.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (value) => setState(() => _frequency = value!),
      ),
      if (_frequency == 'interval')
        _field(_interval, l.automationEveryMinutes, number: true)
      else if (_frequency == 'once')
        ListTile(
          title: Text(l.automationDate),
          subtitle: Text(DateFormat.yMd().add_Hm().format(_at)),
          trailing: const Icon(Icons.event),
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _at,
              firstDate: DateTime.now().subtract(const Duration(days: 1)),
              lastDate: DateTime.now().add(const Duration(days: 3650)),
            );
            if (date == null || !mounted) return;
            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(_at),
            );
            if (time != null && mounted) {
              setState(
                () => _at = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                ),
              );
            }
          },
        )
      else
        ListTile(
          title: Text(l.automationTime),
          trailing: Text(_time.format(context)),
          onTap: () async {
            final time = await showTimePicker(
              context: context,
              initialTime: _time,
            );
            if (time != null) setState(() => _time = time);
          },
        ),
      if (_frequency == 'weekly')
        Wrap(
          spacing: 6,
          children: [
            for (var day = 1; day <= 7; day++)
              FilterChip(
                label: Text(
                  DateFormat.E(
                    app.locale.toLanguageTag(),
                  ).format(DateTime(2024, 1, day)),
                ),
                selected: _weekdays.contains(day),
                onSelected: (value) => setState(
                  () => value ? _weekdays.add(day) : _weekdays.remove(day),
                ),
              ),
          ],
        ),
      if (app.services.automation.exactSchedules) ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.automationExact),
          subtitle: Text(l.automationExactHelp),
          value: _exact,
          onChanged: (value) => setState(() => _exact = value),
        ),
        if (_exact && app.automation.platformStatus['exact'] != true)
          TextButton(
            onPressed: () => _perform(
              context,
              app.services.automation.requestExactPermission,
            ),
            child: Text(l.automationExactRequired),
          ),
      ],
    ],
  );
  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider),
        l = AppLocalizations.of(context);
    _provider ??=
        widget.rule?.providerId ??
        app.selectedProviderId ??
        app.providers.firstOrNull?.id;
    final provider = app.providers.where((p) => p.id == _provider).firstOrNull;
    _model ??= widget.rule?.model ?? provider?.model;
    final models = provider == null
        ? <String>{}
        : {provider.model, ...provider.models.map((m) => m.id)};
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rule?.name ?? l.automations),
        actions: [
          if (widget.rule != null)
            IconButton(
              tooltip: l.delete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _perform(context, () async {
                final yes = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text(l.delete),
                    content: Text(l.automationDeleteConfirm),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: Text(l.cancel),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: Text(l.delete),
                      ),
                    ],
                  ),
                );
                if (yes == true) {
                  await app.automation.deleteRule(widget.rule!.id);
                  if (context.mounted) Navigator.pop(context);
                }
              }),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _field(_name, l.automationName),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.automationEnabled),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
              DropdownButtonFormField<AutomationTrigger>(
                initialValue: _trigger,
                decoration: InputDecoration(labelText: l.automationTrigger),
                items: [
                  DropdownMenuItem(
                    value: AutomationTrigger.schedule,
                    child: Text(l.automationSchedule),
                  ),
                  if (app.services.automation.notificationTriggers)
                    DropdownMenuItem(
                      value: AutomationTrigger.notification,
                      child: Text(l.automationNotification),
                    ),
                  if (app.services.automation.shortcutEntry)
                    DropdownMenuItem(
                      value: AutomationTrigger.shortcut,
                      child: Text(l.automationShortcut),
                    ),
                ],
                onChanged: (v) => setState(() => _trigger = v!),
              ),
              if (_trigger == AutomationTrigger.notification) ...[
                TextButton.icon(
                  onPressed: () => _perform(
                    context,
                    app.services.notifications.openAccessSettings,
                  ),
                  icon: const Icon(Icons.notifications_outlined),
                  label: Text(l.automationNotificationAccess),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.automationAdvanced),
                  value: _advanced,
                  onChanged: (v) {
                    if (!v) {
                      final form = NotificationCondition.formValues(
                        _condition.text,
                      );
                      if (form == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l.automationFormNotRepresentable),
                          ),
                        );
                        return;
                      }
                      _package.text = form['package'] ?? '';
                      _title.text = form['title'] ?? '';
                      _text.text = form['text'] ?? '';
                    }
                    setState(() => _advanced = v);
                  },
                ),
                if (_advanced) ...[
                  _field(_condition, l.automationCondition, lines: 3),
                  Text(l.automationConditionHelp),
                ] else ...[
                  _field(
                    _package,
                    l.automationPackage,
                    changed: (_) => _fromForm(),
                  ),
                  _field(
                    _title,
                    l.automationTitleContains,
                    changed: (_) => _fromForm(),
                  ),
                  _field(
                    _text,
                    l.automationTextContains,
                    changed: (_) => _fromForm(),
                  ),
                ],
                OutlinedButton(onPressed: _test, child: Text(l.automationTest)),
                DropdownButtonFormField<AutomationBatch>(
                  initialValue: _batch,
                  decoration: InputDecoration(labelText: l.automationBatch),
                  items: [
                    DropdownMenuItem(
                      value: AutomationBatch.immediate,
                      child: Text(l.automationImmediate),
                    ),
                    DropdownMenuItem(
                      value: AutomationBatch.window,
                      child: Text(l.automationWindow),
                    ),
                    DropdownMenuItem(
                      value: AutomationBatch.scheduled,
                      child: Text(l.automationDigest),
                    ),
                  ],
                  onChanged: (v) => setState(() => _batch = v!),
                ),
                if (_batch == AutomationBatch.window)
                  _field(_window, l.automationWindowSeconds, number: true),
              ],
              if (_trigger == AutomationTrigger.schedule ||
                  _trigger == AutomationTrigger.notification &&
                      _batch == AutomationBatch.scheduled)
                _schedule(app, l),
              if (_trigger == AutomationTrigger.shortcut)
                Text(l.automationShortcutsHelp),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: provider?.id,
                decoration: InputDecoration(labelText: l.providers),
                items: [
                  for (final p in app.providers)
                    DropdownMenuItem(value: p.id, child: Text(p.displayName)),
                ],
                onChanged: (v) => setState(() {
                  _provider = v;
                  _model = app.providers.firstWhere((p) => p.id == v).model;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(_provider),
                initialValue: models.contains(_model) ? _model : null,
                decoration: InputDecoration(labelText: l.automationModel),
                isExpanded: true,
                items: [
                  for (final model in models)
                    DropdownMenuItem(
                      value: model,
                      child: Text(model, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _model = v),
              ),
              _field(_prompt, l.automationPrompt, lines: 5),
              Text(l.automationPromptHelp),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.automationContinue),
                subtitle: Text(l.automationIndependent),
                value: _continue,
                onChanged: (v) => setState(() => _continue = v),
              ),
              _field(_timeout, l.automationTimeout, number: true),
              Text(l.automationNoTimeout),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(l.save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AutomationRunScreen extends ConsumerStatefulWidget {
  const AutomationRunScreen({required this.runId, super.key});
  final String runId;
  @override
  ConsumerState<AutomationRunScreen> createState() =>
      _AutomationRunScreenState();
}

class _AutomationRunScreenState extends ConsumerState<AutomationRunScreen> {
  String? _historyKey;
  Future<List<ChatMessage>>? _history;
  late final AppController _app;
  @override
  void initState() {
    super.initState();
    _app = ref.read(appControllerProvider);
    unawaited(_app.automation.watchRun(widget.runId));
  }

  @override
  void didUpdateWidget(AutomationRunScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runId != widget.runId) {
      _app.automation.unwatchRun(oldWidget.runId);
      unawaited(_app.automation.watchRun(widget.runId));
    }
  }

  @override
  void dispose() {
    _app.automation.unwatchRun(widget.runId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider),
        l = AppLocalizations.of(context);
    final runId = widget.runId;
    final run = app.automation.runs.where((r) => r.id == runId).firstOrNull;
    final key =
        '${run?.conversationId}:${run?.status}:${(run?.pending['receipts'] as List?)?.length}';
    if (run?.conversationId != null && key != _historyKey) {
      _historyKey = key;
      _history = app.chats.getMessages(run!.conversationId!);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(run?.rule.name ?? l.automationDetails),
        actions: [
          IconButton(
            tooltip: l.automationRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: () => _perform(context, app.automation.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: run == null
                ? Center(child: Text(l.automationNoRuns))
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        automationStatusLabel(run.status, l),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (run.reason != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(automationReason(run.reason, l)),
                        ),
                      if (!run.terminal)
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton(
                              onPressed: run.status == AutomationStatus.running
                                  ? null
                                  : () => _perform(
                                      context,
                                      () => app.automation.resume(runId),
                                    ),
                              child: Text(l.automationResume),
                            ),
                            TextButton(
                              onPressed: () => _perform(
                                context,
                                () => app.automation.cancel(runId),
                              ),
                              child: Text(l.automationCancel),
                            ),
                          ],
                        ),
                      Text('${l.automationModel}: ${run.rule.model}'),
                      const SizedBox(height: 12),
                      SelectableText(run.rule.prompt),
                      if (run.inputs.isNotEmpty)
                        ExpansionTile(
                          title: Text(l.automationInput),
                          children: [
                            SelectableText(
                              const JsonEncoder.withIndent(
                                '  ',
                              ).convert(run.inputs),
                            ),
                          ],
                        ),
                      if (run.status == AutomationStatus.waiting &&
                          run.pending.isNotEmpty)
                        ExpansionTile(
                          title: Text(l.automationWaiting),
                          children: [
                            SelectableText(
                              const JsonEncoder.withIndent(
                                '  ',
                              ).convert(run.pending),
                            ),
                          ],
                        ),
                      if (run.result.isNotEmpty) ...[
                        const Divider(),
                        Text(
                          l.automationResult,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        SelectableText(run.result),
                      ],
                      if (run.conversationId != null)
                        FutureBuilder<List<ChatMessage>>(
                          future: _history,
                          builder: (context, snapshot) => Column(
                            children: [
                              for (final message
                                  in snapshot.data ?? <ChatMessage>[])
                                if (!message.createdAt.isBefore(run.createdAt))
                                  for (final block in message.content)
                                    if (block is ToolResultBlock)
                                      ExpansionTile(
                                        title: Text(
                                          toolLabel(block.toolName, l),
                                        ),
                                        children: [
                                          SelectableText(block.content),
                                        ],
                                      )
                                    else if (block is ImageBlock ||
                                        block is FileBlock)
                                      TextButton(
                                        onPressed: () =>
                                            _perform(context, () async {
                                              await app.openConversation(
                                                run.conversationId!,
                                              );
                                              if (context.mounted) {
                                                Navigator.of(context).popUntil(
                                                  (route) => route.isFirst,
                                                );
                                              }
                                            }),
                                        child: Text(
                                          l.automationViewConversation,
                                        ),
                                      ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          if (app.pendingApproval != null) ToolApprovalSheet(app: app),
        ],
      ),
    );
  }
}
