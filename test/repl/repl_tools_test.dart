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
import 'package:tako/core/tools/repl_tools.dart';
import 'package:tako/core/tools/screen_tools.dart';
import 'package:tako/core/tools/tool.dart';
import 'package:tako/core/tools/tool_executor.dart';
import 'package:tako/core/tools/tool_registry.dart';
import 'package:tako/core/tools/tool_settings.dart';
import 'package:tako/data/audit_repository.dart';
import 'package:tako/data/database.dart';
import 'package:tako/platform/repl/quickjs_repl.dart';

import '../browser/fake_browser.dart';
import '../screen/fake_screen.dart';

class _Workspace implements WorkspaceCapability {
  @override
  bool get isAvailable => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
    final backend = ToolRegistry([
      ...createScreenTools(
        screen,
        workspace: _Workspace(),
        readings: readings,
        observer: ScreenObserver(
          screen: screen,
          workspace: _Workspace(),
          readings: readings,
          allowed: (_) => true,
        ),
      ),
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
    'a newer observation invalidates saved refs instead of retargeting ids',
    () async {
      await load('phone');
      final result = await run('js_repl', {
        'title': 'Check screen',
        'code':
            'var old = await phone.read(); await phone.read(); await phone.tap(old.elements.find(e => e.label.includes("About phone")));',
      });
      expect(result.isError, isTrue);
      expect(result.content, contains('stale_element_read_again'));
      expect(screen.actions, isEmpty);
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
      final result = await run('js_repl', {
        'title': 'Check phone',
        'code': 'await phone.read(); await phone.tap({id:4});',
      });
      expect(result.content, contains('element_reference_required'));
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
