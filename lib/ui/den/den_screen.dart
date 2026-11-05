import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app_controller.dart';
import '../../l10n/gen/app_localizations.dart';

/// The Den this device is signed in to: account, sync status, sign-out.
class DenScreen extends ConsumerWidget {
  const DenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appControllerProvider);
    final den = app.den;
    final account = den.account;
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (account == null) {
      return Scaffold(appBar: AppBar(title: Text(l.denTitle)));
    }
    final status = den.status;
    final synced = status.lastSyncedAt;
    final statusText = status.syncing
        ? l.denSyncing
        : status.error != null
        ? l.denSyncFailed(status.error!)
        : synced == null
        ? l.denNeverSynced
        : l.denSyncedAt(DateFormat.Md(l.localeName).add_Hm().format(synced));

    Future<void> signOut() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.denSignOutTitle),
          content: Text(l.denSignOutBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.denSignOut),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await den.signOut();
      if (context.mounted) Navigator.pop(context);
    }

    return Scaffold(
      appBar: AppBar(title: Text(account.serverName)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              ListTile(
                leading: CircleAvatar(
                  child: Text(
                    account.user.label.characters.first.toUpperCase(),
                  ),
                ),
                title: Text(account.user.label),
                subtitle: Text(
                  [
                    '@${account.user.username}',
                    if (account.user.isAdmin) l.denRoleAdmin,
                    account.server.toString(),
                  ].join(' · '),
                ),
              ),
              const SizedBox(height: 16),
              Text(l.denSync, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            status.error != null
                                ? Icons.sync_problem_outlined
                                : Icons.cloud_done_outlined,
                            color: status.error != null
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              statusText,
                              key: const ValueKey('den-sync-status'),
                            ),
                          ),
                          if (status.live)
                            Chip(
                              label: Text(l.denLive),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      if (status.pending > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          l.denPendingChanges(status.pending),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                      if (status.syncing) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(),
                      ],
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonalIcon(
                          onPressed: status.syncing
                              ? null
                              : () => unawaited(den.syncNow()),
                          icon: const Icon(Icons.sync),
                          label: Text(l.denSyncNow),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(l.denSyncScope, style: theme.textTheme.bodySmall),
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(Icons.open_in_browser),
                title: Text(l.denOpenWeb),
                subtitle: Text(l.denOpenWebHelp),
                onTap: () => unawaited(app.services.openLink(account.server)),
              ),
              ListTile(
                key: const ValueKey('den-sign-out'),
                leading: Icon(Icons.logout, color: theme.colorScheme.error),
                title: Text(
                  l.denSignOut,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                onTap: () => unawaited(signOut()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
