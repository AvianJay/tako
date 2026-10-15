import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/app/app_controller.dart';
import 'package:tako/core/browser/browser_capability.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/files/workspace.dart';
import 'package:tako/core/notifications/notification_capability.dart';
import 'package:tako/core/on_device/on_device_capability.dart';
import 'package:tako/core/permissions/permission_gate.dart';
import 'package:tako/core/providers/hosted_search_probe.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/core/screen/screen_capability.dart';
import 'package:tako/core/shell/shell_capability.dart';
import 'package:tako/core/shortcuts/shortcuts_capability.dart';
import 'package:tako/core/tools/tool_settings.dart';
import 'package:tako/data/database.dart';
import 'package:tako/platform/app_services.dart';
import 'package:tako/platform/device_tools_capability.dart';
import 'package:tako/platform/media_attachment_capability.dart';

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

class _Services implements AppServices {
  final secrets = <String, String>{};
  final writes = <String>[];
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
  Future<DeviceContext> deviceContext() async => const DeviceContext();
  @override
  Future<String?> readSecret(String reference) async => secrets[reference];
  @override
  Future<void> writeSecret(String reference, String? value) async {
    writes.add(reference);
    if (value == null) {
      secrets.remove(reference);
    } else {
      secrets[reference] = value;
    }
  }

  @override
  Future<Map<String, String>> readHeaders(String? reference) async =>
      reference == null ? {} : {'x-fixture': 'stored-fixture-header'};
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
  final BrowserCapability browser = UnavailableBrowser();
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
  Future<String?> pickTextFile({required int maxBytes}) async => null;
  @override
  Future<void> shareTextFile(String name, String text) async {}

  @override
  Future<void> shareImageFile(String name, Uint8List image) async {}
}

class _Adapter implements ProviderAdapter {
  List<ProviderEvent> events = const [
    HostedSearchEvent(success: true),
    Done('stop'),
  ];
  final requests = <ChatRequest>[];
  final started = Completer<void>();
  bool waitForCancel = false;
  Object? thrown;
  @override
  Future<List<ModelInfo>> listModels({CancelToken? cancel}) async => [];
  @override
  Stream<ProviderEvent> send(
    ChatRequest request, {
    required CancelToken cancel,
  }) async* {
    requests.add(request);
    if (!started.isCompleted) started.complete();
    for (final event in events) {
      if (cancel.isCancelled) return;
      yield event;
    }
    if (thrown != null) throw thrown!;
    if (waitForCancel) await cancel.whenCancelled;
  }
}

ProviderConfig _config({ApiType api = ApiType.responses}) => ProviderConfig(
  id: 'fixture',
  displayName: 'Proxy fixture',
  apiType: api,
  baseUrl: 'https://proxy.invalid/v1',
  model: 'fixture-model',
  apiKeyRef: 'fixture-key',
  extraHeadersRef: 'fixture-headers',
  capabilities: const ProviderCapabilities(contextWindow: 32000),
  reasoningMode: ReasoningMode.adaptive,
);

Future<PermissionRequest> _approval(AppController app) {
  if (app.pendingApproval case final request?) return Future.value(request);
  final ready = Completer<PermissionRequest>();
  late void Function() listener;
  listener = () {
    if (app.pendingApproval case final request?) {
      app.removeListener(listener);
      ready.complete(request);
    }
  };
  app.addListener(listener);
  return ready.future.timeout(const Duration(seconds: 5));
}

void main() {
  late AppDatabase database;
  late AppController app;
  late _Services services;
  late _Adapter adapter;
  late ProviderConfig capturedConfig;
  String? capturedKey;
  Map<String, String>? capturedHeaders;
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    services = _Services();
    adapter = _Adapter();
    app = AppController(
      titleGenerator: (_, _, _) async => null,
      database: database,
      services: services,
      promptTemplate: 'Private configured system prompt',
      adapterFactory: (config, key, headers) {
        capturedConfig = config;
        capturedKey = key;
        capturedHeaders = headers;
        return adapter;
      },
    );
    await app.initialize();
  });
  tearDown(() async {
    app.dispose();
    await database.close();
  });

  test(
    'forces one isolated public native search without saving config or secrets',
    () async {
      final config = _config();
      final before = await app.settings.readAll();
      app.errorCode = 'existing-error';
      app.providerError = 'existing-provider-error';
      app.draftAttachments = const [
        FileBlock(
          path: 'private.txt',
          name: 'private.txt',
          mimeType: 'text/plain',
        ),
      ];
      final result = await app.probeHostedSearch(
        config,
        temporaryKey: 'temporary-fixture-key',
        temporaryHeaders: {'x-fixture': 'temporary-fixture-header'},
        cancel: CancelToken(),
      );
      expect(result.status, HostedSearchProbeStatus.supported);
      expect(capturedConfig.capabilities.tools, isTrue);
      expect(capturedConfig.capabilities.builtInWebSearch, isTrue);
      expect(capturedConfig.capabilities.allowCustomSearchEndpoint, isTrue);
      expect(capturedConfig.reasoningMode, ReasoningMode.off);
      expect(capturedConfig.maxOutputTokens, 512);
      expect(capturedKey, 'temporary-fixture-key');
      expect(capturedHeaders, {'x-fixture': 'temporary-fixture-header'});
      final request = adapter.requests.single;
      expect(request.builtInWebSearch, isTrue);
      expect(request.forceBuiltInWebSearch, isTrue);
      expect(request.replayOpaqueReasoning, isFalse);
      expect(request.tools, isEmpty);
      expect(request.maxTokens, 512);
      expect(request.messages, hasLength(1));
      expect(request.messages.single.content, hasLength(1));
      expect(
        request.messages.single.text,
        contains('official Flutter website'),
      );
      expect(request.messages.single.contextEnvelope, isNull);
      expect(request.systemPrompt, isNot(contains('Private configured')));
      expect(config.capabilities.builtInWebSearch, isFalse);
      expect(config.capabilities.allowCustomSearchEndpoint, isFalse);
      expect(app.providers, isEmpty);
      expect(app.conversations, isEmpty);
      expect(app.messages, isEmpty);
      expect(app.draftAttachments, hasLength(1));
      expect(app.errorCode, 'existing-error');
      expect(app.providerError, 'existing-provider-error');
      expect(await app.settings.readAll(), before);
      expect(services.writes, isEmpty);
      expect(app.busy, isFalse);
      final record = (await app.audit.list()).single;
      expect(record.conversationId, startsWith('hosted-search-probe-'));
      expect(record.finishedAt, isNotNull);
      expect(record.resultSummary, '{"status":"supported"}');
      expect(record.arguments, isNot(contains('temporary-fixture')));
      expect(record.isError, isFalse);
    },
  );

  test(
    'uses existing secure references and honors explicit credential removal',
    () async {
      services.secrets['fixture-key'] = 'stored-fixture-key';
      await app.probeHostedSearch(_config(), cancel: CancelToken());
      expect(capturedKey, 'stored-fixture-key');
      expect(capturedHeaders, {'x-fixture': 'stored-fixture-header'});
      await app.probeHostedSearch(
        _config(),
        temporaryKey: 'ignored',
        temporaryHeaders: {'ignored': 'ignored'},
        removeKey: true,
        removeHeaders: true,
        cancel: CancelToken(),
      );
      expect(capturedKey, isNull);
      expect(capturedHeaders, isEmpty);
      expect(services.secrets['fixture-key'], 'stored-fixture-key');
      expect(services.writes, isEmpty);
    },
  );

  test(
    'text claims and citations without native receipts are not proof',
    () async {
      adapter.events = const [
        TextDelta('I searched the web: [Flutter](https://flutter.dev).'),
        ProviderStateMetadata(
          sourceApi: 'responses',
          content: [
            {'type': 'web_search_call', 'status': 'in_progress'},
          ],
        ),
        Done('stop'),
      ];
      final result = await app.probeHostedSearch(
        _config(),
        cancel: CancelToken(),
      );
      expect(result.status, HostedSearchProbeStatus.notObserved);
    },
  );

  for (final events in <String, List<ProviderEvent>>{
    'failed native result': [
      const HostedSearchEvent(success: false),
      const Done('stop'),
    ],
    'later failed native result': [
      const HostedSearchEvent(success: true),
      const HostedSearchEvent(success: false),
      const Done('stop'),
    ],
    'missing terminal completion': [const HostedSearchEvent(success: true)],
    'truncated completion': [
      const HostedSearchEvent(success: true),
      const Done('max_tokens'),
    ],
    'paused completion': [
      const HostedSearchEvent(success: true),
      const Done('pause_turn'),
    ],
    'unknown completion': [
      const HostedSearchEvent(success: true),
      const Done(null),
    ],
  }.entries) {
    test('${events.key} cannot be reported as supported', () async {
      adapter.events = events.value;
      final result = await app.probeHostedSearch(
        _config(),
        cancel: CancelToken(),
      );
      expect(result.status, HostedSearchProbeStatus.failed);
    });
  }

  test(
    'later provider error wins and its body never reaches result or audit',
    () async {
      adapter.events = const [
        HostedSearchEvent(success: true),
        ProviderError('private credential value', statusCode: 502),
      ];
      final result = await app.probeHostedSearch(
        _config(),
        cancel: CancelToken(),
      );
      expect(result.status, HostedSearchProbeStatus.failed);
      expect(result.statusCode, 502);
      final record = (await app.audit.list()).single;
      expect(jsonDecode(record.resultSummary), {
        'status': 'failed',
        'http_status': 502,
      });
      expect(record.resultSummary, isNot(contains('private credential')));
      expect(app.providerError, isNull);
    },
  );

  test('thrown stream error is reduced to a safe failure', () async {
    adapter.thrown = StateError('private credentials');
    final result = await app.probeHostedSearch(
      _config(),
      cancel: CancelToken(),
    );
    expect(result.status, HostedSearchProbeStatus.failed);
    expect(
      (await app.audit.list()).single.resultSummary,
      '{"status":"failed"}',
    );
  });

  test(
    'unsupported protocol is audited without sending or prompting',
    () async {
      final result = await app.probeHostedSearch(
        _config(api: ApiType.chatCompletions),
        cancel: CancelToken(),
      );
      expect(result.status, HostedSearchProbeStatus.unsupportedProtocol);
      expect(adapter.requests, isEmpty);
      expect(app.pendingApproval, isNull);
      expect((await app.audit.list()).single.finishedAt, isNotNull);
    },
  );

  for (final settings in [
    const ToolSettings(enabled: false),
    const ToolSettings(disabled: {'web_search'}),
  ]) {
    test('disabled tools or search rejects probe before network', () async {
      app.toolSettings = settings;
      final result = await app.probeHostedSearch(
        _config(),
        cancel: CancelToken(),
      );
      expect(result.status, HostedSearchProbeStatus.disabled);
      expect(adapter.requests, isEmpty);
      expect((await app.audit.list()).single.finishedAt, isNotNull);
    });
  }

  test('per-tool deny policy is honored and audited', () async {
    app.permissionGate.policy = const PermissionPolicy(
      overrides: {'web_search': ToolPermission.deny},
    );
    final result = await app.probeHostedSearch(
      _config(),
      cancel: CancelToken(),
    );
    expect(result.status, HostedSearchProbeStatus.denied);
    expect(adapter.requests, isEmpty);
    expect((await app.audit.list()).single.decision, 'denied_by_policy');
  });

  test('ask policy waits, and timeout starts only after approval', () async {
    app.permissionGate.policy = const PermissionPolicy(
      overrides: {'web_search': ToolPermission.ask},
    );
    final cancel = CancelToken();
    final pending = app.probeHostedSearch(
      _config(),
      cancel: cancel,
      timeout: const Duration(milliseconds: 20),
    );
    final request = await _approval(app);
    expect(request.arguments['mode'], 'hosted_search_probe');
    expect(request.arguments['max_calls'], 1);
    expect(adapter.requests, isEmpty);
    expect(app.busy, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 45));
    expect(cancel.isCancelled, isFalse);
    expect(app.pendingApproval, isNotNull);
    app.permissionGate.decide(PermissionChoice.allowOnce);
    expect((await pending).status, HostedSearchProbeStatus.supported);
    expect(app.pendingApproval, isNull);
    expect(
      app.permissionGate.policy.overrides['web_search'],
      ToolPermission.ask,
    );
  });

  test('user can deny or stop pending approval', () async {
    app.permissionGate.policy = const PermissionPolicy(
      overrides: {'web_search': ToolPermission.ask},
    );
    var pending = app.probeHostedSearch(_config(), cancel: CancelToken());
    await _approval(app);
    app.permissionGate.decide(PermissionChoice.deny);
    expect((await pending).status, HostedSearchProbeStatus.denied);
    pending = app.probeHostedSearch(_config(), cancel: CancelToken());
    await _approval(app);
    app.stop();
    expect((await pending).status, HostedSearchProbeStatus.cancelled);
    expect(app.pendingApproval, isNull);
    expect(app.busy, isFalse);
    expect(adapter.requests, isEmpty);
  });

  test('request timeout cancels a stalled stream and releases guard', () async {
    adapter.events = [];
    adapter.waitForCancel = true;
    final cancel = CancelToken();
    final result = await app.probeHostedSearch(
      _config(),
      cancel: cancel,
      timeout: const Duration(milliseconds: 20),
    );
    expect(result.status, HostedSearchProbeStatus.timedOut);
    expect(cancel.isCancelled, isTrue);
    expect(app.busy, isFalse);
    expect(
      (await app.audit.list()).single.resultSummary,
      '{"status":"timedOut"}',
    );
  });

  test(
    'Stop cancels stream while a second probe is rejected and audited',
    () async {
      adapter.events = [];
      adapter.waitForCancel = true;
      final cancel = CancelToken();
      final pending = app.probeHostedSearch(_config(), cancel: cancel);
      await adapter.started.future;
      final other = await app.probeHostedSearch(
        _config(),
        cancel: CancelToken(),
      );
      expect(other.status, HostedSearchProbeStatus.busy);
      expect(app.busy, isTrue);
      expect(cancel.isCancelled, isFalse);
      await app.saveProvider(_config());
      expect(app.providers, isEmpty);
      app.stop();
      expect((await pending).status, HostedSearchProbeStatus.cancelled);
      expect(cancel.isCancelled, isTrue);
      expect(app.busy, isFalse);
      expect(await app.audit.list(), hasLength(2));
    },
  );

  test('pre-cancelled probe is audited without network', () async {
    final result = await app.probeHostedSearch(
      _config(),
      cancel: CancelToken()..cancel(),
    );
    expect(result.status, HostedSearchProbeStatus.cancelled);
    expect(adapter.requests, isEmpty);
    expect((await app.audit.list()).single.finishedAt, isNotNull);
  });

  test(
    'existing conversation and persisted history survive probe unchanged',
    () async {
      await app.saveProvider(_config());
      adapter.events = const [
        TextDelta('Private existing response'),
        Done('stop'),
      ];
      await app.send('Private user message');
      final beforeConversation = app.conversation;
      final beforeMessages = jsonEncode(
        app.messages.map((m) => m.toJson()).toList(),
      );
      final beforeSettings = await app.settings.readAll();
      final beforeProviders = jsonEncode(
        (await app.providerRepository.list()).map((p) => p.toJson()).toList(),
      );
      adapter.events = const [HostedSearchEvent(success: true), Done('stop')];
      await app.probeHostedSearch(_config(), cancel: CancelToken());
      expect(app.conversation, same(beforeConversation));
      expect(
        jsonEncode(app.messages.map((m) => m.toJson()).toList()),
        beforeMessages,
      );
      expect(
        jsonEncode(
          (await app.chats.getMessages(
            beforeConversation!.id,
          )).map((m) => m.toJson()).toList(),
        ),
        beforeMessages,
      );
      expect(await app.settings.readAll(), beforeSettings);
      expect(
        jsonEncode(
          (await app.providerRepository.list()).map((p) => p.toJson()).toList(),
        ),
        beforeProviders,
      );
      expect(
        adapter.requests.last.messages.single.text,
        isNot(contains('Private')),
      );
      expect(adapter.requests.last.systemPrompt, isNot(contains('Private')));
    },
  );
}
