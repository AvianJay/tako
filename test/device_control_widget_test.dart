import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/app/app.dart';
import 'package:tako/app/app_controller.dart';
import 'package:tako/core/notifications/notification_capability.dart';
import 'package:tako/core/permissions/permission_gate.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/core/screen/screen_capability.dart';
import 'package:tako/core/shell/shell_capability.dart';
import 'package:tako/core/tools/screen_tools.dart';
import 'package:tako/core/tools/tool_settings.dart';
import 'package:tako/data/database.dart';
import 'package:tako/l10n/gen/app_localizations.dart';
import 'package:tako/platform/services.dart';
import 'package:tako/ui/settings/device_control_screen.dart';
import 'package:tako/ui/settings/remote_agent_settings.dart';
import 'package:tako/ui/settings/tool_settings_screen.dart';

import 'screen/fake_screen.dart';

class _Notifications extends UnavailableNotifications {
  final log = <String>[];
  final sessionBodies = <String>[];
  bool posting = false;
  int accessSettings = 0;
  @override
  bool get canPost => posting;
  @override
  Future<void> openAccessSettings() async => accessSettings++;
  @override
  Future<bool> requestPostPermission() async {
    posting = true;
    notifyListeners();
    return true;
  }

  @override
  Future<void> showSession({
    required String title,
    required String body,
    required String stop,
    required String channel,
  }) async {
    log.add('session: $title / $stop');
    sessionBodies.add(body);
  }

  @override
  Future<void> clearSession() async => log.add('session cleared');
  @override
  Future<void> showAlert(
    String kind, {
    required String title,
    required String body,
    required String channel,
  }) async => log.add('$kind: $title');
  @override
  Future<void> cancelAlert(String kind) async => log.add('$kind cleared');
}

class _Shell extends ShellCapability {
  void changed() => notifyListeners();
  @override
  bool installed = false;
  @override
  bool permitted = false;
  final commands = <String>[];
  @override
  String get environment => 'Termux on this phone';
  @override
  Future<void> refresh() async {}
  @override
  Future<bool> openSetup() async => true;
  @override
  Future<bool> requestPermission() async {
    permitted = true;
    notifyListeners();
    return true;
  }

  @override
  Future<ShellResult> run(
    String command, {
    required Duration timeout,
    required CancelToken cancel,
  }) async {
    commands.add(command);
    return const ShellResult(exitCode: 0, stdout: 'ok\n');
  }
}

class _Screen extends FakeScreen {
  _Screen() : super(phoneScreen().views, start: 'settings');
  int settingsOpened = 0;
  @override
  Future<void> openSettings() async => settingsOpened++;
}

class _Services extends PlatformServices {
  _Services(this._screen, this._notifications, this._shell);
  final ScreenCapability _screen;
  final NotificationCapability _notifications;
  final ShellCapability _shell;
  @override
  ScreenCapability get screen => _screen;
  @override
  NotificationCapability get notifications => _notifications;
  @override
  ShellCapability get shell => _shell;
  @override
  bool get isAvailable => true;
  @override
  Future<DeviceContext> deviceContext() async =>
      const DeviceContext(osVersion: 'test', model: 'test device');
  @override
  Future<String?> readSecret(String reference) async => null;
  @override
  Future<void> writeSecret(String reference, String? value) async {}
}

class _Adapter implements ProviderAdapter {
  _Adapter(this.turns, {this.waitAtEnd = false});
  final List<List<ProviderEvent>> turns;
  final bool waitAtEnd;
  int calls = 0;
  @override
  Future<List<ModelInfo>> listModels({CancelToken? cancel}) async => [];
  @override
  Stream<ProviderEvent> send(
    ChatRequest request, {
    required CancelToken cancel,
  }) async* {
    final index = calls++;
    if (index >= turns.length) {
      if (waitAtEnd) {
        await cancel.whenCancelled;
        return;
      }
      yield const TextDelta('Done.');
      yield const Done('stop');
      return;
    }
    for (final event in turns[index]) {
      if (cancel.isCancelled) return;
      yield event;
    }
  }
}

List<ProviderEvent> _call(
  String id,
  String name,
  Map<String, Object?> args,
) => [
  ToolCallStart(id, name),
  ToolCallArgsDelta(
    id,
    jsonEncode({
      if (screenToolNames.contains(name) || name == 'open_app') 'title': name,
      ...args,
    }),
  ),
  ToolCallEnd(id),
  const Done('tool_calls'),
];

Future<AppController> _boot(
  WidgetTester tester, {
  required _Screen screen,
  required _Notifications notifications,
  _Shell? shell,
  ProviderAdapter? adapter,
  Widget? home,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final database = AppDatabase(NativeDatabase.memory());
  final controller = AppController(
    database: database,
    services: _Services(screen, notifications, shell ?? _Shell()),
    promptTemplate: 'You are {{app_name}}.',
    adapterFactory: adapter == null ? null : (_, key, headers) => adapter,
  );
  await tester.runAsync(() async {
    await controller.initialize();
    await controller.updateAppearance(language: const Locale('en'));
    await controller.saveProvider(
      ProviderConfig(
        id: 'local',
        displayName: 'Local model',
        apiType: ApiType.chatCompletions,
        baseUrl: 'http://127.0.0.1:8080',
        model: 'llama-server',
        capabilities: ProviderCapabilities(tools: true, contextWindow: 32000),
        maxOutputTokens: 256,
      ),
    );
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appControllerProvider.overrideWith((ref) => controller)],
      child: home == null
          ? const TakoApp()
          : MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: home,
            ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });
  return controller;
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 250 && !ready(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(ready(), isTrue);
  await tester.pump();
}

/// The user switches to another app, or back, through valid transitions.
void _hide(WidgetTester tester) {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void _show(WidgetTester tester) {
  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void main() {
  testWidgets(
    'worker selector fits narrow Traditional Chinese screen and saves independently',
    (tester) async {
      final app = await _boot(
        tester,
        screen: _Screen(),
        notifications: _Notifications(),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: RemoteAgentSettings(),
            ),
          ),
        ),
      );
      final mainId = app.selectedProvider!.id;
      await tester.runAsync(
        () => app.updateAppearance(language: const Locale('zh', 'TW')),
      );
      tester.view.physicalSize = const Size(320, 844);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith((ref) => app)],
          child: MaterialApp(
            locale: const Locale('zh', 'TW'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.3)),
              child: child!,
            ),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: RemoteAgentSettings(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('委派手機操作'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final dropdown = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.key.toString().contains('remote-agent-provider'),
      );
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Local model').last);
      await tester.pumpAndSettle();
      expect(app.controlSettings.remoteAgentProviderId, 'local');
      expect(app.remoteAgentProvider?.model, 'llama-server');
      expect(app.selectedProvider!.id, mainId);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'approvals needed while hidden are drawn over other apps, with Stop',
    (tester) async {
      final screen = _Screen();
      final notifications = _Notifications();
      final app = await _boot(
        tester,
        screen: screen,
        notifications: notifications,
        adapter: _Adapter([
          _call('read', 'read_screen', {}),
          _call('tap', 'tap', {'id': 4}),
        ]),
      );
      var done = false;
      unawaited(app.send('Open About phone').whenComplete(() => done = true));
      // The user is in another app while the model works.
      _hide(tester);
      await _waitFor(tester, () => screen.approvals.length == 1);
      final reading = screen.approvals.single;
      expect(reading.title, 'Tool approval');
      expect(reading.subtitle, 'Read screen · Reads private data');
      expect(reading.choices.map((choice) => choice.$2), [
        'Allow once',
        'Allow in this chat',
        'Always allow this tool',
        'Deny',
      ]);
      expect(reading.denyId, 'deny');
      screen.answerApproval('allowInChat');

      await _waitFor(tester, () => screen.approvals.length == 2);
      final tap = screen.approvals.last;
      expect(tap.subtitle, startsWith('Tap on screen'));
      expect(tap.details, [
        ('Element', 'Button “About phone Pixel fixture”'),
        ('App', 'Settings'),
      ]);
      expect(tap.highlight, isNotNull);
      expect(
        notifications.log,
        contains('session: Tako is using your phone / Stop'),
      );
      screen.answerApproval('allowInChat');
      await _waitFor(tester, () => done);
      expect(screen.current, 'settings/about');
      expect(notifications.log, contains('session cleared'));
      expect(notifications.log, contains('reply: Tako replied'));

      // Back in the app, the reply notification is withdrawn.
      _show(tester);
      await tester.pump();
      expect(notifications.log.last, 'reply cleared');
    },
  );

  testWidgets(
    'without screen control, a hidden approval posts a notification instead',
    (tester) async {
      final screen = _Screen()..enabledValue = false;
      final notifications = _Notifications();
      final shell = _Shell()
        ..installed = true
        ..permitted = true;
      final app = await _boot(
        tester,
        screen: screen,
        notifications: notifications,
        shell: shell,
        adapter: _Adapter([
          _call('shell', 'run_shell', {'command': 'pkg upgrade'}),
        ]),
      );
      var done = false;
      unawaited(app.send('Update packages').whenComplete(() => done = true));
      _hide(tester);
      await _waitFor(
        tester,
        () => notifications.log.contains('approval: Tako needs your approval'),
      );
      expect(screen.approvals, isEmpty);
      // Opening the app shows the usual sheet and withdraws the notice.
      _show(tester);
      await _waitFor(tester, () => find.text('Deny').evaluate().isNotEmpty);
      expect(notifications.log, contains('approval cleared'));
      expect(find.text('Run shell command · High-risk action'), findsOneWidget);
      await tester.tap(find.text('Deny'));
      await _waitFor(tester, () => done);
      expect(shell.commands, isEmpty);
    },
  );

  testWidgets(
    'phone status follows titles and thinking, survives foreground changes, and Stop clears immediately',
    (tester) async {
      final screen = _Screen();
      final notifications = _Notifications();
      final app = await _boot(
        tester,
        screen: screen,
        notifications: notifications,
        adapter: _Adapter([
          _call('read', 'read_screen', {'title': 'Check Wi-Fi status'}),
        ], waitAtEnd: true),
      );
      var done = false;
      unawaited(app.send('Check Wi-Fi').whenComplete(() => done = true));
      _hide(tester);
      await _waitFor(tester, () => screen.approvals.isNotEmpty);
      screen.answerApproval('allowInChat');
      await _waitFor(
        tester,
        () => screen.controlOverlays.any(
          (overlay) => overlay.phase == ScreenSessionPhase.thinking,
        ),
      );
      expect(
        screen.controlOverlays.map((overlay) => overlay.title),
        contains('Check Wi-Fi status'),
      );
      expect(notifications.sessionBodies, contains('Check Wi-Fi status'));
      expect(
        screen.controlOverlays.last.title,
        'Thinking about the next step…',
      );
      final sessionId = screen.controlOverlays.last.sessionId;
      _show(tester);
      await tester.pump();
      expect(screen.hiddenControlSessions.last, (sessionId, false));
      expect(screen.modelActive, isTrue);
      _hide(tester);
      await tester.pump();
      expect(screen.controlOverlays.last.sessionId, sessionId);
      app.stop();
      expect(screen.modelActive, isFalse);
      expect(screen.hiddenControlSessions.last, (sessionId, true));
      await _waitFor(tester, () => done);
    },
  );

  testWidgets('at the tool-call limit, Continue goes on', (tester) async {
    final adapter = _Adapter([_call('read', 'read_screen', {})]);
    final app = await _boot(
      tester,
      screen: _Screen(),
      notifications: _Notifications(),
      adapter: adapter,
    );
    await tester.runAsync(() async {
      await app.saveToolSettings(
        const ToolSettings(maxSteps: 1, maxScreenSteps: 1),
      );
      await app.savePermissionPolicy(
        const PermissionPolicy(fullPermissions: true),
      );
    });
    var done = false;
    unawaited(app.send('What is on screen?').whenComplete(() => done = true));
    await _waitFor(tester, () => done);
    expect(
      find.text(
        'Tool-call limit reached. Review the results, then press Continue if needed.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('continue-tools')));
    await _waitFor(tester, () => adapter.calls == 2 && !app.busy);
    expect(app.errorCode, isNull);
    expect(app.visibleMessages.last.text, 'Done.');
    expect(find.byKey(const Key('continue-tools')), findsNothing);
  });

  testWidgets('tool settings set the limit for screen control', (tester) async {
    final app = await _boot(
      tester,
      screen: _Screen(),
      notifications: _Notifications(),
    );
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    unawaited(
      nav.push<void>(
        MaterialPageRoute(builder: (_) => const ToolSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('max-screen-steps'));
    expect(
      find.descendant(
        of: field,
        matching: find.text(
          'Maximum tool calls per turn when controlling the screen',
        ),
      ),
      findsOneWidget,
    );
    expect(app.toolSettings.maxScreenSteps, 50);
    // Out of range: nothing is saved.
    await tester.enterText(field, '500');
    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(app.toolSettings.maxScreenSteps, 50);
    await tester.enterText(field, '80');
    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(app.toolSettings.maxScreenSteps, 80);
    expect(find.byType(ToolSettingsScreen), findsNothing);
  });

  testWidgets('device control setup links to system settings', (tester) async {
    final screen = _Screen()..enabledValue = false;
    final notifications = _Notifications();
    final shell = _Shell();
    await _boot(
      tester,
      screen: screen,
      notifications: notifications,
      shell: shell,
      home: const DeviceControlScreen(),
    );
    expect(find.text('Device control'), findsOneWidget);
    // The page list, not the selectable command inside it.
    final list = find.byType(Scrollable).first;
    // A disclosure comes before the system accessibility settings.
    await tester.tap(
      find.byKey(const ValueKey('device-control-accessibility')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Turn on screen control?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('screen-disclosure-continue')));
    await tester.pumpAndSettle();
    expect(screen.settingsOpened, 1);

    await tester.ensureVisible(
      find.byKey(const ValueKey('device-control-post-notifications')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('device-control-post-notifications')),
    );
    await tester.pumpAndSettle();
    expect(notifications.canPost, isTrue);
    await tester.scrollUntilVisible(
      find.text('Allowed'),
      -200,
      scrollable: list,
    );
    expect(find.text('Allowed'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('device-control-notification-access')),
      200,
      scrollable: list,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('device-control-notification-access')),
    );
    expect(notifications.accessSettings, 1);

    // Termux: not installed, so nothing can be granted or tested yet.
    await tester.scrollUntilVisible(
      find.text(termuxSetupCommand),
      200,
      scrollable: list,
    );
    expect(
      find.text(
        'Termux is not installed. Install it from F-Droid or its GitHub releases.',
      ),
      findsOneWidget,
    );
    shell.installed = true;
    shell.changed();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('device-control-termux-test')),
      200,
      scrollable: list,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('device-control-termux-allow')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('device-control-termux-allow')));
    await tester.pumpAndSettle();
    expect(shell.permitted, isTrue);
    await tester.tap(find.byKey(const ValueKey('device-control-termux-test')));
    await tester.pumpAndSettle();
    expect(shell.commands, ['echo ok']);
    expect(find.text('Termux replied: ok'), findsOneWidget);
  });
}
