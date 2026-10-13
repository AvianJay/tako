import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../app/app_info.dart';
import '../../core/browser/browser_settings.dart';
import '../../core/providers/provider_config.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../platform/android/app_updater.dart';
import '../brand/tako_mark.dart';
import '../browser/browser_screen.dart';
import '../files/files_screen.dart';
import '../memory/memory_screen.dart';
import 'app_update_screen.dart';
import 'device_control_screen.dart';
import 'on_device_models_screen.dart';
import 'personalization_screen.dart';
import 'provider_editor.dart';
import 'search_settings_screen.dart';
import 'shortcuts_screen.dart';
import 'tool_settings_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appControllerProvider);
    final l = AppLocalizations.of(context);
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
      appBar: AppBar(title: Text(l.settings)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              ListTile(
                title: Text(l.toolsSettings),
                leading: const Icon(Icons.build_outlined),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(builder: (_) => const ToolSettingsScreen()),
                ),
              ),
              ListTile(
                title: Text(l.search),
                leading: const Icon(Icons.travel_explore),
                trailing: const Icon(Icons.chevron_right),
                onTap: app.busy
                    ? null
                    : () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SearchSettingsScreen(),
                        ),
                      ),
              ),
              ListTile(
                title: Text(l.files),
                leading: const Icon(Icons.folder_outlined),
                trailing: const Icon(Icons.chevron_right),
                onTap: app.busy
                    ? null
                    : () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(builder: (_) => const FilesScreen()),
                      ),
              ),
              ListTile(
                title: Text(l.memory),
                leading: const Icon(Icons.bookmarks_outlined),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(builder: (_) => const MemoryScreen()),
                ),
              ),
              ListTile(
                title: Text(l.personalization),
                leading: const Icon(Icons.person_outline),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PersonalizationScreen(),
                  ),
                ),
              ),
              if (app.services.onDevice.isAvailable)
                ListTile(
                  key: const ValueKey('settings-on-device'),
                  title: Text(l.onDeviceModels),
                  subtitle: Text(l.onDeviceModelsHelp),
                  leading: const Icon(Icons.memory),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OnDeviceModelsScreen(),
                    ),
                  ),
                ),
              if (app.services.shortcuts.isAvailable)
                ListTile(
                  key: const ValueKey('settings-shortcuts'),
                  title: Text(l.shortcuts),
                  subtitle: Text(l.shortcutsHelp),
                  leading: const Icon(Icons.bolt_outlined),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(builder: (_) => const ShortcutsScreen()),
                  ),
                ),
              if (app.services.isAvailable)
                ListTile(
                  key: const ValueKey('settings-device-control'),
                  title: Text(l.deviceControl),
                  leading: const Icon(Icons.touch_app_outlined),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DeviceControlScreen(),
                    ),
                  ),
                ),
              if (app.services.browser.isAvailable) ...[
                ListTile(
                  title: Text(l.browser),
                  leading: const Icon(Icons.public),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => openBrowserScreen(context, app),
                ),
                SwitchListTile(
                  secondary: const SizedBox(width: 24),
                  title: Text(l.openLinksInApp),
                  subtitle: Text(l.openLinksInAppHelp),
                  value: app.browserSettings.openLinksInApp,
                  onChanged: app.busy
                      ? null
                      : (value) => run(
                          () => app.saveBrowserSettings(
                            BrowserSettings(openLinksInApp: value),
                          ),
                        ),
                ),
              ],
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.providers,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: l.addProvider,
                    onPressed: app.busy
                        ? null
                        : () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ProviderEditor(),
                            ),
                          ),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              if (app.providers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(l.setupBody),
                ),
              for (final p in app.providers)
                Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
                    leading: Icon(providerIcon(p)),
                    title: Text(p.displayName),
                    subtitle: Text(
                      '${p.models.map((model) => model.displayName).take(4).join(', ')}${p.models.length > 4 ? ' … (${p.models.length})' : ''}\n'
                      '${p.apiType == ApiType.onDevice ? l.onDeviceApi : p.baseUrl}',
                    ),
                    isThreeLine: true,
                    onTap: app.busy
                        ? null
                        : () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProviderEditor(provider: p),
                            ),
                          ),
                    trailing: IconButton(
                      tooltip: l.delete,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: app.busy
                          ? null
                          : () async {
                              final yes = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text(l.delete),
                                  content: Text(l.providerDeleteBody),
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
                                await run(() => app.deleteProvider(p.id));
                              }
                            },
                    ),
                  ),
                ),
              const SizedBox(height: 28),
              Text(l.appearance, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              DropdownButtonFormField<ThemeMode>(
                initialValue: app.themeMode,
                decoration: InputDecoration(labelText: l.theme),
                items: [
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text(l.systemTheme),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child: Text(l.lightTheme),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.dark,
                    child: Text(l.darkTheme),
                  ),
                ],
                onChanged: (v) => run(() => app.updateAppearance(theme: v)),
              ),
              const SizedBox(height: 20),
              Text(l.textSize),
              Slider(
                value: app.textScale,
                min: .85,
                max: 1.4,
                divisions: 11,
                label: '${(app.textScale * 100).round()}%',
                onChanged: (v) => run(() => app.updateAppearance(scale: v)),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: app.locale.languageCode,
                decoration: InputDecoration(labelText: l.language),
                items: const [
                  DropdownMenuItem(value: 'zh', child: Text('繁體中文')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                ],
                onChanged: (v) => run(
                  () => app.updateAppearance(
                    language: v == 'en'
                        ? const Locale('en')
                        : const Locale('zh', 'TW'),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.shield_outlined),
                          const SizedBox(width: 10),
                          Text(
                            l.privacy,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(l.privacyBody),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (AndroidAppUpdater.isAvailable)
                ListTile(
                  key: const ValueKey('settings-app-updates'),
                  title: Text(l.appUpdates),
                  subtitle: Text(l.appUpdatesHelp),
                  leading: const Icon(Icons.system_update),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(builder: (_) => const AppUpdateScreen()),
                  ),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(kAppName),
                subtitle: Text(l.appTagline),
                leading: const TakoMark(),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
