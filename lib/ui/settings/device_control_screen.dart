import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../app/app_info.dart';
import '../../core/providers/cancel_token.dart';
import '../../core/screen/remote_screen.dart';
import '../../core/shell/shell_capability.dart';
import '../../l10n/gen/app_localizations.dart';
import 'ictrl_settings.dart';

/// Enables `allow-external-apps` so other apps may use RUN_COMMAND.
const termuxSetupCommand =
    'mkdir -p ~/.termux && echo "allow-external-apps = true" >> '
    '~/.termux/termux.properties && termux-reload-settings';

/// Setup for screen control, notification access and Termux. Each is turned
/// on by the user in Android; this screen explains and links to it.
class DeviceControlScreen extends ConsumerStatefulWidget {
  const DeviceControlScreen({super.key});
  @override
  ConsumerState<DeviceControlScreen> createState() =>
      _DeviceControlScreenState();
}

class _DeviceControlScreenState extends ConsumerState<DeviceControlScreen> {
  late final _app = ref.read(appControllerProvider);
  late final _timeout = TextEditingController(
    text: '${_app.controlSettings.shellTimeoutSeconds}',
  );
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_app.refreshDeviceControl());
  }

  @override
  void dispose() {
    _timeout.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    final l = AppLocalizations.of(context);
    try {
      await action();
    } catch (_) {
      if (mounted) _say(l.operationFailed);
    }
  }

  void _say(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _openScreenSettings() async {
    final l = AppLocalizations.of(context);
    final screen = _app.services.screen;
    if (!screen.enabled) {
      // Prominent disclosure before the system accessibility settings.
      final agreed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.screenControlDisclosureTitle),
          content: SingleChildScrollView(
            child: Text(l.screenControlDisclosure(kAppName)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              key: const ValueKey('screen-disclosure-continue'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.continueAction),
            ),
          ],
        ),
      );
      if (agreed != true) return;
    }
    await _run(screen.openSettings);
  }

  Future<void> _testShell() async {
    final l = AppLocalizations.of(context);
    setState(() => _testing = true);
    try {
      final result = await _app.services.shell.run(
        'echo ok',
        timeout: const Duration(seconds: 20),
        cancel: CancelToken(),
      );
      final output = result.stdout.trim().isEmpty
          ? '(${result.exitCode})'
          : result.stdout.trim();
      if (mounted) {
        _say(
          result.exitCode == 0
              ? l.shellTestPassed(output)
              : l.shellTestFailed('exit ${result.exitCode}'),
        );
      }
    } on ShellException catch (error) {
      if (mounted) _say(l.shellTestFailed(error.code));
    } catch (_) {
      if (mounted) _say(l.operationFailed);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _saveTimeout(String text) async {
    final seconds = int.tryParse(text.trim());
    if (seconds == null || seconds < 5 || seconds > 600) {
      _timeout.text = '${_app.controlSettings.shellTimeoutSeconds}';
      return;
    }
    await _run(
      () => _app.saveControlSettings(
        _app.controlSettings.copyWith(shellTimeoutSeconds: seconds),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider);
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final screen = app.services.screen;
    if (screen is RemoteScreen) {
      return Scaffold(
        appBar: AppBar(title: Text(l.deviceControl)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                IctrlSettings(screen: screen),
                SwitchListTile(
                  title: Text(l.screenshotsSetting),
                  subtitle: Text(l.screenshotsHelp),
                  value: app.controlSettings.screenshots,
                  onChanged: app.busy
                      ? null
                      : (value) => _run(
                          () => app.saveControlSettings(
                            app.controlSettings.copyWith(screenshots: value),
                          ),
                        ),
                ),
                SwitchListTile(
                  title: Text(l.deleteScreenshots),
                  subtitle: Text(l.deleteScreenshotsHelp),
                  value: app.controlSettings.deleteScreenshotsWithChat,
                  onChanged: app.busy
                      ? null
                      : (value) => _run(
                          () => app.saveControlSettings(
                            app.controlSettings.copyWith(
                              deleteScreenshotsWithChat: value,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final shell = app.services.shell;
    final notifications = app.services.notifications;
    Widget status(bool on) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          on ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 18,
          color: on ? theme.colorScheme.primary : theme.colorScheme.outline,
        ),
        const SizedBox(width: 6),
        Text(on ? l.statusOn : l.statusOff),
      ],
    );
    Widget section(String title, IconData icon, bool on, List<Widget> body) =>
        Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(title, style: theme.textTheme.titleMedium),
                    ),
                    status(on),
                  ],
                ),
                const SizedBox(height: 12),
                ...body,
              ],
            ),
          ),
        );
    Widget small(String text) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(text, style: theme.textTheme.bodySmall),
    );
    Widget step(int number, String text, [Widget? action]) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 12, child: Text('$number')),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(text), ?action],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l.deviceControl)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(l.deviceControlHelp(kAppName)),
              ),
              section(
                l.screenControl,
                Icons.touch_app_outlined,
                screen.isAvailable,
                screen.supported
                    ? [
                        Text(l.screenControlHelp(kAppName)),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          key: const ValueKey('device-control-accessibility'),
                          onPressed: _openScreenSettings,
                          child: Text(l.openAccessibilitySettings),
                        ),
                        small(l.restrictedSettingsHelp),
                        TextButton(
                          onPressed: () => _run(screen.openAppInfo),
                          child: Text(l.openAppInfo),
                        ),
                        const Divider(height: 24),
                        SwitchListTile(
                          key: const ValueKey('device-control-screenshots'),
                          contentPadding: EdgeInsets.zero,
                          title: Text(l.screenshotsSetting),
                          subtitle: Text(
                            screen.screenshotsSupported || !screen.enabled
                                ? l.screenshotsHelp
                                : l.screenshotsUnsupported,
                          ),
                          value: app.controlSettings.screenshots,
                          onChanged: app.busy
                              ? null
                              : (value) => _run(
                                  () => app.saveControlSettings(
                                    app.controlSettings.copyWith(
                                      screenshots: value,
                                    ),
                                  ),
                                ),
                        ),
                        SwitchListTile(
                          key: const ValueKey(
                            'device-control-delete-screenshots',
                          ),
                          contentPadding: EdgeInsets.zero,
                          title: Text(l.deleteScreenshots),
                          subtitle: Text(l.deleteScreenshotsHelp),
                          value: app.controlSettings.deleteScreenshotsWithChat,
                          onChanged: app.busy
                              ? null
                              : (value) => _run(
                                  () => app.saveControlSettings(
                                    app.controlSettings.copyWith(
                                      deleteScreenshotsWithChat: value,
                                    ),
                                  ),
                                ),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l.sessionNotification),
                          subtitle: Text(l.sessionNotificationHelp),
                          trailing: notifications.canPost
                              ? Text(l.allowed)
                              : TextButton(
                                  key: const ValueKey(
                                    'device-control-post-notifications',
                                  ),
                                  onPressed: () =>
                                      _run(notifications.requestPostPermission),
                                  child: Text(l.allowNotifications),
                                ),
                        ),
                      ]
                    : [Text(l.screenControlUnsupported)],
              ),
              section(
                l.notificationAccess,
                Icons.notifications_none,
                notifications.access,
                [
                  Text(l.notificationAccessHelp(kAppName)),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    key: const ValueKey('device-control-notification-access'),
                    onPressed: () => _run(notifications.openAccessSettings),
                    child: Text(l.openNotificationAccess),
                  ),
                  small(l.restrictedSettingsHelp),
                ],
              ),
              section(l.termux, Icons.terminal, shell.isAvailable, [
                Text(l.termuxHelp),
                if (!shell.installed) small(l.termuxNotInstalled),
                step(
                  1,
                  l.termuxStepOpen,
                  shell.installed
                      ? Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(
                            onPressed: () => _run(shell.openSetup),
                            child: Text(l.openTermux),
                          ),
                        )
                      : null,
                ),
                step(
                  2,
                  l.termuxStepProperty,
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: SelectableText(
                            termuxSetupCommand,
                            style: TextStyle(fontFamily: 'monospace'),
                          ),
                        ),
                        IconButton(
                          tooltip: l.copy,
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: () => _run(() async {
                            await app.services.copyText(termuxSetupCommand);
                            if (mounted) _say(l.copied);
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
                small(l.termuxSecurityNote),
                step(
                  3,
                  l.termuxStepPermission(kAppName),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: shell.permitted
                        ? Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(l.allowed),
                          )
                        : TextButton(
                            key: const ValueKey('device-control-termux-allow'),
                            onPressed: shell.installed
                                ? () => _run(shell.requestPermission)
                                : null,
                            child: Text(l.grantPermission),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton(
                      key: const ValueKey('device-control-termux-test'),
                      onPressed: shell.isAvailable && !_testing
                          ? _testShell
                          : null,
                      child: Text(l.testShell),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _timeout,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: l.shellTimeout),
                        onSubmitted: _saveTimeout,
                        onTapOutside: (_) => _saveTimeout(_timeout.text),
                      ),
                    ),
                  ],
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
