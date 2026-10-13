import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/app/app_controller.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/permissions/permission_gate.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/data/database.dart';
import 'package:tako/platform/services.dart';

class FakeServices extends PlatformServices {
  final secrets = <String, String>{};
  Completer<DeviceContext>? nextSnapshot;
  int snapshots = 0;

  @override
  Future<DeviceContext> deviceContext() async {
    snapshots++;
    final delayed = nextSnapshot;
    nextSnapshot = null;
    return delayed == null
        ? DeviceContext(model: 'device-$snapshots', network: 'wifi')
        : await delayed.future;
  }

  @override
  Future<String?> readSecret(String reference) async => secrets[reference];
  @override
  Future<void> writeSecret(String reference, String? value) async {
    if (value == null) {
      secrets.remove(reference);
    } else {
      secrets[reference] = value;
    }
  }
}

class FakeAdapter implements ProviderAdapter {
  final requests = <ChatRequest>[];
  List<ProviderEvent> events = const [
    TextDelta('A useful answer'),
    Done('stop'),
  ];
  Completer<void>? started;
  bool waitForStop = false;
  List<ModelInfo> models = [];
  Completer<List<ModelInfo>>? pendingModels;
  bool failModels = false;
  int modelFetches = 0;

  @override
  Future<List<ModelInfo>> listModels({CancelToken? cancel}) async {
    modelFetches++;
    if (failModels) throw StateError('offline');
    return pendingModels == null ? models : await pendingModels!.future;
  }

  @override
  Stream<ProviderEvent> send(
    ChatRequest request, {
    required CancelToken cancel,
  }) async* {
    requests.add(request);
    started?.complete();
    for (final event in events) {
      if (cancel.isCancelled) return;
      yield event;
    }
    if (waitForStop) await cancel.whenCancelled;
  }
}

ProviderConfig config({String model = 'model-1', int context = 32768}) =>
    ProviderConfig(
      id: 'local',
      displayName: 'Local server',
      apiType: ApiType.chatCompletions,
      baseUrl: 'http://127.0.0.1:8080',
      model: model,
      capabilities: ProviderCapabilities(contextWindow: context),
      maxOutputTokens: 256,
    );

void main() {
  late AppDatabase database;
  late FakeServices services;
  late FakeAdapter adapter;
  late AppController app;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    services = FakeServices();
    adapter = FakeAdapter();
    app = AppController(
      titleGenerator: (_, _, _) async => null,
      database: database,
      services: services,
      promptTemplate:
          '{{provider_name}} on {{device_model}}{{#full_permissions}} full permissions{{/full_permissions}}{{#skip_high_risk_confirmations}} skip confirmations{{/skip_high_risk_confirmations}}',
      adapterFactory: (_, key, headers) => adapter,
    );
    await app.initialize();
    await app.saveProvider(config());
  });
  tearDown(() async {
    app.dispose();
    await database.close();
  });

  test(
    'automatic discovery coalesces and preserves independent selections',
    () async {
      await app.refreshProviderModels();
      adapter.models = const [
        ModelInfo(id: 'gpt-6.1-sol'),
        ModelInfo(id: 'claude-haiku-5-5'),
        ModelInfo(id: 'gpt-6.1-sol'),
      ];
      const savedHaiku = ModelProfile(
        id: 'claude-haiku-5-5',
        maxOutputTokens: 12000,
        reasoningMode: ReasoningMode.adaptive,
        reasoningEffort: 'xhigh',
        capabilities: ProviderCapabilities(
          tools: true,
          vision: true,
          reasoning: true,
        ),
      );
      final cpa = config().copyWith(
        apiType: ApiType.messages,
        autoRouteModels: true,
        model: savedHaiku.id,
        models: [savedHaiku],
      );
      await app.saveProvider(cpa, key: 'secure-test-key');
      await app.refreshProviderModels(providerId: cpa.id);
      final fetched = app.providers.single;
      expect(fetched.models, hasLength(2));
      expect(fetched.models.first.toJson(), savedHaiku.toJson());
      expect(app.selectedProvider!.model, 'claude-haiku-5-5');
      expect(app.remoteAgentProvider!.model, 'claude-haiku-5-5');
      await app.selectProvider(cpa.id, model: 'gpt-6.1-sol');
      expect(app.selectedProvider!.apiType, ApiType.responses);
      expect(app.selectedProvider!.modelDisplayName, 'GPT 6.1 Sol');
      expect(app.remoteAgentProvider!.apiType, ApiType.messages);
      expect(app.remoteAgentProvider!.reasoningEffort, 'xhigh');
      final before = adapter.modelFetches;
      adapter.pendingModels = Completer<List<ModelInfo>>();
      final first = app.refreshProviderModels(force: true);
      final second = app.refreshProviderModels(force: true);
      await Future<void>.delayed(Duration.zero);
      expect(adapter.modelFetches, before + 1);
      adapter.pendingModels!.complete(const [ModelInfo(id: 'gpt-6-sol')]);
      await Future.wait([first, second]);
      expect(app.providers.single.models, hasLength(3));
      expect(app.selectedProvider!.model, 'gpt-6.1-sol');
      expect(services.secrets.values, contains('secure-test-key'));
      expect(
        app.providers.single.toJson().toString(),
        isNot(contains('secure-test-key')),
      );
    },
  );
  test(
    'permission modes refresh a cached prompt without losing the chat',
    () async {
      await app.send('First message');
      final id = app.conversation!.id;
      final first = app.conversation!.systemPrompt;
      await app.savePermissionPolicy(
        const PermissionPolicy(
          fullPermissions: true,
          skipHighRiskConfirmations: true,
          overrides: {'tap': ToolPermission.deny},
        ),
      );
      await app.send('Second message');
      expect(app.conversation!.id, id);
      expect(app.conversation!.systemPrompt, isNot(first));
      expect(adapter.requests.last.systemPrompt, contains('full permissions'));
      expect(
        adapter.requests.last.systemPrompt,
        contains('skip confirmations'),
      );
      expect(app.permissionGate.policy.overrides['tap'], ToolPermission.deny);
      final changed = app.conversation!.systemPrompt;
      await app.savePermissionPolicy(app.permissionGate.policy);
      await app.send('Third message');
      expect(app.conversation!.systemPrompt, changed);
      await app.savePermissionPolicy(const PermissionPolicy());
      await app.send('Fourth message');
      expect(
        app.conversation!.systemPrompt,
        isNot(contains('full permissions')),
      );
      expect(
        app.conversation!.systemPrompt,
        isNot(contains('skip confirmations')),
      );
    },
  );

  test('offline and empty model lists never erase saved models', () async {
    await app.refreshProviderModels();
    final previous = app.providers.single.toJson();
    adapter.failModels = true;
    await app.refreshProviderModels(force: true);
    expect(app.providers.single.toJson(), previous);
    expect(app.modelFetchErrors, containsPair('local', 'connection_failed'));
    adapter.failModels = false;
    await app.refreshProviderModels(force: true);
    expect(app.providers.single.toJson(), previous);
    expect(app.modelFetchErrors, containsPair('local', 'no_models'));
  });

  test(
    'model discovery waits for generation to finish before applying',
    () async {
      await app.refreshProviderModels();
      adapter.pendingModels = Completer<List<ModelInfo>>();
      final fetching = app.refreshProviderModels(force: true);
      adapter.started = Completer<void>();
      adapter.waitForStop = true;
      adapter.events = const [TextDelta('Working')];
      final sending = app.send('Keep the selected model for this request');
      await adapter.started!.future;
      adapter.pendingModels!.complete(const [ModelInfo(id: 'gpt-6.1-sol')]);
      await fetching;
      expect(app.providers.single.models, hasLength(1));
      app.stop();
      await sending;
      await app.refreshProviderModels();
      expect(app.providers.single.models, hasLength(2));
      expect(app.selectedProvider!.model, 'model-1');
    },
  );

  test('late discovery cannot overwrite a changed connection', () async {
    await app.refreshProviderModels();
    adapter.pendingModels = Completer<List<ModelInfo>>();
    final fetching = app.refreshProviderModels(force: true);
    await app.saveProvider(
      config().copyWith(
        baseUrl: 'https://changed.example/v1',
        autoFetchModels: false,
      ),
    );
    adapter.pendingModels!.complete(const [ModelInfo(id: 'old-server-model')]);
    await fetching;
    expect(app.providers.single.baseUrl, 'https://changed.example/v1');
    expect(app.providers.single.models, hasLength(1));
  });

  test(
    'send preserves frozen prompt and context; edits, regen and rewind keep branches',
    () async {
      await app.send('First message');
      final firstUser = app.visibleMessages.first;
      final firstAnswer = app.visibleMessages.last;
      final prompt = app.conversation!.systemPrompt;
      await app.send('Follow up');
      expect(adapter.requests.last.systemPrompt, prompt);
      expect(
        adapter.requests.last.messages.first.contextEnvelope,
        firstUser.contextEnvelope,
      );
      expect(app.visibleMessages.length, 4);
      await app.regenerate(firstAnswer);
      final secondAnswer = app.visibleMessages.last;
      expect(app.tree.siblingsOf(secondAnswer.id), hasLength(2));
      expect(app.visibleMessages, hasLength(2));
      await app.switchBranch(firstAnswer);
      expect(app.visibleMessages, hasLength(4));
      await app.send('Edited first message', editing: firstUser);
      expect(app.tree.siblingsOf(app.visibleMessages.first.id), hasLength(2));
      expect(app.visibleMessages.first.parentId, isNull);
      await app.rewind(firstUser);
      expect(app.visibleMessages, hasLength(1));
      await app.switchBranch(firstAnswer);
      expect(app.visibleMessages, hasLength(4));
      final id = app.conversation!.id;
      await app.newChat();
      await app.openConversation(id);
      expect(app.visibleMessages, hasLength(4));
      expect(app.conversation!.systemPrompt, prompt);
    },
  );

  test(
    'Stop during device preflight prevents message or conversation creation',
    () async {
      final pending = Completer<DeviceContext>();
      services.nextSnapshot = pending;
      final sending = app.send('Cancel before persistence');
      expect(app.busy, isTrue);
      app.stop();
      await sending;
      pending.complete(const DeviceContext());
      expect(app.busy, isFalse);
      expect(app.messages, isEmpty);
      expect(app.conversations, isEmpty);
      expect(adapter.requests, isEmpty);
      expect(app.errorCode, isNull);
    },
  );

  test(
    'Stop preserves partial output and Retry creates an assistant sibling',
    () async {
      adapter.events = const [TextDelta('Partial')];
      adapter.waitForStop = true;
      adapter.started = Completer<void>();
      final sending = app.send('Question');
      await adapter.started!.future;
      await Future<void>.delayed(Duration.zero);
      app.stop();
      await sending;
      final stopped = app.visibleMessages.last;
      expect(stopped.status, MessageStatus.stopped);
      expect(stopped.text, 'Partial');
      adapter.started = null;
      adapter.waitForStop = false;
      adapter.events = const [TextDelta('Complete'), Done('stop')];
      await app.regenerate(stopped);
      expect(app.visibleMessages.last.text, 'Complete');
      expect(app.tree.siblingsOf(stopped.id), hasLength(2));
    },
  );

  test(
    'navigation and provider mutation cannot replace a running stream tree',
    () async {
      adapter.events = const [TextDelta('Partial')];
      adapter.waitForStop = true;
      adapter.started = Completer<void>();
      final sending = app.send('Question');
      await adapter.started!.future;
      final id = app.conversation!.id;
      await Future.wait([
        app.newChat(),
        app.saveProvider(config(model: 'changed')),
        app.deleteConversation(id),
      ]);
      expect(app.conversation!.id, id);
      expect(app.selectedProvider!.model, 'model-1');
      app.stop();
      await sending;
      expect((await app.chats.getConversation(id))!.id, id);
    },
  );

  test(
    'unchanged provider settings and key edits keep prompt; model edits refresh it',
    () async {
      await app.send('Question');
      final prompt = app.conversation!.systemPrompt;
      await app.saveProvider(config(), key: 'test-only-value');
      expect(app.conversation!.systemPrompt, prompt);
      expect(
        app.providers.single.toJson().values,
        isNot(contains('test-only-value')),
      );
      await app.saveProvider(config(model: 'model-2'));
      expect(app.conversation!.systemPrompt, contains('model-2'));
      expect(app.conversation!.systemPrompt, isNot(prompt));
      await app.send('Next question');
      expect(app.visibleMessages.last.model, 'model-2');
    },
  );

  test('provider failures persist partial output and support retry', () async {
    adapter.events = const [
      TextDelta('Partial'),
      ProviderError('Unavailable', statusCode: 503),
    ];
    await app.send('Question');
    final failed = app.visibleMessages.last;
    expect(failed.status, MessageStatus.error);
    expect(failed.error, 'HTTP 503: Unavailable');
    expect(failed.text, 'Partial');
    adapter.events = const [TextDelta('Recovered'), Done('stop')];
    await app.regenerate(failed);
    expect(app.visibleMessages.last.status, MessageStatus.done);
    expect(app.tree.siblingsOf(failed.id), hasLength(2));
  });

  test(
    'thinking-only and unsolicited tool results do not become dangling history',
    () async {
      adapter.events = const [ReasoningDelta('Only thinking'), Done('stop')];
      await app.send('Question');
      expect(app.visibleMessages.last.error, 'emptyResponse');
      adapter.events = const [
        ToolCallStart('call-1', 'file_read'),
        ToolCallArgsDelta('call-1', '{}'),
        ToolCallEnd('call-1'),
        Done('tool_calls'),
      ];
      await app.send('Another question');
      expect(app.visibleMessages.last.error, 'toolsLater');
      expect(adapter.requests.last.replayOpaqueReasoning, isFalse);
      adapter.events = const [TextDelta('Answer'), Done('stop')];
      await app.send('Final question');
      expect(
        adapter.requests.last.messages.any(
          (m) => m.content.any((b) => b is ToolCallBlock),
        ),
        isFalse,
      );
      expect(adapter.requests.last.replayOpaqueReasoning, isFalse);
    },
  );

  test('oversized latest turn is retained locally but never sent', () async {
    await app.saveProvider(config(context: 300));
    await app.send('A very long message ' * 100);
    expect(app.errorCode, 'contextTooLarge');
    expect(app.visibleMessages.single.role, MessageRole.user);
    expect(adapter.requests, isEmpty);
  });

  test(
    'multiple models share a provider, retain selection and use their own budgets',
    () async {
      await app.saveProvider(
        config().copyWith(
          models: const [
            ModelProfile(
              id: 'model-1',
              maxOutputTokens: 256,
              capabilities: ProviderCapabilities(contextWindow: 32768),
            ),
            ModelProfile(
              id: 'model-2',
              maxOutputTokens: 500,
              capabilities: ProviderCapabilities(contextWindow: 64000),
            ),
          ],
        ),
        key: 'test-credential',
      );
      await app.selectProvider('local', model: 'model-2');
      await app.send('First');
      final conversationId = app.conversation!.id;
      expect(app.conversation!.model, 'model-2');
      expect(adapter.requests.last.maxTokens, 500);
      expect(app.providers, hasLength(1));
      expect(services.secrets, hasLength(1));
      await app.selectProvider('local', model: 'model-1');
      await app.send('Next');
      expect(adapter.requests.last.maxTokens, 256);
      expect(app.visibleMessages.first.model, 'model-2');
      expect(app.visibleMessages.last.model, 'model-1');
      await app.newChat();
      await app.selectProvider('local', model: 'model-2');
      await app.initialize();
      expect(app.selectedProvider!.model, 'model-2');
      await app.openConversation(conversationId);
      expect(app.selectedProvider!.model, 'model-1');
      expect(app.selectedProvider!.maxOutputTokens, 256);
    },
  );

  test(
    'fast streamed fragments are coalesced without losing final text',
    () async {
      adapter.events = [
        for (var i = 0; i < 500; i++) const TextDelta('x'),
        const Done('stop'),
      ];
      var notifications = 0;
      app.addListener(() => notifications++);
      await app.send('Burst');
      expect(app.visibleMessages.last.text, 'x' * 500);
      expect(notifications, lessThan(40));
      expect(identical(app.tree, app.tree), isTrue);
    },
  );
}
