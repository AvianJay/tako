import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/app/app_controller.dart';
import 'package:tako/core/browser/browser_capability.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/conversation.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/files/workspace.dart';
import 'package:tako/core/notifications/notification_capability.dart';
import 'package:tako/core/on_device/on_device_capability.dart';
import 'package:tako/core/permissions/permission_gate.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/core/screen/device_control_settings.dart';
import 'package:tako/core/shell/shell_capability.dart';
import 'package:tako/core/shortcuts/shortcuts_capability.dart';
import 'package:tako/core/tools/device_tools.dart';
import 'package:tako/core/tools/screen_tools.dart';
import 'package:tako/core/tools/tool_settings.dart';
import 'package:tako/data/database.dart';
import 'package:tako/platform/app_services.dart';
import 'package:tako/platform/device_tools_capability.dart';
import 'package:tako/platform/media_attachment_capability.dart';

import '../screen/fake_screen.dart';

class _Workspace implements WorkspaceCapability {
  @override
  bool get isAvailable => false;
  @override
  Future<ImageBlock> importImageBytes(
    String name,
    Uint8List bytes, {
    CancelToken? cancel,
  }) async => ImageBlock(path: 'attachments/$name', mimeType: 'image/jpeg');
  @override
  Future<List<ContentBlock>> hydrateBlocks(
    List<ContentBlock> blocks, {
    required bool vision,
    CancelToken? cancel,
  }) async => blocks;
  final removed = <String>[];
  @override
  Future<void> removeAttachments(Iterable<String> paths) async =>
      removed.addAll(paths);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// open_app by name, launching the fake app on the fake screen.
class _DeviceTools implements DeviceToolsCapability {
  _DeviceTools(this.screen);
  final FakeScreen screen;
  static const apps = [
    (label: 'Settings', packageName: 'com.android.settings'),
    (label: 'Messages', packageName: 'com.example.messages'),
  ];
  @override
  bool get isAvailable => true;
  @override
  bool supports(String tool) => tool == 'open_app';
  @override
  Future<Map<String, Object?>> invoke(
    String tool,
    Map<String, Object?> arguments, {
    required CancelToken cancel,
  }) async {
    final package =
        arguments['package'] as String? ??
        matchApps(arguments['name']! as String, apps).single.packageName;
    screen.launch(package);
    return {'launched': true, 'completion_verified': false};
  }
}

class _Shell extends UnavailableShell {
  bool ready = false;
  @override
  bool get installed => ready;
  @override
  bool get permitted => ready;
  @override
  String get environment => 'Termux on this phone';
}

class _Services implements AppServices {
  _Services(this.screen) : deviceTools = _DeviceTools(screen);
  @override
  final FakeScreen screen;
  @override
  final DeviceToolsCapability deviceTools;
  @override
  final _Shell shell = _Shell();
  @override
  final NotificationCapability notifications = UnavailableNotifications();
  @override
  final OnDeviceCapability onDevice = UnavailableOnDevice();
  @override
  final ShortcutsCapability shortcuts = UnavailableShortcuts();
  @override
  final BrowserCapability browser = UnavailableBrowser();
  @override
  final _Workspace workspace = _Workspace();
  @override
  MediaAttachmentCapability get mediaAttachments =>
      const UnavailableMediaAttachments();
  int refreshes = 0;
  @override
  Future<void> refreshDeviceControl() async => refreshes++;
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
}

typedef _Turn = List<ProviderEvent> Function(ChatRequest request);

/// A scripted model that reads ids from the latest tool result, as a real
/// model would.
class _Adapter implements ProviderAdapter {
  _Adapter(this.turns);
  final List<_Turn> turns;
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
    if (index >= turns.length) {
      await cancel.whenCancelled;
      return;
    }
    for (final event in turns[index](request)) {
      if (cancel.isCancelled) return;
      yield event;
    }
  }
}

String _lastResult(ChatRequest request) => request.messages
    .expand((message) => message.content)
    .whereType<ToolResultBlock>()
    .last
    .content;

/// The id the latest read_screen gave an element whose label starts so.
int _id(ChatRequest request, String label) => int.parse(
  RegExp(
    '\\[(\\d+)\\] \\w+ "${RegExp.escape(label)}',
  ).firstMatch(_lastResult(request))!.group(1)!,
);

_Turn _call(String name, [Object? args = const <String, Object?>{}]) =>
    (request) {
      final arguments = args is Map<String, Object?> Function(ChatRequest)
          ? args(request)
          : args! as Map<String, Object?>;
      final id = 'call_${name}_${request.messages.length}';
      return [
        ToolCallStart(id, name),
        ToolCallArgsDelta(
          id,
          jsonEncode({
            if (screenToolNames.contains(name) || name == 'open_app')
              'title': name,
            ...arguments,
          }),
        ),
        ToolCallEnd(id),
        const Done('tool_calls'),
      ];
    };

_Turn _say(String Function(ChatRequest request) text) =>
    (request) => [TextDelta(text(request)), const Done('stop')];

final _template = File('assets/prompts/system_prompt.md').readAsStringSync();

Future<(AppController, _Services)> _app(
  _Adapter adapter, {
  FakeScreen? screen,
  bool vision = false,
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  final services = _Services(screen ?? phoneScreen());
  final app = AppController(
    database: db,
    services: services,
    promptTemplate: _template,
    adapterFactory: (_, key, headers) => adapter,
  );
  addTearDown(() async {
    app.dispose();
    await db.close();
  });
  await app.initialize();
  await app.saveProvider(
    ProviderConfig(
      id: 'fixture',
      displayName: 'Fixture',
      apiType: ApiType.chatCompletions,
      baseUrl: 'https://fixture.example.com/v1',
      model: 'fixture-model',
      capabilities: ProviderCapabilities(
        tools: true,
        vision: vision,
        contextWindow: 32000,
      ),
      maxOutputTokens: 256,
    ),
  );
  return (app, services);
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

List<ToolResultBlock> _results(AppController app) => [
  for (final message in app.visibleMessages)
    if (message.role == MessageRole.tool)
      ...message.content.whereType<ToolResultBlock>(),
];

void main() {
  test(
    'the model opens an app, navigates three screens and reads back',
    () async {
      final adapter = _Adapter([
        _call('open_app', {'name': 'settings'}),
        _call('read_screen'),
        _call('tap', (ChatRequest r) => {'id': _id(r, 'About phone')}),
        _call('read_screen'),
        _call('tap', (ChatRequest r) => {'id': _id(r, 'Android version')}),
        _call('read_screen'),
        _say((r) {
          final version = RegExp(
            r'\[2\] Text "([^"]+)"',
          ).firstMatch(_lastResult(r))!.group(1);
          return 'This phone runs Android $version.';
        }),
      ]);
      final (app, services) = await _app(adapter);
      final screen = services.screen;
      final approvals = await _approveAll(
        app,
        app.send('Which Android version is this phone on?'),
      );
      expect(app.visibleMessages.last.text, 'This phone runs Android 15.');
      expect(screen.current, 'settings/version');
      expect(_results(app).where((result) => result.isError), isEmpty);
      // Opening, reading and tapping are each approved once for the chat.
      expect(approvals.map((request) => (request.toolName, request.risk)), [
        ('open_app', RiskLevel.action),
        ('read_screen', RiskLevel.sensitive),
        ('tap', RiskLevel.action),
      ]);
      expect(
        approvals.last.details['element'],
        'Button “About phone Pixel fixture”',
      );
      expect(approvals.last.details['app'], 'Settings');
      final prompt = app.conversation!.systemPrompt;
      expect(prompt, contains('## Controlling the screen'));
      expect(prompt, contains('lists visible elements as `[id] type "text"`.'));
      expect(
        prompt,
        contains('Actions return the screen after them when they can'),
      );
      expect(prompt, isNot(contains('includes a screenshot')));
      expect(prompt, isNot(contains('## Shell')));
      expect(services.refreshes, greaterThan(0));
      // One notification session for the whole response, ended after it.
      expect(screen.sessions, 1);
      expect(screen.modelActive, isFalse);
      final tapped = _results(app)
          .expand((result) => result.sideEffects)
          .where((effect) => effect.kind == 'screen_tapped')
          .map((effect) => effect.summary);
      expect(tapped, [
        '“About phone Pixel fixture” · Settings',
        '“Android version 15” · Settings',
      ]);
    },
  );

  test(
    'a Send-like tap needs high-risk confirmation under full permissions',
    () async {
      final adapter = _Adapter([
        _call('open_app', {'name': 'Messages'}),
        _call('read_screen'),
        _call('tap', (ChatRequest r) => {'id': _id(r, 'Send')}),
        _say(_lastResult),
      ]);
      final (app, services) = await _app(adapter);
      await app.savePermissionPolicy(
        const PermissionPolicy(fullPermissions: true),
      );
      final approvals = await _approveAll(
        app,
        app.send('Tell Alex I am on my way'),
        choose: (_) => PermissionChoice.deny,
      );
      final request = approvals.single;
      expect(request.toolName, 'tap');
      expect(request.risk, RiskLevel.high);
      expect(request.choices, [
        PermissionChoice.allowOnce,
        PermissionChoice.deny,
      ]);
      expect(request.details['element'], 'Button “Send”');
      expect(request.target, isNotNull);
      expect(app.visibleMessages.last.text, contains('denied_by_user'));
      expect(services.screen.actions, isEmpty);
      expect(services.screen.current, 'messages');
    },
  );

  test('prompt sections follow what the user enabled', () async {
    final screen = phoneScreen(screenshots: true)..enabledValue = false;
    final adapter = _Adapter([
      _say((_) => 'One.'),
      _call('read_screen'),
      _say((_) => 'Two.'),
    ]);
    final (app, services) = await _app(adapter, screen: screen, vision: true);
    await app.send('Hello');
    final before = app.conversation!.systemPrompt;
    expect(before, contains('## Other apps'));
    expect(before, contains('You cannot see or control other apps'));
    expect(before, isNot(contains('## Shell')));
    // The user enables screen control, screenshots and Termux.
    screen.enabledValue = true;
    services.shell.ready = true;
    await app.saveControlSettings(
      const DeviceControlSettings(screenshots: true),
    );
    screen.show('settings');
    await _approveAll(app, app.send('What is on screen?'));
    final after = app.conversation!.systemPrompt;
    expect(after, contains('## Controlling the screen'));
    expect(after, contains('and includes a screenshot'));
    expect(after, contains('run_shell runs commands in Termux on this phone.'));
    final read = _results(app).last;
    expect(read.attachments.single, isA<ImageBlock>());
    expect(read.content, contains('screenshot: attached, 540x1200'));
    // The tool list offered to the model includes the new tools.
    final offered = adapter.requests.last.tools.map((tool) => tool.name);
    expect(offered, containsAll(['read_screen', 'tap', 'run_shell']));
    expect(
      adapter.requests.first.tools.map((tool) => tool.name),
      isNot(contains('read_screen')),
    );
  });

  test('Stop in the screen-control notification stops the response', () async {
    final adapter = _Adapter([
      _call('open_app', {'name': 'Settings'}),
      _call('read_screen'),
      // The model is still thinking when the user presses Stop.
    ]);
    final (app, services) = await _app(adapter);
    final sending = _approveAll(app, app.send('Look around'));
    while (!(services.screen.modelActive && adapter.requests.length == 3)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    services.screen.takeOver();
    await sending;
    expect(app.isGenerating, isFalse);
    expect(app.visibleMessages.last.status, MessageStatus.stopped);
    expect(services.screen.modelActive, isFalse);
  });

  group('tool-call limit', () {
    test('a turn that controls the screen gets the screen limit', () async {
      final adapter = _Adapter([
        _call('open_app', {'name': 'Settings'}),
        _call('read_screen'),
        // Each tap returns the screen after it, so the model taps on.
        _call('tap', (ChatRequest r) => {'id': _id(r, 'About phone')}),
        _call('tap', (ChatRequest r) => {'id': _id(r, 'Android version')}),
        _say((r) {
          final version = RegExp(
            r'\[2\] Text "([^"]+)"',
          ).firstMatch(_lastResult(r))!.group(1);
          return 'Android $version.';
        }),
        // A later turn without screen tools keeps the usual limit.
        _call('open_app', {'name': 'Messages'}),
        _call('open_app', {'name': 'Settings'}),
        _call('open_app', {'name': 'Messages'}),
      ]);
      final (app, services) = await _app(adapter);
      await app.saveToolSettings(
        const ToolSettings(maxSteps: 2, maxScreenSteps: 5),
      );
      await _approveAll(app, app.send('Which Android version is this?'));
      expect(app.errorCode, isNull);
      expect(app.visibleMessages.last.text, 'Android 15.');
      final results = _results(app);
      expect(results.map((result) => result.toolName), [
        'open_app',
        'read_screen',
        'tap',
        'tap',
      ]);
      expect(results[2].content, contains('screen after the action:'));

      await _approveAll(app, app.send('Open a few apps'));
      expect(app.errorCode, 'toolStepLimit');
      expect(adapter.requests, hasLength(7));
      // open_app now returned the screen, so that response used the screen.
      expect(_results(app).last.content, contains('screen after the action:'));
      expect(services.screen.sessions, 2);
      expect(services.screen.modelActive, isFalse);
    });

    test('Continue goes on from the last results with a new budget', () async {
      final adapter = _Adapter([
        _call('open_app', {'name': 'Settings'}),
        _call('read_screen'),
        _say((r) => 'Seen: ${_lastResult(r).contains('About phone')}'),
      ]);
      final (app, _) = await _app(adapter);
      await app.saveToolSettings(
        const ToolSettings(maxSteps: 1, maxScreenSteps: 1),
      );
      await _approveAll(app, app.send('Look at Settings'));
      expect(app.errorCode, 'toolStepLimit');
      expect(app.canContinueAfterLimit, isTrue);
      expect(app.visibleMessages.last.role, MessageRole.tool);
      await _approveAll(app, app.continueAfterLimit());
      // The model saw what open_app returned, then reached the limit again.
      expect(_lastResult(adapter.requests[1]), contains('"launched":true'));
      expect(app.errorCode, 'toolStepLimit');
      await _approveAll(app, app.continueAfterLimit());
      expect(app.errorCode, isNull);
      expect(app.canContinueAfterLimit, isFalse);
      expect(app.visibleMessages.last.text, 'Seen: true');
      // Nothing ran twice.
      expect(_results(app).map((result) => result.toolName), [
        'open_app',
        'read_screen',
      ]);
    });

    test('Continue is offered only while that response is shown', () async {
      final adapter = _Adapter([
        _call('open_app', {'name': 'Settings'}),
      ]);
      final (app, _) = await _app(adapter);
      await app.saveToolSettings(const ToolSettings(maxSteps: 1));
      await _approveAll(app, app.send('Open Settings'));
      expect(app.canContinueAfterLimit, isTrue);
      await app.rewind(app.visibleMessages.first);
      expect(app.canContinueAfterLimit, isFalse);
      await app.continueAfterLimit();
      expect(adapter.requests, hasLength(1));
    });
  });

  group('screenshots of deleted chats', () {
    Future<(AppController, _Services, String)> chatWithScreenshot({
      bool incognito = false,
    }) async {
      final screen = phoneScreen(screenshots: true)..show('settings');
      final adapter = _Adapter([
        _call('read_screen'),
        _say((_) => 'Settings is open.'),
      ]);
      final (app, services) = await _app(adapter, screen: screen, vision: true);
      await app.saveControlSettings(
        const DeviceControlSettings(screenshots: true),
      );
      if (incognito) await app.newChat(incognito: true);
      await _approveAll(app, app.send('What is on screen?'));
      final image = _results(app).single.attachments.single as ImageBlock;
      return (app, services, image.path);
    }

    test('are deleted with the chat', () async {
      final (app, services, path) = await chatWithScreenshot();
      expect(path, startsWith('attachments/screen-'));
      await app.deleteConversation(app.conversation!.id);
      expect(services.workspace.removed, [path]);
    });

    test(
      'stay when the setting is off, unless the chat was incognito',
      () async {
        final (app, services, _) = await chatWithScreenshot();
        await app.saveControlSettings(
          const DeviceControlSettings(deleteScreenshotsWithChat: false),
        );
        await app.deleteConversation(app.conversation!.id);
        expect(services.workspace.removed, isEmpty);

        final (private, privateServices, path) = await chatWithScreenshot(
          incognito: true,
        );
        await private.saveControlSettings(
          const DeviceControlSettings(deleteScreenshotsWithChat: false),
        );
        await private.newChat();
        expect(privateServices.workspace.removed, [path]);
      },
    );

    test('a rewind that deletes later messages deletes their screenshots, '
        'but not ones another message still uses', () async {
      final (app, services, path) = await chatWithScreenshot();
      final first = app.visibleMessages.first;
      // Another chat refers to the same file.
      final now = DateTime.now();
      await app.chats.createConversation(
        Conversation(
          id: 'other',
          createdAt: now,
          updatedAt: now,
          systemPrompt: '',
        ),
      );
      await app.chats.saveMessage(
        ChatMessage(
          id: 'other-message',
          conversationId: 'other',
          role: MessageRole.user,
          content: [ImageBlock(path: path, mimeType: 'image/jpeg')],
          createdAt: now,
        ),
      );
      await app.rewind(first, deleteAfter: true);
      expect(app.visibleMessages, hasLength(1));
      expect(services.workspace.removed, isEmpty);
      await app.chats.deleteConversation('other');
      final (again, againServices, second) = await chatWithScreenshot();
      await again.rewind(again.visibleMessages.first, deleteAfter: true);
      expect(againServices.workspace.removed, [second]);
    });
  });
}
