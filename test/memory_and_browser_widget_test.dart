import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/app/app.dart';
import 'package:tako/app/app_controller.dart';
import 'package:tako/core/browser/browser_capability.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/conversation.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/memory/memory.dart';
import 'package:tako/core/memory/settings.dart';
import 'package:tako/core/permissions/permission_gate.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/data/database.dart';
import 'package:tako/platform/services.dart';
import 'package:tako/ui/browser/browser_screen.dart';
import 'package:tako/ui/chat/tool_widgets.dart';

import 'browser/fake_browser.dart';

class _Services extends PlatformServices {
  _Services([BrowserCapability? browser])
    : _browser = browser ?? UnavailableBrowser();
  final BrowserCapability _browser;
  @override
  BrowserCapability get browser => _browser;
  @override
  Future<DeviceContext> deviceContext() async =>
      const DeviceContext(osVersion: 'test', model: 'test device');
  @override
  Future<String?> readSecret(String reference) async => null;
  @override
  Future<void> writeSecret(String reference, String? value) async {}
}

class _Adapter implements ProviderAdapter {
  _Adapter(this.turns);
  final List<List<ProviderEvent>> turns;
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
      // The model is still thinking until the user stops or takes over.
      await cancel.whenCancelled;
      return;
    }
    for (final event in turns[index]) {
      if (cancel.isCancelled) return;
      yield event;
    }
  }
}

List<ProviderEvent> _call(String id, String name, Map<String, Object?> args) =>
    [
      ToolCallStart(id, name),
      ToolCallArgsDelta(id, jsonEncode(args)),
      ToolCallEnd(id),
      const Done('tool_calls'),
    ];

Future<AppController> _boot(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  BrowserCapability? browser,
  ProviderAdapter? adapter,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final database = AppDatabase(NativeDatabase.memory());
  final controller = AppController(
    titleGenerator: (_, _, _) async => null,
    database: database,
    services: _Services(browser),
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
      child: const TakoApp(),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Drift closes cancelled query streams on a zero-length timer.
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });
  return controller;
}

/// Lets real database work and fake timers progress until [ready].
Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(ready(), isTrue);
  // Rebuild once more: the controller notifies after the awaited change.
  await tester.pump();
}

bool _shown(Finder finder) => finder.evaluate().isNotEmpty;

void main() {
  testWidgets(
    'the model opens the browser, asks there, and the user can take over',
    (tester) async {
      final browser = shopBrowser();
      final adapter = _Adapter([
        _call('open', 'browser_open', {'url': 'https://shop.example.com/'}),
        _call('read', 'browser_read', {}),
      ]);
      final app = await _boot(tester, browser: browser, adapter: adapter);
      var done = false;
      unawaited(
        app
            .send('Look up tea on shop.example.com')
            .whenComplete(() => done = true),
      );

      // The first approval appears in the chat, naming the site.
      await _waitFor(tester, () => _shown(find.byType(ToolApprovalSheet)));
      expect(find.text('Page: shop.example.com'), findsOneWidget);
      await tester.tap(find.text('Allow in this chat'));

      // Acting on the page opens the shared browser so the user can watch.
      await _waitFor(tester, () => _shown(find.byType(BrowserScreen)));
      // Finish the page transition; the busy banner never settles.
      await tester.pump(const Duration(milliseconds: 600));
      await _waitFor(
        tester,
        () => _shown(
          find.descendant(
            of: find.byType(BrowserScreen),
            matching: find.byType(ToolApprovalSheet),
          ),
        ),
      );
      expect(find.text('Shop'), findsOneWidget);
      expect(find.text('Tako is using the browser'), findsOneWidget);
      // The covered chat keeps its own copy of the sheet; act in the browser.
      await tester.tap(
        find.descendant(
          of: find.byType(BrowserScreen),
          matching: find.text('Allow in this chat'),
        ),
      );
      await _waitFor(
        tester,
        () => browser.log.contains('read https://shop.example.com/'),
      );

      // Still generating: taking over stops the response.
      expect(find.byKey(const ValueKey('browser-take-over')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('browser-take-over')));
      // The send future completes in this fake zone; pump instead of
      // awaiting it in a real zone, where its microtasks never run.
      await _waitFor(tester, () => done && !app.isGenerating);
      await tester.pumpAndSettle();
      expect(find.text('Tako is using the browser'), findsNothing);
      expect(find.byType(BrowserScreen), findsOneWidget);
      expect(browser.modelActive, isFalse);
      expect(tester.takeException(), isNull);

      // Closing keeps the page for the next visit.
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(BrowserScreen), findsNothing);
      expect(browser.viewMounted, isFalse);
      expect(browser.url, 'https://shop.example.com/');
    },
  );

  testWidgets('the saved-to-memory chip undoes only that save', (tester) async {
    final app = await _boot(tester);
    late MemoryEntry entry;
    await tester.runAsync(() async {
      entry = (await app.memory.save(text: 'Likes hiking')).entry;
      final now = DateTime.now();
      await app.chats.createConversation(
        Conversation(
          id: 'memory-chat',
          createdAt: now,
          updatedAt: now,
          systemPrompt: 'Fixture',
          providerId: 'local',
          model: 'llama-server',
        ),
      );
      for (final message in [
        ChatMessage(
          id: 'user',
          conversationId: 'memory-chat',
          role: MessageRole.user,
          content: const [TextBlock('I like hiking')],
          createdAt: now,
        ),
        ChatMessage(
          id: 'call-message',
          conversationId: 'memory-chat',
          parentId: 'user',
          role: MessageRole.assistant,
          content: const [
            ToolCallBlock(
              id: 'save',
              name: 'memory_save',
              arguments: '{"text":"Likes hiking"}',
            ),
          ],
          createdAt: now.add(const Duration(seconds: 1)),
        ),
        ChatMessage(
          id: 'result-message',
          conversationId: 'memory-chat',
          parentId: 'call-message',
          role: MessageRole.tool,
          content: [
            ToolResultBlock(
              toolCallId: 'save',
              toolName: 'memory_save',
              content: '{"saved":{}}',
              sideEffects: [
                SideEffect(
                  kind: 'memory_saved',
                  summary: 'Likes hiking',
                  memoryUndo: MemoryUndo(
                    id: entry.id,
                    revision: entry.revision,
                  ).toJson(),
                ),
              ],
            ),
          ],
          createdAt: now.add(const Duration(seconds: 2)),
        ),
      ]) {
        await app.chats.saveMessage(message);
      }
      await app.openConversation('memory-chat');
    });
    await _waitFor(tester, () => _shown(find.text('Undo')));
    expect(find.text('Saved to memory · Likes hiking'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await _waitFor(
      tester,
      () => _shown(find.text('Removed from memory · Likes hiking')),
    );
    expect(await tester.runAsync(() => app.memory.get(entry.id)), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('memory screen lists, searches, pins and edits memories', (
    tester,
  ) async {
    final app = await _boot(tester);
    await tester.runAsync(() async {
      await app.memory.save(text: 'Name is Alex', kind: MemoryKind.profile);
      await app.memory.save(text: 'Allergic to peanuts');
    });
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Memory'));
    await _waitFor(tester, () => _shown(find.text('Allergic to peanuts')));
    expect(find.text('Name is Alex'), findsOneWidget);
    expect(find.text('Pinned profile: 3/150 words'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'peanut');
    await _waitFor(tester, () => !_shown(find.text('Name is Alex')));
    expect(find.text('Allergic to peanuts'), findsOneWidget);

    await tester.tap(find.byTooltip('Pin'));
    await _waitFor(tester, () => _shown(find.byTooltip('Unpin')));
    final pinned = await tester.runAsync(() => app.memory.list());
    expect(pinned!.firstWhere((e) => e.text.contains('peanuts')).pinned, true);

    await tester.tap(find.text('Allergic to peanuts'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Allergic to peanuts and shellfish',
    );
    await tester.tap(find.text('Preference'));
    await tester.tap(find.text('Save'));
    await _waitFor(
      tester,
      () => _shown(find.text('Allergic to peanuts and shellfish')),
    );
    final edited = (await tester.runAsync(
      () => app.memory.search('shellfish'),
    ))!;
    expect(edited.single.kind, MemoryKind.preference);

    // Let the editor's closing transition finish before tapping beneath it.
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await _waitFor(tester, () => !app.memorySettings.enabled);
    expect(find.textContaining('Memory is off'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Leave the screen inside the test: drift closes its query streams on a
    // zero-length timer, which must run before the tree check at the end.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('personalization saves name, instructions and reply style', (
    tester,
  ) async {
    final app = await _boot(tester);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personalization'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('personalization-name')),
      'Alex',
    );
    await tester.enterText(
      find.byKey(const ValueKey('personalization-notes')),
      'Answer in Traditional Chinese.',
    );
    await tester.tap(find.text('Concise'));
    await tester.tap(find.text('Save'));
    await _waitFor(tester, () => app.personalization.displayName == 'Alex');
    expect(app.personalization.replyStyle, ReplyStyle.concise);
    expect(
      app.personalization.promptNotes,
      'Preferred name: Alex\nAnswer in Traditional Chinese.\n'
      'Reply style: concise. Keep replies brief and direct.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow chat bar offers the browser and incognito chat', (
    tester,
  ) async {
    final app = await _boot(
      tester,
      size: const Size(320, 700),
      browser: shopBrowser(),
    );
    expect(find.byKey(const ValueKey('open-browser')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('incognito-toggle')));
    await _waitFor(tester, () => app.incognitoDraft && !app.busy);
    await tester.pumpAndSettle();
    expect(find.text('Incognito chat'), findsOneWidget);
    expect(
      find.text('Memory is off, and this chat is deleted when you leave it.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('open-browser')));
    await tester.pumpAndSettle();
    expect(find.byType(BrowserScreen), findsOneWidget);
    expect(
      find.text('Enter an address, or ask Tako to open a page.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('browser-title')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('browser-address')),
      'shop.example.com',
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Shop'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a browser opened for the model closes when the answer is ready',
    (tester) async {
      final browser = shopBrowser();
      // The user's page stays in its tab; the model opens its own.
      await browser.navigate('https://shop.example.com/login');
      final adapter = _Adapter([
        _call('open', 'browser_open', {'url': 'https://shop.example.com/'}),
        _call('read', 'browser_read', {}),
        [const TextDelta('The shop sells tea.'), const Done('stop')],
      ]);
      final app = await _boot(tester, browser: browser, adapter: adapter);
      await tester.runAsync(
        () => app.savePermissionPolicy(
          const PermissionPolicy(fullPermissions: true),
        ),
      );
      var done = false;
      unawaited(
        app.send('What does the shop sell?').whenComplete(() => done = true),
      );
      await _waitFor(tester, () => _shown(find.byType(BrowserScreen)));
      await _waitFor(tester, () => done && !app.isGenerating);
      await tester.pumpAndSettle();
      // Back in the chat with the answer; the pages are kept.
      expect(find.byType(BrowserScreen), findsNothing);
      expect(find.text('The shop sells tea.'), findsOneWidget);
      expect(browser.tabs.map((tab) => tab.url), [
        'https://shop.example.com/login',
        'https://shop.example.com/',
      ]);
      expect(browser.tabs.last.openedByModel, isTrue);
      expect(browser.activeTabId, browser.tabs.last.id);

      // The tab list switches, closes and adds tabs.
      await tester.tap(find.byKey(const ValueKey('open-browser')));
      await tester.pumpAndSettle();
      expect(find.byType(BrowserScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('browser-tabs')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Opened by Tako'), findsOneWidget);
      final userTab = browser.tabs.first.id;
      final modelTab = browser.tabs.last.id;
      await tester.tap(find.byKey(ValueKey('browser-close-tab-$modelTab')));
      await tester.pumpAndSettle();
      expect(browser.tabs.map((tab) => tab.id), [userTab]);
      await tester.tap(find.byKey(const ValueKey('browser-new-tab')));
      await tester.pumpAndSettle();
      expect(browser.tabs, hasLength(2));
      expect(browser.url, isEmpty);
      await tester.tap(find.byKey(const ValueKey('browser-tabs')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('browser-tab-$userTab')));
      await tester.pumpAndSettle();
      expect(browser.activeTabId, userTab);
      expect(find.text('Sign in'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a browser the user opened stays open after the model', (
    tester,
  ) async {
    final browser = shopBrowser();
    final adapter = _Adapter([
      _call('read', 'browser_read', {}),
      [const TextDelta('It is the shop.'), const Done('stop')],
    ]);
    final app = await _boot(tester, browser: browser, adapter: adapter);
    await tester.runAsync(
      () => app.savePermissionPolicy(
        const PermissionPolicy(fullPermissions: true),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-browser')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => browser.navigate('https://shop.example.com/'));
    await tester.pumpAndSettle();
    var done = false;
    unawaited(app.send('What page is this?').whenComplete(() => done = true));
    await _waitFor(tester, () => done && !app.isGenerating);
    await tester.pumpAndSettle();
    expect(browser.log, contains('read https://shop.example.com/'));
    expect(find.byType(BrowserScreen), findsOneWidget);
  });
}
