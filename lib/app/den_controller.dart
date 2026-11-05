import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/widgets.dart';

import '../core/den/den_account.dart';
import '../core/den/den_client.dart';
import '../core/den/sync_engine.dart';
import '../core/providers/provider_config.dart';
import '../core/util/json.dart';
import '../data/sync_store.dart';
import 'app_controller.dart';

/// Signing in to a Den, the provider for its model gateway, and keeping the
/// app database in sync with the account. Runs only in the foreground engine.
final class DenController extends ChangeNotifier {
  DenController(
    this.app, {
    DenClient Function(Uri server, String? token)? clientFactory,
  }) : _clientFactory =
           clientFactory ??
           ((server, token) => DenClient(server, token: token));

  final AppController app;
  final DenClient Function(Uri server, String? token) _clientFactory;
  late final SyncStore store = SyncStore(app.database);

  DenAccount? account;
  SyncStatus status = const SyncStatus();
  SyncEngine? _engine;
  StreamSubscription<void>? _tableUpdates;
  AppLifecycleListener? _lifecycle;
  bool _wasGenerating = false;
  bool _disposed = false;

  bool get connected => account != null;

  static String get deviceName => 'Tako · ${_platform()}';

  static String _platform() => Platform.isIOS
      ? 'iOS'
      : Platform.isAndroid
      ? 'Android'
      : Platform.operatingSystem;

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  /// Resumes a saved session. Never throws: the app starts without Den when
  /// its settings or secure storage cannot be read.
  Future<void> initialize() async {
    try {
      final stored = DenAccount.fromJson(
        tryDecodeObject(
          await app.settings.getString(DenAccount.settingsKey) ?? '',
        ),
      );
      if (stored == null) return;
      final token = await app.services.readSecret(DenAccount.tokenKey);
      if (_disposed || token == null || token.isEmpty) return;
      account = stored;
      _start(token);
      _emit();
    } on Object {
      account = null;
    }
  }

  /// Runs [action] with a client of its own, closed afterwards.
  Future<T> _once<T>(
    Uri server,
    String? token,
    Future<T> Function(DenClient client) action,
  ) async {
    final client = _clientFactory(server, token);
    try {
      return await action(client);
    } finally {
      client.close();
    }
  }

  /// Reads a server's public information, to show its sign-in options.
  Future<DenInfo> probe(Uri server) =>
      _once(server, null, (client) => client.info());

  Future<void> signInWithPassword(
    Uri server,
    String username,
    String password,
  ) async => _complete(
    server,
    await _once(
      server,
      null,
      (client) => client.login(username, password, deviceName),
    ),
  );

  Future<void> register(
    Uri server,
    String username,
    String password, {
    String? inviteCode,
  }) async => _complete(
    server,
    await _once(
      server,
      null,
      (client) => client.register(
        username,
        password,
        deviceName,
        inviteCode: inviteCode,
      ),
    ),
  );

  Future<void> claimPairCode(Uri server, String code) async => _complete(
    server,
    await _once(
      server,
      null,
      (client) => client.claimPairCode(code, deviceName),
    ),
  );

  Future<DenDeviceLogin> startBrowserSignIn(Uri server) => _once(
    server,
    null,
    (client) => client.startDeviceLogin(deviceName, platform: _platform()),
  );

  /// The page to open for [login]: the server's confirmation page, or an
  /// OAuth provider's sign-in that continues to it.
  Uri browserUrl(DenDeviceLogin login, {String? oauthProviderId}) =>
      oauthProviderId == null
      ? login.verificationUrl
      : login.oauthStart(oauthProviderId);

  /// Polls until the user approves [login] in the browser. Returns false when
  /// [cancelled] completes first.
  Future<bool> finishBrowserSignIn(
    Uri server,
    DenDeviceLogin login, {
    required Future<void> cancelled,
  }) async {
    var stop = false;
    unawaited(cancelled.then((_) => stop = true));
    final deadline = DateTime.now().add(login.expiresIn);
    final session = await _once(server, null, (client) async {
      while (!stop && DateTime.now().isBefore(deadline)) {
        final waited = Completer<void>();
        final timer = Timer(login.interval, waited.complete);
        await Future.any([waited.future, cancelled]);
        timer.cancel();
        if (stop) return null;
        final session = await client.pollDeviceLogin(login.deviceCode);
        if (session != null) return session;
      }
      return null;
    });
    if (session != null) {
      await _complete(server, session);
      return true;
    }
    if (stop) return false;
    throw const DenException('expired', 'Sign-in timed out.');
  }

  Future<void> _complete(Uri server, DenSession session) async {
    final (info, models) = await _once(
      server,
      session.token,
      (client) async => (
        await client.info(),
        await client.models().catchError((_) => <String>[]),
      ),
    );
    // Signing in again replaces the old session and its token.
    if (connected) await signOut();
    await app.services.writeSecret(DenAccount.tokenKey, session.token);
    final signedIn = DenAccount(
      server: server,
      serverName: info.name,
      user: session.user,
      deviceId: session.deviceId,
    );
    await app.settings.setString(
      DenAccount.settingsKey,
      jsonEncode(signedIn.toJson()),
    );
    await _saveProvider(signedIn, session.token, models);
    // Everything already on this device joins the account.
    await store.enable();
    account = signedIn;
    _start(session.token);
    _emit();
  }

  Future<void> _saveProvider(
    DenAccount account,
    String token,
    List<String> models,
  ) async {
    final existing = app.providers
        .where((p) => p.id == DenAccount.providerId)
        .firstOrNull;
    final model = existing != null && models.contains(existing.model)
        ? existing.model
        : (models.firstOrNull ?? existing?.model ?? '');
    final config = ProviderConfig(
      id: DenAccount.providerId,
      displayName: account.serverName,
      apiType: ApiType.chatCompletions,
      // Keeps a sub-path, for a Den behind a reverse proxy at /den.
      baseUrl: account.server
          .replace(path: '${account.server.path}/v1')
          .toString(),
      model: model,
      // The gateway forwards to hosted models; never call it on-device.
      isLocal: false,
    );
    final first = app.providers.isEmpty;
    await app.saveProvider(config, key: token);
    if (first && model.isNotEmpty) {
      await app.selectProvider(DenAccount.providerId, model: model);
    }
  }

  void _start(String token) {
    final current = account!;
    final engine = _engine = SyncEngine(
      client: _clientFactory(current.server, token),
      ledger: store,
      deviceId: current.deviceId,
      onApplied: (result) => unawaited(app.reloadAfterSync(result)),
      onStatus: (next) {
        status = next;
        _emit();
      },
      onModelsChanged: () => unawaited(
        app.refreshProviderModels(providerId: DenAccount.providerId),
      ),
      onAccountChanged: () => unawaited(_refreshAccount()),
      onSignedOut: () => unawaited(_tokenRevoked()),
    );
    _tableUpdates ??= app.database
        .tableUpdates(
          TableUpdateQuery.onAllTables([
            app.database.conversationRecords,
            app.database.messageRecords,
            app.database.memories,
            app.database.settingRecords,
          ]),
        )
        .listen((_) => unawaited(_localChange()));
    _lifecycle ??= AppLifecycleListener(
      onResume: () {
        _engine?.startLive();
        _engine?.schedule(Duration.zero);
      },
      onHide: () => _engine?.stopLive(),
    );
    app.addListener(_watchGeneration);
    engine.startLive();
    unawaited(engine.sync());
  }

  /// Uploads soon after local edits, but not on every save of a reply that
  /// is still streaming: that waits until the reply ends.
  Future<void> _localChange() async {
    final engine = _engine;
    if (engine == null || app.isGenerating) return;
    if (await store.pendingCount() > 0) engine.schedule();
  }

  void _watchGeneration() {
    final generating = app.isGenerating;
    if (_wasGenerating && !generating) _engine?.schedule();
    _wasGenerating = generating;
  }

  Future<void> syncNow() async => _engine?.sync();

  Future<void> _refreshAccount() async {
    final current = account;
    final engine = _engine;
    if (current == null || engine == null) return;
    try {
      final me = await engine.client.me();
      account = current.copyWith(user: me.user);
      await app.settings.setString(
        DenAccount.settingsKey,
        jsonEncode(account!.toJson()),
      );
      _emit();
    } on Object {
      // Shown again on the next successful refresh.
    }
  }

  /// The token was revoked elsewhere (or the account disabled): stop syncing
  /// but keep the local data, as after signing out.
  Future<void> _tokenRevoked() async {
    if (!connected) return;
    await signOut(revoke: false);
  }

  /// Stops syncing and removes the Den provider. Chats and memories already
  /// on the device stay.
  Future<void> signOut({bool revoke = true}) async {
    final engine = _engine;
    _engine = null;
    engine?.dispose();
    app.removeListener(_watchGeneration);
    if (revoke) {
      try {
        await engine?.client.logout();
      } on Object {
        // Offline: the token can still be revoked from the Den's web page.
      }
    }
    engine?.client.close();
    await store.disable();
    await app.services.writeSecret(DenAccount.tokenKey, null);
    await app.settings.setString(DenAccount.settingsKey, null);
    if (app.providers.any((p) => p.id == DenAccount.providerId)) {
      await app.deleteProvider(DenAccount.providerId);
    }
    account = null;
    status = const SyncStatus();
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    _engine?.dispose();
    _engine?.client.close();
    unawaited(_tableUpdates?.cancel());
    _lifecycle?.dispose();
    app.removeListener(_watchGeneration);
    super.dispose();
  }
}
