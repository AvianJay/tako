import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../core/permissions/permission_gate.dart';
import '../../l10n/gen/app_localizations.dart';
import '../chat/tool_widgets.dart';

class ToolSettingsScreen extends ConsumerStatefulWidget {
  const ToolSettingsScreen({super.key});
  @override
  ConsumerState<ToolSettingsScreen> createState() => _ToolSettingsScreenState();
}

class _ToolSettingsScreenState extends ConsumerState<ToolSettingsScreen> {
  late final _app = ref.read(appControllerProvider);
  late final _steps = TextEditingController(
    text: '${_app.toolSettings.maxSteps}',
  );
  late final _screenSteps = TextEditingController(
    text: '${_app.toolSettings.maxScreenSteps}',
  );
  late final _limit = TextEditingController(
    text: '${_app.toolSettings.maxOutputChars}',
  );
  late final _keywords = TextEditingController(
    text: _app.permissionGate.policy.highRiskKeywords.join('\n'),
  );
  @override
  void dispose() {
    _steps.dispose();
    _screenSteps.dispose();
    _limit.dispose();
    _keywords.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider);
    final l = AppLocalizations.of(context);
    Future<bool> confirm(String title, String body) async =>
        await showDialog<bool>(
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
                child: Text(l.continueAction),
              ),
            ],
          ),
        ) ??
        false;
    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l.operationFailed)));
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.toolsSettings),
        actions: [
          TextButton(
            onPressed: app.busy
                ? null
                : () => run(() async {
                    final steps = int.tryParse(_steps.text),
                        screenSteps = int.tryParse(_screenSteps.text),
                        limit = int.tryParse(_limit.text);
                    if (steps == null ||
                        steps < 1 ||
                        steps > 100 ||
                        screenSteps == null ||
                        screenSteps < 1 ||
                        screenSteps > 200 ||
                        limit == null ||
                        limit < 256 ||
                        limit > 60000) {
                      throw const FormatException();
                    }
                    await app.saveToolSettings(
                      app.toolSettings.copyWith(
                        maxSteps: steps,
                        maxScreenSteps: screenSteps,
                        maxOutputChars: limit,
                      ),
                    );
                    await app.savePermissionPolicy(
                      app.permissionGate.policy.copyWith(
                        highRiskKeywords: _keywords.text
                            .split('\n')
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .toList(),
                      ),
                    );
                    if (context.mounted) Navigator.pop(context);
                  }),
            child: Text(l.save),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: Text(l.toolsEnabled),
            value: app.toolSettings.enabled,
            onChanged: app.busy
                ? null
                : (v) => run(
                    () => app.saveToolSettings(
                      app.toolSettings.copyWith(enabled: v),
                    ),
                  ),
          ),
          if (app.selectedProvider?.capabilities.tools == false)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(l.toolsUnavailable),
            ),
          TextFormField(
            controller: _steps,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l.maxToolSteps),
            onFieldSubmitted: (text) {
              final n = int.tryParse(text);
              if (n != null && n >= 1 && n <= 100) {
                run(
                  () => app.saveToolSettings(
                    app.toolSettings.copyWith(maxSteps: n),
                  ),
                );
              }
            },
          ),
          if (app.services.screen.supported) ...[
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('max-screen-steps'),
              controller: _screenSteps,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.maxScreenToolSteps),
              onFieldSubmitted: (text) {
                final n = int.tryParse(text);
                if (n != null && n >= 1 && n <= 200) {
                  run(
                    () => app.saveToolSettings(
                      app.toolSettings.copyWith(maxScreenSteps: n),
                    ),
                  );
                }
              },
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _limit,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l.toolOutputLimit),
            onFieldSubmitted: (text) {
              final n = int.tryParse(text);
              if (n != null && n >= 256 && n <= 60000) {
                run(
                  () => app.saveToolSettings(
                    app.toolSettings.copyWith(maxOutputChars: n),
                  ),
                );
              }
            },
          ),
          const Divider(height: 32),
          Text(l.permissions, style: Theme.of(context).textTheme.titleLarge),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.fullPermissions),
            subtitle: Text(l.fullPermissionsWarning),
            value: app.permissionGate.policy.fullPermissions,
            onChanged: app.busy
                ? null
                : (v) async {
                    if (!v ||
                        await confirm(
                          l.fullPermissions,
                          l.fullPermissionsWarning,
                        )) {
                      await run(
                        () => app.savePermissionPolicy(
                          app.permissionGate.policy.copyWith(
                            fullPermissions: v,
                          ),
                        ),
                      );
                    }
                  },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.skipHighRisk),
            subtitle: Text(l.skipHighRiskWarning),
            value: app.permissionGate.policy.skipHighRiskConfirmations,
            onChanged: app.busy
                ? null
                : (v) async {
                    if (!v ||
                        await confirm(l.skipHighRisk, l.skipHighRiskWarning)) {
                      await run(
                        () => app.savePermissionPolicy(
                          app.permissionGate.policy.copyWith(
                            skipHighRiskConfirmations: v,
                          ),
                        ),
                      );
                    }
                  },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.auditLog),
            leading: const Icon(Icons.history),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => const AuditScreen()),
            ),
          ),
          const Divider(height: 24),
          Text(l.toolOverrides, style: Theme.of(context).textTheme.titleLarge),
          for (final tool in app.toolRegistry.allTools)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(toolLabel(tool.name, l)),
                      subtitle: Text(
                        tool.requires.isAvailable ? tool.name : l.toolDisabled,
                      ),
                      value:
                          !app.toolSettings.disabled.contains(tool.name) &&
                          tool.requires.isAvailable,
                      onChanged: app.busy || !tool.requires.isAvailable
                          ? null
                          : (v) => run(
                              () => app.saveToolSettings(
                                app.toolSettings.copyWith(
                                  disabled: v
                                      ? (Set<String>.of(
                                          app.toolSettings.disabled,
                                        )..remove(tool.name))
                                      : {
                                          ...app.toolSettings.disabled,
                                          tool.name,
                                        },
                                ),
                              ),
                            ),
                    ),
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        '${tool.name}-${app.permissionGate.policy.overrides[tool.name]}',
                      ),
                      initialValue:
                          app
                              .permissionGate
                              .policy
                              .overrides[tool.name]
                              ?.name ??
                          'default',
                      isExpanded: true,
                      items: [
                        DropdownMenuItem(
                          value: 'default',
                          child: Text(l.defaultPolicy),
                        ),
                        DropdownMenuItem(
                          value: 'ask',
                          child: Text(l.alwaysAsk),
                        ),
                        DropdownMenuItem(
                          value: 'allow',
                          child: Text(l.alwaysAllow),
                        ),
                        DropdownMenuItem(value: 'deny', child: Text(l.deny)),
                      ],
                      onChanged: app.busy
                          ? null
                          : (value) => run(() async {
                              final overrides = {
                                ...app.permissionGate.policy.overrides,
                              };
                              if (value == 'default') {
                                overrides.remove(tool.name);
                              } else {
                                overrides[tool.name] = ToolPermission.values
                                    .byName(value!);
                              }
                              await app.savePermissionPolicy(
                                app.permissionGate.policy.copyWith(
                                  overrides: overrides,
                                ),
                              );
                            }),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _keywords,
            minLines: 3,
            maxLines: 8,
            decoration: InputDecoration(labelText: l.highRiskKeywords),
            onFieldSubmitted: (text) => run(
              () => app.savePermissionPolicy(
                app.permissionGate.policy.copyWith(
                  highRiskKeywords: text
                      .split('\n')
                      .map((v) => v.trim())
                      .where((v) => v.isNotEmpty)
                      .toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});
  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  late final _app = ref.read(appControllerProvider);
  late var _records = _app.audit.list();
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final busy = ref.watch(appControllerProvider.select((app) => app.busy));
    return Scaffold(
      appBar: AppBar(
        title: Text(l.auditLog),
        actions: [
          IconButton(
            tooltip: l.clearAudit,
            icon: const Icon(Icons.delete_outline),
            onPressed: busy
                ? null
                : () async {
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(l.clearAudit),
                        content: Text(l.clearAuditBody),
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
                    if (yes == true) {
                      await _app.audit.clear();
                      if (mounted) setState(() => _records = _app.audit.list());
                    }
                  },
          ),
        ],
      ),
      body: FutureBuilder(
        future: _records,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(
              child: snapshot.hasError
                  ? Text(l.operationFailed)
                  : const CircularProgressIndicator(),
            );
          }
          if (snapshot.data!.isEmpty) return Center(child: Text(l.noAudit));
          return ListView(
            children: [
              for (final row in snapshot.data!)
                ExpansionTile(
                  title: Text(toolLabel(row.toolName, l)),
                  subtitle: Text(
                    '${row.startedAt.toLocal()} · ${row.decision}',
                  ),
                  leading: Icon(
                    row.isError
                        ? Icons.error_outline
                        : Icons.check_circle_outline,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.arguments),
                          SelectableText(row.arguments),
                          const SizedBox(height: 12),
                          Text(l.result),
                          SelectableText(row.resultSummary),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
