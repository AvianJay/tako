import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/app/app_controller.dart';
import 'package:tako/core/browser/browser_capability.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/files/workspace.dart';
import 'package:tako/core/memory/memory.dart';
import 'package:tako/core/memory/settings.dart';
import 'package:tako/core/notifications/notification_capability.dart';
import 'package:tako/core/on_device/on_device_capability.dart';
import 'package:tako/core/permissions/permission_gate.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/core/screen/screen_capability.dart';
import 'package:tako/core/shell/shell_capability.dart';
import 'package:tako/core/shortcuts/shortcuts_capability.dart';
import 'package:tako/core/tools/tool_settings.dart';
import 'package:tako/data/database.dart';
import 'package:tako/platform/app_services.dart';
import 'package:tako/platform/device_tools_capability.dart';
import 'package:tako/platform/media_attachment_capability.dart';

import '../browser/fake_browser.dart';

class _Workspace implements WorkspaceCapability {
  @override
  bool get isAvailable => false;
  @override
  Future<List<ContentBlock>> hydrateBlocks(
    List<ContentBlock> blocks, {
    required bool vision,
    CancelToken? cancel,
  }) async => blocks;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// No native services, filesystem, HTTP, or secrets are used by these tests.
class _Services implements AppServices {
  _Services(this.browser);
  @override
  final BrowserCapability browser;
  @override
  final ScreenCapability screen = UnavailableScreen();
  @override
  final ShellCapability shell = UnavailableShell();
  @override
  final NotificationCapability notifications = UnavailableNotifications();
  @override
  final OnDeviceCapability onDevice = UnavailableOnDevice();
  @override
  final ShortcutsCapability shortcuts = UnavailableShortcuts();
  @override
  Future<void> refreshDeviceControl() async {}
  @override
  final WorkspaceCapability workspace = _Workspace();
  @override
  DeviceToolsCapability get deviceTools => const UnavailableDeviceTools();
  @override
  MediaAttachmentCapability get mediaAttachments =>
      const UnavailableMediaAttachments();
  @override
  bool get isAvailable => false;
  @override
  Future<DeviceContext> deviceContext() async =>
      const DeviceContext(osVersion: '15', model: 'Fixture phone');
  @override
  Future<String?> readSecret(String reference) async => null;
  @override
  Future<void> writeSecret(String reference, String? value) async {}
  @override
  Future<Map<String, String>> readHeaders(String? reference) async => {};
  @override
  Future<void> copyText(String text) async {}
  @override
  Future<void> shareText(String text) async {}
  @override
  Future<void> openLink(Uri uri) async {}
  @override
  Future<Uint8List> readWorkspaceImage(String relative) async => Uint8List(0);
  @override
  Future<void> shareWorkspaceFile(String relative) async {}
  @override
  Future<String?> pickTextFile({required int maxBytes}) async => null;
  @override
  Future<void> shareTextFile(String name, String text) async {}

  @override
  Future<void> shareImageFile(String name, Uint8List image) async {}
}

class _Adapter implements ProviderAdapter {
  _Adapter(this.turns);
  final List<List<ProviderEvent>> turns;
  final requests = <ChatRequest>[];
  @override
  Future<List<ModelInfo>> listModels({CancelToken? cancel}) async => [];
  @override
  Stream<ProviderEvent> send(
    ChatRequest request, {
    required CancelToken cancel,
  }) async* {
    final index = requests.length;
    requests.add(request);
    for (final event in turns[index]) {
      if (cancel.isCancelled) return;
      yield event;
    }
  }
}

List<ProviderEvent> _call(String name, Map<String, Object?> args) {
  final id = 'call_${name}_${args.hashCode}';
  return [
    ToolCallStart(id, name),
    ToolCallArgsDelta(id, jsonEncode(args)),
    ToolCallEnd(id),
    const Done('tool_calls'),
  ];
}

List<ProviderEvent> _say(String text) => [TextDelta(text), const Done('stop')];

final _template = File('assets/prompts/system_prompt.md').readAsStringSync();

Future<AppController> _app(
  _Adapter adapter, {
  BrowserCapability? browser,
  AppDatabase? database,
  String? template,
}) async {
  final db = database ?? AppDatabase(NativeDatabase.memory());
  final app = AppController(
    titleGenerator: (_, _, _) async => null,
    database: db,
    services: _Services(browser ?? UnavailableBrowser()),
    promptTemplate: template ?? _template,
    adapterFactory: (_, key, headers) => adapter,
  );
  addTearDown(() async {
    app.dispose();
    if (database == null) await db.close();
  });
  await app.initialize();
  await app.saveToolSettings(
    app.toolSettings.copyWith(controlMode: ControlToolMode.basic),
  );
  await app.saveProvider(
    ProviderConfig(
      id: 'fixture',
      displayName: 'Fixture',
      apiType: ApiType.chatCompletions,
      baseUrl: 'https://fixture.example.com/v1',
      model: 'fixture-model',
      capabilities: ProviderCapabilities(tools: true, contextWindow: 32000),
      maxOutputTokens: 256,
    ),
  );
  return app;
}

/// Answers each approval until [work] completes: chat-wide when offered.
Future<List<PermissionRequest>> _approveAll(
  AppController app,
  Future<void> work, {
  PermissionChoice Function(PermissionRequest request)? choose,
}) async {
  final seen = <PermissionRequest>[];
  void listener() {
    final pending = app.pendingApproval;
    if (pending == null || seen.any((r) => identical(r, pending))) return;
    seen.add(pending);
    final choice =
        choose?.call(pending) ??
        (pending.choices.contains(PermissionChoice.allowInChat)
            ? PermissionChoice.allowInChat
            : PermissionChoice.allowOnce);
    scheduleMicrotask(() => app.permissionGate.decide(choice));
  }

  app.addListener(listener);
  try {
    await work;
  } finally {
    app.removeListener(listener);
  }
  return seen;
}

Future<void> _until(AppController app, bool Function() condition) {
  if (condition()) return Future.value();
  final ready = Completer<void>();
  void listener() {
    if (condition() && !ready.isCompleted) ready.complete();
  }

  app.addListener(listener);
  return ready.future
      .timeout(const Duration(seconds: 5))
      .whenComplete(() => app.removeListener(listener));
}

List<ToolResultBlock> _results(AppController app) => [
  for (final message in app.visibleMessages)
    if (message.role == MessageRole.tool)
      ...message.content.whereType<ToolResultBlock>(),
];

void main() {
  test(
    'memories persist across conversations and the pinned profile reaches new prompts',
    () async {
      final adapter = _Adapter([
        _call('memory_save', {
          'text': 'The user is called Alex',
          'kind': 'profile',
        }),
        _say('Noted.'),
        _call('memory_search', {'query': 'called'}),
        _say('You are Alex.'),
      ]);
      final app = await _app(adapter);
      final first = await _approveAll(
        app,
        app.send('My name is Alex. Remember it.'),
      );
      expect(first.single.toolName, 'memory_save');
      expect(first.single.risk, RiskLevel.action);
      final firstPrompt = adapter.requests.first.systemPrompt;
      expect(firstPrompt, contains('## Memory'));
      expect(firstPrompt, isNot(contains('The user is called Alex')));
      expect(
        adapter.requests.first.tools.map((tool) => tool.name),
        containsAll(memoryToolNamesForTest),
      );
      final saved = (await app.memory.list()).single;
      expect(saved.pinned, isTrue);
      expect(saved.kind, MemoryKind.profile);
      final receipt = _results(app).single;
      expect(receipt.sideEffects.single.kind, 'memory_saved');
      expect(
        MemoryUndo.fromJson(receipt.sideEffects.single.memoryUndo)?.revision,
        saved.revision,
      );
      // The prompt of a conversation never changes after it starts.
      expect(app.conversation!.systemPrompt, firstPrompt);

      await app.newChat();
      final second = await _approveAll(app, app.send('What is my name?'));
      expect(second.single.toolName, 'memory_search');
      expect(second.single.risk, RiskLevel.sensitive);
      expect(
        adapter.requests[2].systemPrompt,
        contains('What you know about the user:\n- The user is called Alex'),
      );
      expect(_results(app).single.content, contains('The user is called Alex'));
      expect(app.visibleMessages.last.text, 'You are Alex.');
    },
  );

  test('profile and personalization are frozen per conversation', () async {
    final adapter = _Adapter([
      _say('one'),
      _say('two'),
      _say('three'),
      _say('four'),
    ]);
    final app = await _app(adapter);
    await app.memory.save(
      text: 'Prefers metric units',
      kind: MemoryKind.preference,
    );
    await app.savePersonalization(
      const PersonalizationSettings(
        displayName: 'Alex',
        userNotes: 'Use bullet points.',
        replyStyle: ReplyStyle.concise,
      ),
    );
    await app.send('Hello');
    final firstId = app.conversation!.id;
    final prompt = adapter.requests[0].systemPrompt;
    expect(prompt, contains('- Prefers metric units'));
    expect(
      prompt,
      contains(
        '## Notes from the user\nFollow these unless they conflict with the rules above.\n'
        'Preferred name: Alex\nUse bullet points.\n'
        'Reply style: concise. Keep replies brief and direct.',
      ),
    );

    await app.memory.save(text: 'Lives in Taichung', kind: MemoryKind.profile);
    await app.savePersonalization(
      const PersonalizationSettings(replyStyle: ReplyStyle.detailed),
    );
    await app.newChat();
    await app.send('New chat');
    final next = adapter.requests[1].systemPrompt;
    expect(next, contains('- Lives in Taichung'));
    expect(next, contains('Reply style: detailed.'));
    expect(next, isNot(contains('Preferred name')));

    // A provider change re-renders the old chat with its own snapshot.
    await app.saveProvider(
      ProviderConfig(
        id: 'second',
        displayName: 'Second',
        apiType: ApiType.chatCompletions,
        baseUrl: 'https://second.example.com/v1',
        model: 'second-model',
        capabilities: ProviderCapabilities(tools: true, contextWindow: 32000),
        maxOutputTokens: 256,
      ),
    );
    await app.openConversation(firstId);
    await app.selectProvider('second');
    await app.send('Again');
    final rerendered = adapter.requests[2].systemPrompt;
    expect(rerendered, contains('You run on Second (second-model)'));
    expect(rerendered, contains('- Prefers metric units'));
    expect(rerendered, isNot(contains('Taichung')));
    expect(rerendered, contains('Preferred name: Alex'));
    await app.send('Once more');
    expect(adapter.requests[3].systemPrompt, rerendered);
  });

  test(
    'an app update that changes the template re-renders a chat once',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final before = _Adapter([_say('one')]);
      final first = await _app(before, database: database);
      await first.memory.save(
        text: 'Prefers metric units',
        kind: MemoryKind.preference,
      );
      await first.send('Hello');
      final old = before.requests.single.systemPrompt;
      expect(old, contains('- Prefers metric units'));
      // The next version of the app ships a changed template.
      const rule = 'Reply in the language the user writes in.';
      final after = _Adapter([_say('two'), _say('three')]);
      final updated = await _app(
        after,
        database: database,
        template: _template.replaceFirst(rule, '$rule Be brief.'),
      );
      await updated.memory.save(
        text: 'Lives in Taichung',
        kind: MemoryKind.profile,
      );
      expect(updated.conversation?.id, first.conversation!.id);
      await updated.send('Again');
      final rerendered = after.requests[0].systemPrompt;
      expect(rerendered, isNot(old));
      expect(rerendered, contains('$rule Be brief.'));
      // The chat keeps its own profile snapshot.
      expect(rerendered, contains('- Prefers metric units'));
      expect(rerendered, isNot(contains('Taichung')));
      await updated.send('Once more');
      expect(after.requests[1].systemPrompt, rerendered);
    },
  );

  test('the normal reply style adds no notes section', () async {
    final adapter = _Adapter([_say('ok')]);
    final app = await _app(adapter);
    await app.send('Hi');
    expect(
      adapter.requests.single.systemPrompt,
      isNot(contains('## Notes from the user')),
    );
  });

  test('a model without tools still gets the pinned profile', () async {
    final adapter = _Adapter([_say('Hi Alex'), _say('ok')]);
    final app = await _app(adapter);
    await app.saveProvider(
      ProviderConfig(
        id: 'fixture',
        displayName: 'Fixture',
        apiType: ApiType.chatCompletions,
        baseUrl: 'https://fixture.example.com/v1',
        model: 'fixture-model',
        capabilities: ProviderCapabilities(contextWindow: 32000),
        maxOutputTokens: 256,
      ),
    );
    await app.memory.save(text: 'Name is Alex', kind: MemoryKind.profile);
    await app.send('Hi');
    final prompt = adapter.requests.single.systemPrompt;
    expect(prompt, isNot(contains('## Memory')));
    expect(prompt, contains('## About the user'));
    expect(prompt, contains('- Name is Alex'));
    expect(adapter.requests.single.tools, isEmpty);
    // Turning memory off removes it from the running chat as well.
    await app.saveMemorySettings(const MemorySettings(enabled: false));
    await app.send('Again');
    expect(adapter.requests.last.systemPrompt, isNot(contains('Name is Alex')));
  });

  test('switched-off memory removes tools and the profile section', () async {
    final adapter = _Adapter([_say('ok')]);
    final app = await _app(adapter);
    await app.memory.save(text: 'Name is Alex', kind: MemoryKind.profile);
    await app.saveMemorySettings(const MemorySettings(enabled: false));
    await app.send('Hi');
    final request = adapter.requests.single;
    expect(request.systemPrompt, isNot(contains('## Memory')));
    expect(request.systemPrompt, isNot(contains('Name is Alex')));
    expect(
      request.tools.map((tool) => tool.name),
      isNot(contains('memory_save')),
    );
    // Saved memories are kept while memory is off.
    expect(await app.memory.list(), hasLength(1));
  });

  test('incognito chats use no memory and disappear when left', () async {
    final adapter = _Adapter([_say('Private answer'), _say('Normal answer')]);
    final app = await _app(adapter);
    await app.memory.save(text: 'Name is Alex', kind: MemoryKind.profile);
    await app.newChat(incognito: true);
    expect(app.incognito, isTrue);
    await app.send('A private question');
    final request = adapter.requests.single;
    expect(request.systemPrompt, isNot(contains('## Memory')));
    expect(request.systemPrompt, isNot(contains('Name is Alex')));
    expect(
      request.tools.map((tool) => tool.name),
      isNot(contains('memory_search')),
    );
    final id = app.conversation!.id;
    expect(app.conversation!.incognito, isTrue);
    expect(app.conversations.where((c) => c.id == id), isEmpty);
    expect(await app.settings.getString('conversation'), isNull);

    await app.newChat();
    expect(app.incognito, isFalse);
    expect(await app.chats.getConversation(id), isNull);
    expect(await app.chats.getMessages(id), isEmpty);
    await app.send('A normal question');
    expect(
      adapter.requests.last.systemPrompt,
      contains('What you know about the user:\n- Name is Alex'),
    );
    expect(app.conversations, hasLength(1));
  });

  test(
    'an incognito chat left by a process death is purged at startup',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final first = await _app(_Adapter([_say('ok')]), database: database);
      await first.newChat(incognito: true);
      await first.send('Private');
      final id = first.conversation!.id;
      expect(await first.chats.getConversation(id), isNotNull);
      // No navigation happens: the process is gone and the app starts again.
      final restarted = await _app(_Adapter([]), database: database);
      expect(await restarted.chats.getConversation(id), isNull);
      expect(restarted.conversation, isNull);
    },
  );

  test('restoring on rewind removes memories saved after that point', () async {
    final adapter = _Adapter([
      _call('memory_save', {'text': 'Owns a red bike'}),
      _say('Saved.'),
    ]);
    final app = await _app(adapter);
    await _approveAll(app, app.send('Remember my red bike'));
    expect(await app.memory.list(), hasLength(1));
    final user = app.visibleMessages.first;
    final effects = app.sideEffectsAfter(user);
    expect(effects.single.kind, 'memory_saved');
    expect(effects.single.summary, 'Owns a red bike');
    await app.restoreSideEffects(effects);
    await app.rewind(user);
    expect(await app.memory.list(), isEmpty);
  });

  test('the model completes a multi-step task in the in-app browser', () async {
    final browser = shopBrowser();
    final adapter = _Adapter([
      _call('browser_open', {'url': 'https://shop.example.com/'}),
      _call('browser_read', {}),
      _call('browser_type', {'id': 1, 'text': 'tea', 'submit': true}),
      _call('browser_read', {}),
      _call('browser_click', {'id': 2}),
      _call('browser_read', {}),
      _say('Green tea is in your cart.'),
    ]);
    final app = await _app(adapter, browser: browser);
    var opened = 0;
    browser.onRequestOpen = () => opened++;
    final approvals = await _approveAll(
      app,
      app.send('Add green tea to my cart on shop.example.com'),
    );
    expect(approvals.map((request) => request.toolName), [
      'browser_open',
      'browser_read',
      'browser_type',
      'browser_click',
    ]);
    expect(
      browser.log,
      containsAllInOrder([
        'load https://shop.example.com/',
        'read https://shop.example.com/',
        'type Search products=tea ⏎',
        'read https://shop.example.com/search?q=tea',
        'click Add to cart',
        'read https://shop.example.com/cart',
      ]),
    );
    // The model's turns acted on a browser the user could see.
    expect(opened, greaterThan(0));
    expect(_results(app).every((result) => !result.isError), isTrue);
    expect(_results(app).last.content, contains('Cart: Green tea x1.'));
    expect(
      adapter.requests.first.systemPrompt,
      contains('## Built-in browser'),
    );
    expect(app.visibleMessages.last.text, 'Green tea is in your cart.');
    expect(browser.modelActive, isFalse);
  });

  test('taking over the browser stops the response and its approval', () async {
    final browser = shopBrowser();
    final adapter = _Adapter([
      _call('browser_open', {'url': 'https://shop.example.com/'}),
      _call('browser_read', {}),
      _say('Not reached'),
    ]);
    final app = await _app(adapter, browser: browser);
    final sending = app.send('Open the shop');
    await _until(app, () => app.pendingApproval?.toolName == 'browser_open');
    app.permissionGate.decide(PermissionChoice.allowInChat);
    await _until(app, () => app.pendingApproval?.toolName == 'browser_read');
    expect(browser.modelActive, isTrue);
    browser.takeOver();
    await sending;
    expect(app.isGenerating, isFalse);
    expect(app.pendingApproval, isNull);
    expect(jsonDecode(_results(app).last.content), {'error': 'cancelled'});
    expect(adapter.requests, hasLength(2));
    expect(browser.modelActive, isFalse);
    expect(browser.log, isNot(contains('read https://shop.example.com/')));
  });

  test('a send-like browser button always needs its own approval', () async {
    final browser = shopBrowser();
    final adapter = _Adapter([
      _call('browser_open', {'url': 'https://shop.example.com/'}),
      _call('browser_read', {}),
      _call('browser_type', {'id': 1, 'text': 'tea', 'submit': true}),
      _call('browser_read', {}),
      _call('browser_click', {'id': 3}),
      _say('Not sent.'),
    ]);
    final app = await _app(adapter, browser: browser);
    // Even with full permissions, high risk still asks.
    await app.savePermissionPolicy(
      app.permissionGate.policy.copyWith(fullPermissions: true),
    );
    final approvals = await _approveAll(
      app,
      app.send('Send the tea as a gift'),
      choose: (_) => PermissionChoice.deny,
    );
    final request = approvals.single;
    expect(request.toolName, 'browser_click');
    expect(request.risk, RiskLevel.high);
    expect(request.details['element'], 'button “Send as gift”');
    expect(browser.log, isNot(contains('click Send as gift')));
    expect(jsonDecode(_results(app).last.content), {'error': 'denied_by_user'});
  });
}

const memoryToolNamesForTest = [
  'memory_search',
  'memory_save',
  'memory_update',
  'memory_delete',
];
