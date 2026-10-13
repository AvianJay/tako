// On-device checks of device control with a scripted model: no provider and
// no network. See "On-device tests" in README.md for preparing the device
// and running this file. Two steps need a person: press Stop in the
// "Tako is controlling the screen" notification, and press Deny in the
// prompt drawn over Settings for Uninstall.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tako/app/app.dart';
import 'package:tako/app/app_controller.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/permissions/permission_gate.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/core/screen/device_control_settings.dart';
import 'package:tako/core/tools/screen_tools.dart';
import 'package:tako/data/database.dart';
import 'package:tako/platform/services.dart';
import 'package:tako/ui/browser/browser_screen.dart';

/// The Settings app's label on the test device.
const _settings = String.fromEnvironment('SETTINGS_APP', defaultValue: '設定');

typedef _Next = List<ProviderEvent>? Function(ChatRequest request);

/// A model that decides each step from the latest tool result.
class _Script implements ProviderAdapter {
  _Script(this.next);
  final _Next next;
  @override
  Future<List<ModelInfo>> listModels({CancelToken? cancel}) async => [];
  @override
  Stream<ProviderEvent> send(
    ChatRequest request, {
    required CancelToken cancel,
  }) async* {
    final events =
        next(request) ?? [const TextDelta('Done.'), const Done('stop')];
    // An empty step keeps "thinking" until the user stops the response.
    if (events.isEmpty) await cancel.whenCancelled;
    for (final event in events) {
      if (cancel.isCancelled) return;
      yield event;
    }
  }
}

String _last(ChatRequest request) {
  final results = request.messages
      .expand((message) => message.content)
      .whereType<ToolResultBlock>();
  return results.isEmpty ? '' : results.last.content;
}

/// The id of the first element whose label matches [pattern].
int? _id(String reading, Pattern pattern) {
  for (final line in reading.split('\n')) {
    final match = RegExp(r'^\[(\d+)\] \w+ "([^"]*)"').firstMatch(line);
    if (match != null && match.group(2)!.contains(pattern)) {
      return int.parse(match.group(1)!);
    }
  }
  return null;
}

var _calls = 0;
List<ProviderEvent> _call(String name, Map<String, Object?> args) {
  final id = 'call_${_calls++}';
  return [
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
}

List<ProviderEvent> _say(String text) => [TextDelta(text), const Done('stop')];

/// What an action's result says before the screen after it.
const _screenAfter = 'screen after the action:';

/// Opens [app], then taps elements matching [path] in turn (scrolling when
/// one is not on screen), reading the screen after a step that did not
/// return it; [then] takes over once the last screen was seen.
_Next _navigate(String app, List<Pattern> path, _Next then) {
  var step = -1;
  var read = false;
  var scrolls = 0;
  var tapped = false;
  return (request) {
    // A tap that failed (e.g. the screen changed) is tried again.
    final status = _last(request).split('\n').first;
    if (tapped && read && status.contains('"error"')) step--;
    tapped = false;
    if (step < 0) {
      step = 0;
      read = true;
      return _call('open_app', {'name': app});
    }
    if (read) {
      read = false;
      if (!_last(request).contains(_screenAfter)) {
        return _call('read_screen', {});
      }
    }
    if (step >= path.length) return then(request);
    final last = _last(request);
    final id = _id(last, path[step]);
    read = true;
    if (id == null) {
      if (scrolls++ >= 6) return _say('Not found: ${path[step]}');
      return _call('scroll', {'direction': 'down'});
    }
    step++;
    scrolls = 0;
    tapped = true;
    return _call('tap', {'id': id});
  };
}

Future<AppController> _start(
  WidgetTester tester,
  _Script script, {
  bool vision = false,
}) async {
  final services = PlatformServices();
  final database = AppDatabase(NativeDatabase.memory());
  final app = AppController(
    titleGenerator: (_, _, _) async => null,
    database: database,
    services: services,
    promptTemplate: await rootBundle.loadString(
      'assets/prompts/system_prompt.md',
    ),
    adapterFactory: (_, key, headers) => script,
  );
  addTearDown(() async {
    // Unmounting the scope disposes the controller.
    await tester.pumpWidget(const SizedBox.shrink());
    await database.close();
  });
  await app.initialize();
  await app.saveProvider(
    ProviderConfig(
      id: 'script',
      displayName: 'Scripted model',
      apiType: ApiType.chatCompletions,
      baseUrl: 'https://fixture.example.com/v1',
      model: 'script',
      capabilities: ProviderCapabilities(
        tools: true,
        vision: vision,
        contextWindow: 64000,
      ),
      maxOutputTokens: 256,
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appControllerProvider.overrideWith((ref) => app)],
      child: const TakoApp(),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  await app.refreshDeviceControl();
  return app;
}

/// Approves requests as they come, except where [manual] leaves the answer
/// to the tester (in the prompt drawn over other apps).
List<PermissionRequest> _approve(
  AppController app, {
  bool Function(PermissionRequest request)? manual,
}) {
  final seen = <PermissionRequest>[];
  app.addListener(() {
    final pending = app.pendingApproval;
    if (pending == null || seen.any((r) => identical(r, pending))) return;
    seen.add(pending);
    debugPrint(
      'APPROVAL ${pending.toolName} ${pending.risk.name} ${pending.details}',
    );
    if (manual?.call(pending) ?? false) return;
    final choice = pending.choices.contains(PermissionChoice.allowInChat)
        ? PermissionChoice.allowInChat
        : PermissionChoice.allowOnce;
    // Let the over-app prompt appear first, as a user would see it.
    Timer(
      const Duration(milliseconds: 800),
      () => app.permissionGate.decide(choice),
    );
  });
  return seen;
}

List<ToolResultBlock> _results(AppController app) => [
  for (final message in app.visibleMessages)
    if (message.role == MessageRole.tool)
      ...message.content.whereType<ToolResultBlock>(),
];

void _log(AppController app) {
  for (final result in _results(app)) {
    debugPrint('RESULT ${result.toolName}: ${result.content}');
  }
  debugPrint('ANSWER ${app.visibleMessages.last.text}');
}

/// Brings Tako back to the front: hidden, it draws no frames, and the test
/// cannot tear its widgets down.
Future<void> _returnToApp(WidgetTester tester, AppController app) async {
  await app.services.deviceTools.invoke('open_app', {
    'package': 'tw.avianjay.tako',
  }, cancel: CancelToken());
  for (var i = 0; i < 50 && !app.appInForeground; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opens Settings, goes three screens deep and reads back', (
    tester,
  ) async {
    final script = _Script(
      _navigate(_settings, [RegExp('^系統|^System'), RegExp('^日期和時間|^Date')], (
        request,
      ) {
        final zone = RegExp(
          r'GMT[+-]\d\d:\d\d[^"]*',
        ).firstMatch(_last(request));
        return _say('Time zone: ${zone?.group(0)}');
      }),
    );
    final app = await _start(tester, script, vision: true);
    expect(
      app.services.screen.isAvailable,
      isTrue,
      reason: 'Enable the accessibility service first.',
    );
    // A vision model with screenshots on: read_screen also attaches one.
    await app.saveControlSettings(
      const DeviceControlSettings(screenshots: true),
    );
    final requests = _approve(app);
    await app.send('Open Settings and tell me the time zone.');
    await _returnToApp(tester, app);
    _log(app);
    expect(app.errorCode, isNull);
    expect(_results(app).where((result) => result.isError), isEmpty);
    expect(app.visibleMessages.last.text, startsWith('Time zone: GMT'));
    expect(
      requests.map((request) => request.toolName).toSet(),
      containsAll(['open_app', 'read_screen', 'tap']),
    );
    final reads = _results(
      app,
    ).where((result) => result.toolName == 'read_screen');
    expect(reads.first.content, contains('screenshot: attached'));
    expect(reads.first.attachments.single, isA<ImageBlock>());
    // Once reading was allowed for the chat, taps returned the screen.
    final seen = _results(app).where(
      (result) =>
          result.toolName == 'tap' && result.content.contains(_screenAfter),
    );
    debugPrint('READS ${reads.length}, TAPS WITH SCREEN ${seen.length}');
    expect(seen, isNotEmpty);
    expect(seen.last.attachments.single, isA<ImageBlock>());
    expect(
      app.conversation!.systemPrompt,
      contains('and includes a screenshot'),
    );
  });

  testWidgets('Stop in the notification ends a response that uses the screen', (
    tester,
  ) async {
    var turn = 0;
    final script = _Script((request) {
      switch (turn++) {
        case 0:
          return _call('open_app', {'name': _settings});
        case 1:
          return _call('read_screen', {});
      }
      // Keep "thinking" until the tester presses Stop in the notification.
      return [];
    });
    final app = await _start(tester, script);
    _approve(app);
    debugPrint('WAITING FOR STOP: press Stop in the Tako notification');
    await app.send('Look at Settings.').timeout(const Duration(minutes: 4));
    await _returnToApp(tester, app);
    debugPrint('STATUS ${app.visibleMessages.last.status.name}');
    expect(app.visibleMessages.last.status, MessageStatus.stopped);
    expect(app.services.screen.modelActive, isFalse);
  });

  testWidgets('Uninstall asks over Settings at high risk', (tester) async {
    var phase = 0;
    final script = _Script(
      _navigate(_settings, [RegExp('^應用程式和通知|^Apps'), RegExp('^Termux')], (
        request,
      ) {
        final last = _last(request);
        switch (phase++) {
          case 0:
            final id = _id(last, RegExp('^解除安裝|^Uninstall'));
            return id == null
                ? _say('No uninstall button.')
                : _call('tap', {'id': id});
          case 1:
            return _call('press_key', {'key': 'home'});
        }
        return _say(last);
      }),
    );
    final app = await _start(tester, script);
    final requests = _approve(
      app,
      manual: (request) => request.risk == RiskLevel.high,
    );
    await app.send('Uninstall Termux.').timeout(const Duration(minutes: 4));
    await _returnToApp(tester, app);
    _log(app);
    final uninstall = requests.firstWhere(
      (request) => request.toolName == 'tap' && request.risk == RiskLevel.high,
    );
    expect(uninstall.details['app'], isNotEmpty);
    final tapped = _results(
      app,
    ).where((result) => result.toolName == 'tap').last;
    // The tester denies it in the prompt drawn over Settings.
    expect(tapped.content, contains('denied_by_user'));
  });

  testWidgets('the model browses in its own tab and the screen closes after', (
    tester,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8765);
    addTearDown(server.close);
    server.listen((request) {
      final model = request.uri.path == '/model';
      request.response
        ..headers.contentType = ContentType.html
        ..write(
          '<html><head><title>${model ? 'Model page' : 'User page'}</title>'
          '</head><body><main><p>${model ? 'Tea costs 12 USD.' : 'Reading'}'
          '</p><button>Buy</button></main></body></html>',
        )
        ..close();
    });
    var turn = 0;
    final script = _Script((request) {
      switch (turn++) {
        case 0:
          return _call('browser_open', {'url': 'http://127.0.0.1:8765/model'});
        case 1:
          return _call('browser_read', {});
      }
      final price = RegExp(r'\d+ USD').firstMatch(_last(request))?.group(0);
      return _say('Tea costs $price.');
    });
    final app = await _start(tester, script);
    final browser = app.services.browser;
    // The user reads a page in the in-app browser, then returns to the chat.
    await browser.newTab(url: 'http://127.0.0.1:8765/user');
    await tester.tap(find.byKey(const ValueKey('open-browser')));
    for (var i = 0; i < 50 && browser.title != 'User page'; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(browser.title, 'User page');
    await tester.tap(find.byTooltip('關閉'));
    await tester.pumpAndSettle();
    _approve(app);
    final sending = app.send('How much is tea?');
    while (!app.isGenerating) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Keep frames coming while the model uses the browser screen.
    while (app.isGenerating) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await sending;
    await tester.pumpAndSettle();
    _log(app);
    expect(app.visibleMessages.last.text, 'Tea costs 12 USD.');
    expect(find.byType(BrowserScreen), findsNothing);
    final tabs = browser.tabs;
    debugPrint(
      'TABS ${tabs.map((tab) => '${tab.id} ${tab.url} ${tab.openedByModel}')}',
    );
    expect(tabs.map((tab) => tab.url), [
      'http://127.0.0.1:8765/user',
      'http://127.0.0.1:8765/model',
    ]);
    expect(tabs.last.openedByModel, isTrue);
    // Both native views are alive: switching back shows the user's page.
    await tester.tap(find.byKey(const ValueKey('open-browser')));
    await tester.pumpAndSettle();
    browser.selectTab(tabs.first.id);
    for (var i = 0; i < 30 && browser.title != 'User page'; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(browser.title, 'User page');
    await tester.tap(find.byTooltip('關閉'));
    await tester.pumpAndSettle();
  });

  testWidgets('run_shell runs in Termux and notifications_list reads', (
    tester,
  ) async {
    var turn = 0;
    final script = _Script((request) {
      switch (turn++) {
        case 0:
          return _call('run_shell', {'command': 'uname -m'});
        case 1:
          return _call('notifications_list', {'limit': 10});
      }
      return _say('ok');
    });
    final app = await _start(tester, script);
    expect(app.services.shell.isAvailable, isTrue, reason: 'Set up Termux.');
    expect(
      app.services.notifications.isAvailable,
      isTrue,
      reason: 'Grant notification access.',
    );
    final requests = _approve(app);
    await app.send('Which CPU architecture, and any notifications?');
    _log(app);
    final results = _results(app);
    expect(requests.first.risk, RiskLevel.sensitive);
    expect(jsonDecode(results.first.content), containsPair('exit_code', 0));
    expect(results.first.content, contains('x86_64'));
    expect(results.last.content, contains('Tako fixture notification'));
  });
}
