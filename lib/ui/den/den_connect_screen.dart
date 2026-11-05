import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../core/den/den_client.dart';
import '../../l10n/gen/app_localizations.dart';
import '../brand/tako_mark.dart';

/// Signs this device in to a Den: by password, through a browser (which
/// also covers Google, Discord and other OAuth sign-in), or with a pairing
/// code made on the Den's web page.
class DenConnectScreen extends ConsumerStatefulWidget {
  const DenConnectScreen({super.key});

  @override
  ConsumerState<DenConnectScreen> createState() => _DenConnectScreenState();
}

enum _Mode { signIn, register, pairCode }

class _DenConnectScreenState extends ConsumerState<DenConnectScreen> {
  final _address = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _invite = TextEditingController();
  final _code = TextEditingController();
  Uri? _server;
  DenInfo? _info;
  _Mode _mode = _Mode.signIn;
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_address, _username, _password, _invite, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  String _message(Object error, AppLocalizations l) => switch (error) {
    DenException(code: 'unreachable', :final message) => l.denUnreachable(
      message,
    ),
    DenException(code: 'not_den') => l.denNotDen,
    DenException(code: 'invalid_login') => l.denInvalidLogin,
    DenException(code: 'invalid_code') => l.denInvalidCode,
    DenException(code: 'access_denied') => l.denSignInDenied,
    DenException(code: 'expired') => l.denSignInExpired,
    DenException(:final message) => message,
    _ => l.operationFailed,
  };

  Future<void> _run(Future<void> Function() action) async {
    final l = AppLocalizations.of(context);
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (e) {
      if (mounted) setState(() => _error = _message(e, l));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _probe() async {
    final l = AppLocalizations.of(context);
    final server = normalizeDenUrl(_address.text);
    if (server == null) {
      setState(() => _error = l.denInvalidAddress);
      return;
    }
    await _run(() async {
      final info = await ref.read(appControllerProvider).den.probe(server);
      setState(() {
        _server = server;
        _info = info;
        _mode = _Mode.signIn;
      });
    });
  }

  void _done() {
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    final name = ref.read(appControllerProvider).den.account?.serverName;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.denConnected(name ?? l.denTitle))));
    Navigator.pop(context);
  }

  Future<void> _signIn() => _run(() async {
    final den = ref.read(appControllerProvider).den;
    switch (_mode) {
      case _Mode.signIn:
        await den.signInWithPassword(
          _server!,
          _username.text.trim(),
          _password.text,
        );
      case _Mode.register:
        await den.register(
          _server!,
          _username.text.trim(),
          _password.text,
          inviteCode: _invite.text.trim(),
        );
      case _Mode.pairCode:
        await den.claimPairCode(_server!, _code.text.trim());
    }
    _done();
  });

  Future<void> _browser({String? oauthProviderId}) => _run(() async {
    final app = ref.read(appControllerProvider);
    final server = _server!;
    final login = await app.den.startBrowserSignIn(server);
    final url = app.den.browserUrl(login, oauthProviderId: oauthProviderId);
    await app.services.openLink(url);
    if (!mounted) return;
    final cancel = Completer<void>();
    final signedIn = app.den.finishBrowserSignIn(
      server,
      login,
      cancelled: cancel.future,
    );
    // Closing the dialog cancels; signing in (or failing) closes it.
    var dialogOpen = true;
    void closeDialog() {
      if (dialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    unawaited(
      signedIn.then((ok) {
        if (ok) closeDialog();
      }, onError: (_) => closeDialog()),
    );
    await showDialog<void>(
      context: context,
      builder: (context) {
        final l = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l.denSignInWithBrowser),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.denWaitingForBrowser(login.userCode)),
              const SizedBox(height: 16),
              SelectableText(
                login.userCode,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  letterSpacing: 4,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => unawaited(app.services.openLink(url)),
              child: Text(l.denOpenBrowserAgain),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
          ],
        );
      },
    );
    dialogOpen = false;
    if (!cancel.isCompleted) cancel.complete();
    if (await signedIn) _done();
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final info = _info;
    return Scaffold(
      appBar: AppBar(title: Text(l.denConnectTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: AutofillGroup(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: IconTheme.merge(
                      data: IconThemeData(
                        size: 36,
                        color: theme.colorScheme.primary,
                      ),
                      child: const TakoMark(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  l.denConnectIntro,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                ),
                const SizedBox(height: 24),
                if (info == null) ...[
                  TextField(
                    key: const ValueKey('den-address'),
                    controller: _address,
                    enabled: !_working,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _probe(),
                    decoration: InputDecoration(
                      labelText: l.denServerAddress,
                      hintText: l.denServerAddressHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _working ? null : _probe,
                    child: Text(l.denContinue),
                  ),
                  ..._feedback(theme),
                ] else
                  ..._signInOptions(info, l, theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Progress and the last error, near the top of the long sign-in list so
  /// they stay visible on a phone.
  List<Widget> _feedback(ThemeData theme) => [
    if (_working) ...[
      const SizedBox(height: 20),
      const LinearProgressIndicator(),
    ],
    if (_error case final error?) ...[
      const SizedBox(height: 16),
      Text(
        error,
        key: const ValueKey('den-error'),
        style: TextStyle(color: theme.colorScheme.error),
      ),
    ],
  ];

  List<Widget> _signInOptions(
    DenInfo info,
    AppLocalizations l,
    ThemeData theme,
  ) {
    final server = _server!;
    final canRegister = info.registration != 'closed';
    return [
      Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(Icons.cottage_outlined),
          title: Text(info.name),
          subtitle: Text(server.toString()),
          trailing: IconButton(
            tooltip: l.denServerAddress,
            icon: const Icon(Icons.edit_outlined),
            onPressed: _working
                ? null
                : () => setState(() {
                    _info = null;
                    _error = null;
                  }),
          ),
        ),
      ),
      ..._feedback(theme),
      const SizedBox(height: 20),
      if (info.setupRequired) ...[
        Text(l.denSetupRequired, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => unawaited(
            ref.read(appControllerProvider).services.openLink(server),
          ),
          icon: const Icon(Icons.open_in_browser),
          label: Text(l.denOpenWeb),
        ),
      ] else ...[
        if (_mode == _Mode.pairCode) ...[
          Text(l.denPairCodeHelp, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('den-code'),
            controller: _code,
            enabled: !_working,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (_) => _signIn(),
            decoration: InputDecoration(
              labelText: l.denPairCode,
              hintText: 'ABCD-EFGH',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _working ? null : _signIn,
            child: Text(l.denSignIn),
          ),
        ] else if (info.passwordLogin || _mode == _Mode.register) ...[
          TextField(
            key: const ValueKey('den-username'),
            controller: _username,
            enabled: !_working,
            autocorrect: false,
            autofillHints: [
              _mode == _Mode.register
                  ? AutofillHints.newUsername
                  : AutofillHints.username,
            ],
            decoration: InputDecoration(
              labelText: l.denUsername,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('den-password'),
            controller: _password,
            enabled: !_working,
            obscureText: true,
            autofillHints: [
              _mode == _Mode.register
                  ? AutofillHints.newPassword
                  : AutofillHints.password,
            ],
            onSubmitted: (_) => _signIn(),
            decoration: InputDecoration(
              labelText: l.denPassword,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_mode == _Mode.register && info.registration == 'invite') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _invite,
              enabled: !_working,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l.denInviteCode,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('den-sign-in'),
            onPressed: _working ? null : _signIn,
            child: Text(
              _mode == _Mode.register ? l.denCreateAccount : l.denSignIn,
            ),
          ),
        ],
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 12),
        for (final provider in info.oauth) ...[
          OutlinedButton.icon(
            onPressed: _working
                ? null
                : () => _browser(oauthProviderId: provider.id),
            icon: const Icon(Icons.login),
            label: Text(l.denContinueWith(provider.name)),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          key: const ValueKey('den-browser'),
          onPressed: _working ? null : _browser,
          icon: const Icon(Icons.open_in_browser),
          label: Text(l.denSignInWithBrowser),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            if (_mode != _Mode.signIn && info.passwordLogin)
              TextButton(
                onPressed: () => setState(() => _mode = _Mode.signIn),
                child: Text(l.denSignIn),
              ),
            if (_mode != _Mode.pairCode)
              TextButton(
                onPressed: () => setState(() => _mode = _Mode.pairCode),
                child: Text(l.denUsePairCode),
              ),
            if (canRegister && _mode != _Mode.register)
              TextButton(
                onPressed: () => setState(() => _mode = _Mode.register),
                child: Text(l.denCreateAccount),
              ),
          ],
        ),
      ],
    ];
  }
}
