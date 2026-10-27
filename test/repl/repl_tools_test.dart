import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/files/workspace.dart';
import 'package:tako/core/permissions/permission_gate.dart';
import 'package:tako/core/providers/cancel_token.dart';
import 'package:tako/core/providers/provider_config.dart';
import 'package:tako/core/tools/browser_tools.dart';
import 'package:tako/core/tools/device_tools.dart';
import 'package:tako/core/tools/repl_tools.dart';
import 'package:tako/core/tools/screen_tools.dart';
import 'package:tako/core/tools/tool.dart';
import 'package:tako/core/tools/tool_executor.dart';
import 'package:tako/core/tools/tool_registry.dart';
import 'package:tako/core/tools/tool_settings.dart';
import 'package:tako/data/audit_repository.dart';
import 'package:tako/data/database.dart';
import 'package:tako/platform/device_tools_capability.dart';
import 'package:tako/platform/repl/quickjs_repl.dart';

import '../browser/fake_browser.dart';
import '../screen/fake_screen.dart';

class _Workspace implements WorkspaceCapability {
  @override
  bool get isAvailable => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Opens apps as Android does: the launched app replaces Tako in front a
/// moment after the launch call returns.
class _Launcher implements DeviceToolsCapability {
  _Launcher(this.screen);
  final FakeScreen screen;
  @override
  bool get isAvailable => true;
  @override
  bool supports(String tool) => tool == 'open_app';
  @override
  Future<Map<String, Object?>> invoke(
    String tool,
    Map<String, Object?> args, {
    required CancelToken cancel,
  }) async {
    Timer(
      const Duration(milliseconds: 300),
      () => screen.launch(args['package']! as String),
    );
    return {'launched': true, 'completion_verified': false};
  }
}

void main() {
  test(
    'automatic mode distinguishes remote, local-server and on-device providers',
    () {
      final remote = ProviderConfig(
        id: 'remote',
        displayName: 'Remote',
        apiType: ApiType.responses,
        baseUrl: 'https://api.example.com',
        model: 'model',
      );
      final local = remote.copyWith(
        baseUrl: 'http://127.0.0.1:8080',
        isLocal: true,
      );
      final nano = ProviderConfig(
        id: 'nano',
        displayName: 'Nano',
        apiType: ApiType.onDevice,
        baseUrl: '',
        model: 'aicore:gemini-nano',
      );
      const settings = ToolSettings();
      expect(settings.usesRepl(remote), isTrue);
      expect(settings.usesRepl(local), isFalse);
      expect(settings.usesRepl(nano), isFalse);
      expect(
        settings.copyWith(controlMode: ControlToolMode.basic).usesRepl(remote),
        isFalse,
      );
      expect(
        settings.copyWith(controlMode: ControlToolMode.repl).usesRepl(nano),
        isTrue,
      );
      expect(
        ToolSettings.fromJson(
          settings.copyWith(controlMode: ControlToolMode.repl).toJson(),
        ).controlMode,
        ControlToolMode.repl,
      );
    },
  );
  late AppDatabase database;
  late FakeScreen screen;
  late FakeBrowser browser;
  late ReplToolSession session;
  late ToolExecutor executor;
  final requests = <PermissionRequest>[];
  var deny = false;
  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    screen = phoneScreen()..show('settings');
    browser = FakeBrowser({
      'https://example.com/': const FakePage('Example', 'Page text', [
        FakeElement('button', 'Next', click: 'https://example.com/next'),
      ]),
      'https://example.com/next': const FakePage('Next', 'Finished', []),
    });
    requests.clear();
    deny = false;
    late final PermissionGate gate;
    gate = PermissionGate(
      policy: const PermissionPolicy(fullPermissions: true),
      onPendingChanged: (request) {
        if (request == null) return;
        requests.add(request);
        scheduleMicrotask(
          () => gate.decide(
            deny ? PermissionChoice.deny : PermissionChoice.allowOnce,
          ),
        );
      },
    );
    final readings = ScreenReadings();
    final observer = ScreenObserver(
      screen: screen,
      workspace: _Workspace(),
      readings: readings,
      allowed: (_) => true,
    );
    final backend = ToolRegistry([
      ...createScreenTools(
        screen,
        workspace: _Workspace(),
        readings: readings,
        observer: observer,
      ),
      ...createDeviceTools(_Launcher(screen), observer: observer),
      ...createBrowserTools(browser),
    ]);
    final primitives = ToolExecutor(
      registry: backend,
      permissions: gate,
      audit: AuditRepository(database),
    );
    session = ReplToolSession(
      registry: backend,
      execute: primitives.execute,
      readings: readings,
      runtimeFactory: QuickJsRepl.new,
      loadSkill: (name) async => 'Trusted $name guide',
    );
    executor = ToolExecutor(
      registry: replPresentation(backend, session),
      permissions: gate,
      audit: AuditRepository(database),
    );
  });
  tearDown(() async {
    session.close();
    await database.close();
  });
  var count = 0;
  Future<ToolResultBlock> run(
    String name,
    Map<String, Object?> args, {
    CancelToken? cancel,
  }) async => (await executor.execute(
    ToolCallBlock(
      id: 'call-${count++}',
      name: name,
      arguments: jsonEncode(args),
    ),
    ToolContext(
      conversationId: 'chat',
      messageId: 'message-$count',
      cancel: cancel ?? CancelToken(),
    ),
  )).result;
  Future<void> load(String name) async =>
      expect((await run('read_skill', {'skill': name})).isError, isFalse);

  test(
    'REPL can choose silent sessions through the audited host tool',
    () async {
      await load('browser');
      final result = await run('js_repl', {
        'title': 'Read quietly',
        'code':
            'console.log(await browser.startSession({silent:true})); '
            'await browser.open({url:"https://example.com/"}); '
            'console.log(await browser.read());',
      });
      expect(result.isError, false);
      expect(browser.silent, true);
      expect(browser.openRequests, 0);
      expect(result.content, contains('browser_start_session'));
      expect(result.content, contains('Page text'));
    },
  );

  test(
    'skill must be loaded and the model sees REPL rather than raw controls',
    () async {
      final names = executor.registry.definitions.map(
        (definition) => definition.name,
      );
      expect(names, containsAll(['read_skill', 'js_repl']));
      expect(names, isNot(contains('tap')));
      final result = await run('js_repl', {
        'title': 'Read phone',
        'code': 'await phone.read();',
      });
      expect(result.content, contains('read_skill_first'));
      expect(screen.sessions, 0);
    },
  );

  test(
    'fresh JS observations and element refs navigate with individual audits',
    () async {
      await load('phone');
      final result = await run('js_repl', {
        'title': 'Open About phone',
        'code':
            'var s = await phone.read(); var about = s.elements.find(e => e.label.includes("About phone")); var done = await phone.tap(about); console.log(done.screen.app);',
      });
      expect(result.isError, isFalse, reason: result.content);
      expect(screen.current, 'settings/about');
      expect(result.sideEffects.single.kind, 'screen_tapped');
      final audits = await database.select(database.auditRecords).get();
      expect(
        audits.map((record) => record.toolName),
        containsAll(['read_skill', 'js_repl', 'read_screen', 'tap']),
      );
    },
  );

  test(
    'refs survive an unchanged re-read; a changed screen invalidates them instead of retargeting',
    () async {
      await load('phone');
      final kept = await run('js_repl', {
        'title': 'Check screen',
        'code':
            'var old = await phone.read(); var again = await phone.read(); '
            'var about = old.elements.find(e => e.label.includes("About phone")); '
            'console.log(about.ref === again.elements.find(e => e.label.includes("About phone")).ref); '
            'await phone.tap(about);',
      });
      expect(kept.isError, isFalse, reason: kept.content);
      expect(kept.content, contains('"output":"true\\n"'));
      expect(screen.current, 'settings/about');
      // The tap changed the screen: the saved element never names another.
      final stale = await run('js_repl', {
        'title': 'Check screen',
        'code': 'await phone.tap(about);',
      });
      expect(stale.isError, isTrue);
      expect(stale.content, contains('stale_element_read_again'));
      expect(stale.content, isNot(contains('session_reset')));
      expect(screen.actions, hasLength(1));
    },
  );

  test('tap accepts the element, its ref, or either under element', () async {
    await load('phone');
    final result = await run('js_repl', {
      'title': 'Open About phone',
      'code':
          'var forms = [e => e, e => e.ref, e => ({ref: e.ref}), e => ({element: e}), e => ({element: e.ref})]; '
          'for (var form of forms) { '
          'var s = await phone.read(); '
          'await phone.tap(form(s.elements.find(e => e.label.includes("About phone")))); '
          'await phone.pressKey({key: "back"}); }',
    });
    expect(result.isError, isFalse, reason: result.content);
    expect(
      screen.actions.where((action) => action.action == 'tap'),
      hasLength(5),
    );
    expect(screen.current, 'settings');
  });

  test('a bad target explains the accepted forms and keeps the session', () async {
    await load('phone');
    final missing = await run('js_repl', {
      'title': 'Open About phone',
      'code':
          'var s = await phone.read(); '
          'await phone.tap(s.elements.find(e => e.label === "No such row"));',
    });
    expect(missing.isError, isTrue);
    expect(missing.content, contains('got no element'));
    expect(missing.content, isNot(contains('session_reset')));
    final wrong = await run('js_repl', {
      'title': 'Open About phone',
      'code':
          'await phone.tap({target: s.elements.find(e => e.label.includes("About phone"))});',
    });
    expect(wrong.content, contains('element_reference_required'));
    expect(wrong.content, contains('{ref: element.ref}'));
    expect(wrong.content, contains('(other)'));
    expect(wrong.content, isNot(contains('target')));
    expect(screen.actions, isEmpty);
    // The bindings made before both failures are still there.
    final reused = await run('js_repl', {
      'title': 'Open About phone',
      'code':
          'await phone.tap(s.elements.find(e => e.label.includes("About phone")));',
    });
    expect(reused.isError, isFalse, reason: reused.content);
    expect(screen.current, 'settings/about');
  });

  test(
    'observations include bounds in the tap unit, view ids and clickability',
    () async {
      screen.show('messages');
      await load('phone');
      final result = await run('js_repl', {
        'title': 'Read messages',
        'code':
            'var s = await phone.read(); '
            'var send = s.elements.find(e => e.view_id === "com.example:id/send_button"); '
            'var row = s.elements.find(e => e.label === "Send"); '
            'console.log(JSON.stringify([send.clickable, row.bounds, s.width]));',
      });
      expect(result.isError, isFalse, reason: result.content);
      expect(
        result.content,
        contains(r'[true,{\"x1\":0,\"y1\":2200,\"x2\":1080,\"y2\":2300},1080]'),
      );
    },
  );

  test(
    'openApp waits for the launched app, so the same script can read it',
    () async {
      screen.show('tako');
      await load('phone');
      final result = await run('js_repl', {
        'title': 'Open Messages',
        'code':
            'var opened = await phone.openApp({package: "com.example.messages"}); '
            'var s = await phone.read(); '
            'console.log(opened.screen.app + "/" + s.app);',
      });
      expect(result.isError, isFalse, reason: result.content);
      expect(result.content, contains('Messages/Messages'));
    },
  );

  test('phone.wait pauses within its bound', () async {
    await load('phone');
    final waited = await run('js_repl', {
      'title': 'Wait for animation',
      'code': 'console.log((await phone.wait({ms: 20})).waited_ms);',
    });
    expect(waited.isError, isFalse, reason: waited.content);
    expect(waited.content, contains('"output":"20\\n"'));
    final tooLong = await run('js_repl', {
      'title': 'Wait for animation',
      'code': 'await phone.wait({ms: 60000});',
    });
    expect(tooLong.isError, isTrue);
    expect(tooLong.content, contains('waits 0..5000 milliseconds'));
  });

  test('read_skill presents refs instead of listing ids', () async {
    final skill = await run('read_skill', {'skill': 'phone', 'method': 'tap'});
    final schema = jsonDecode(skill.content.split('\n').last) as Map;
    final tap = (schema['phone.tap'] as Map)['parameters'] as Map;
    expect((tap['properties'] as Map).keys, containsAll(['ref', 'x', 'y']));
    expect((tap['properties'] as Map).keys, isNot(contains('id')));
    expect(tap['required'], isEmpty);
    expect(tap['anyOf'], hasLength(2));
  });

  test(
    'an id from a listing printed in an earlier response taps that element',
    () async {
      await load('phone');
      final read = await run('js_repl', {
        'title': 'Read settings',
        'code': 'console.log((await phone.read()).text);',
      });
      expect(
        read.content,
        contains(r'[4] Button \"About phone Pixel fixture\"'),
      );
      final tapped = await run('js_repl', {
        'title': 'Open About phone',
        'code': 'await phone.tap({id: 4});',
      });
      expect(tapped.isError, isFalse, reason: tapped.content);
      expect(screen.current, 'settings/about');
    },
  );

  test('a Send target still asks high-risk permission through JS', () async {
    screen.show('messages');
    deny = true;
    await load('phone');
    final result = await run('js_repl', {
      'title': 'Read a safe page',
      'code':
          'var s = await phone.read(); await phone.tap(s.elements.find(e => e.label === "Send"));',
    });
    expect(result.isError, isTrue);
    expect(requests.single.risk, RiskLevel.high);
    expect(screen.actions, isEmpty);
  });

  test('password entry is rejected before showing an approval', () async {
    screen.show('messages');
    await load('phone');
    final result = await run('js_repl', {
      'title': 'Fill field',
      'code':
          'var s = await phone.read(); await phone.type({element:s.elements.find(e => e.flags.includes("password")),text:"dummy"});',
    });
    expect(result.isError, isTrue);
    expect(result.content, contains('password_entry_blocked'));
    expect(requests, isEmpty);
    expect(screen.actions, isEmpty);
  });

  test('a script error keeps already committed action receipts', () async {
    await load('phone');
    final result = await run('js_repl', {
      'title': 'Open About phone',
      'code':
          'var s = await phone.read(); await phone.tap(s.elements.find(e => e.label.includes("About phone"))); throw new Error("demo failure");',
    });
    expect(result.isError, isTrue);
    expect(screen.current, 'settings/about');
    expect(result.sideEffects.single.kind, 'screen_tapped');
    expect(result.content, contains('"tool":"tap","ok":true'));
  });

  test(
    'browser APIs return structured observations and opaque element refs',
    () async {
      await load('browser');
      final result = await run('js_repl', {
        'title': 'Open next page',
        'code':
            'await browser.open({url:"https://example.com/"}); var page=await browser.read(); await browser.click(page.elements[0]); console.log(await browser.read());',
      });
      expect(result.isError, isFalse, reason: result.content);
      expect(browser.url, 'https://example.com/next');
      expect(result.sideEffects.single.kind, 'browser_clicked');
      expect(browser.modelActionTitle, 'Open next page');
    },
  );

  test(
    'plain ids, disabled operations and other capabilities cannot bypass the host',
    () async {
      await load('phone');
      // The script read the screen itself: its ids may belong to an older
      // listing than the one the model saw.
      final result = await run('js_repl', {
        'title': 'Check phone',
        'code': 'await phone.read(); await phone.tap({id:4});',
      });
      expect(result.content, contains('pass_the_element_not_its_id'));
      expect(screen.actions, isEmpty);
      final unknown = await run('js_repl', {
        'title': 'Check phone',
        'code': 'await phone.tap({id:99});',
      });
      expect(unknown.content, contains('unknown_id_read_again'));
      expect(screen.actions, isEmpty);
      session.registry.disabledTools.add('press_key');
      final disabled = await run('js_repl', {
        'title': 'Go home',
        'code': 'await phone.pressKey({key:"home"});',
      });
      expect(disabled.isError, isTrue);
      expect(screen.actions, isEmpty);
    },
  );
}
