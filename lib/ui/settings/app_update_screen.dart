import 'package:flutter/material.dart';

import '../../core/updates/app_update.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../platform/android/app_updater.dart';

class AppUpdateScreen extends StatefulWidget {
  const AppUpdateScreen({super.key});
  @override
  State<AppUpdateScreen> createState() => _AppUpdateScreenState();
}

class _AppUpdateScreenState extends State<AppUpdateScreen> {
  final _updater = AndroidAppUpdater();
  Map<Object?, Object?> _installed = {};
  AppUpdate? _update;
  bool _checking = false;
  bool _downloading = false;
  bool _available = false;
  double _progress = 0;
  String? _status;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _status = null;
      _update = null;
    });
    try {
      final installed = await _updater.installedInfo();
      final abis = (installed['abis'] as List<Object?>? ?? [])
          .whereType<String>()
          .toList();
      final update = await AppUpdateRepository().check(abis);
      if (!mounted) return;
      setState(() {
        _installed = installed;
        _update = update;
        _available = update.isNewerThan(
          installedCommit: installed['commit'] as String? ?? '',
          installedAt: DateTime.fromMillisecondsSinceEpoch(
            installed['installedAt'] as int? ?? 0,
            isUtc: true,
          ),
        );
        _status = _available ? 'updateAvailable' : 'updateCurrent';
      });
    } catch (_) {
      if (mounted) setState(() => _status = 'updateCheckFailed');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _install() async {
    final update = _update;
    if (update == null || _downloading) return;
    setState(() {
      _downloading = true;
      _progress = 0;
      _status = null;
    });
    try {
      if (!await _updater.prepareInstall()) {
        if (mounted) setState(() => _status = 'updateInstallPermission');
        return;
      }
      await _updater.downloadAndInstall(
        update,
        onProgress: (received, total) {
          if (mounted) setState(() => _progress = received / total);
        },
      );
      if (mounted) setState(() => _status = 'updateInstallerOpened');
    } catch (_) {
      if (mounted) setState(() => _status = 'updateInstallFailed');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final status = switch (_status) {
      'updateAvailable' => l.updateAvailable,
      'updateCurrent' => l.updateCurrent,
      'updateCheckFailed' => l.updateCheckFailed,
      'updateInstallPermission' => l.updateInstallPermission,
      'updateInstallerOpened' => l.updateInstallerOpened,
      'updateInstallFailed' => l.updateInstallFailed,
      _ => null,
    };
    return PopScope(
      canPop: !_downloading,
      child: Scaffold(
        appBar: AppBar(title: Text(l.appUpdates)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(l.appUpdatesHelp),
                const SizedBox(height: 20),
                if (_installed['version'] != null)
                  Text('${l.installedVersion}: ${_installed['version']}'),
                if (_update case final update?) ...[
                  const SizedBox(height: 12),
                  Text(
                    update.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    '${update.updatedAt.toLocal()} · ${(update.size / 1048576).toStringAsFixed(1)} MB',
                  ),
                  const SizedBox(height: 12),
                  SelectableText(update.notes),
                ],
                const SizedBox(height: 20),
                if (status != null) Text(status),
                if (_checking) const LinearProgressIndicator(),
                if (_downloading) ...[
                  LinearProgressIndicator(value: _progress),
                  Text('${(_progress * 100).round()}%'),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _checking || _downloading ? null : _check,
                      icon: const Icon(Icons.refresh),
                      label: Text(l.checkUpdates),
                    ),
                    if (_available && _update != null)
                      FilledButton.icon(
                        onPressed: _downloading || _checking ? null : _install,
                        icon: const Icon(Icons.system_update),
                        label: Text(l.downloadUpdate),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
