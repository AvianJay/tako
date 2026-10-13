import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tako/app/app_controller.dart';
import 'package:tako/core/browser/browser_capability.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/files/workspace.dart';
import 'package:tako/core/notifications/notification_capability.dart';
import 'package:tako/core/on_device/on_device_capability.dart';
import 'package:tako/core/permissions/permission_gate.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/core/screen/device_control_settings.dart';
import 'package:tako/core/screen/screen_capability.dart';
import 'package:tako/core/shell/shell_capability.dart';
import 'package:tako/core/shortcuts/shortcuts_capability.dart';
import 'package:tako/core/tools/tool.dart';
import 'package:tako/core/tools/tool_settings.dart';
import 'package:tako/core/util/json.dart';
import 'package:tako/data/database.dart';
import 'package:tako/platform/app_services.dart';
import 'package:tako/platform/capabilities.dart';
import 'package:tako/platform/device_tools_capability.dart';
import 'package:tako/platform/media_attachment_capability.dart';

import '../screen/fake_screen.dart';

class _Workspace implements WorkspaceCapability {
  @override
  bool get isAvailable => false;
  @override
  Future<List<ContentBlock>> hydrateBlocks(
    List<ContentBlock> blocks, {
    required bool vision,
    CancelToken? cancel,
  }) async => [for (final block in blocks) _hydrate(block)];

  ContentBlock _hydrate(ContentBlock block) => switch (block) {
    ImageBlock() => block.withData('AQ=='),
    ToolResultBlock() => ToolResultBlock(
      toolCallId: block.toolCallId,
      toolName: block.toolName,
      content: block.content,
      isError: block.isError,
      sideEffects: block.sideEffects,
      attachments: [for (final item in block.attachments) _hydrate(item)],
    ),
    _ => block,
  };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// No native services, filesystem, HTTP, or secrets are used by these tests.
class _Services implements AppServices {
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
}

class _Available implements Capability {
  @override
  bool get isAvailable => true;
}

class _RemoteServices extends _Services {
  _RemoteServices(this.remote);
  final FakeScreen remote;
  @override
  ScreenCapability get screen => remote;
}

class _Tool extends Tool {
  _Tool({this.risk = RiskLevel.safe, this.onRun, this.imageResult = false});
  final RiskLevel risk;
  final bool imageResult;
  final Future<ToolResult> Function(ToolContext)? onRun;
  final inputs = <String>[];
  @override
  String get name => 'fixture_tool';
  @override
  String get description => 'Return a fixture value.';
  @override
  Capability get requires => _Available();
  @override
  JsonMap get schema => const {
    'type': 'object',
    'properties': {
      'text': {'type': 'string'},
    },
    'required': ['text'],
    'additionalProperties': false,
  };
  @override
  RiskLevel riskFor(JsonMap args, ToolContext ctx) => risk;
  @override
  Future<ToolResult> run(JsonMap args, ToolContext ctx) async {
    ctx.cancel.throwIfCancelled();
    inputs.add(args['text']! as String);
    if (onRun != null) return onRun!(ctx);
    return ToolResult(
      content: jsonEncode({'value': args['text']}),
      attachments: imageResult && args['text'] == 'one'
          ? const [
              ImageBlock(
                path: 'fixture.png',
                mimeType: 'image/png',
                data: 'AQ==',
              ),
            ]
          : const [],
    );
  }
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

List<ProviderEvent> _calls(List<String> texts, {String prefix = 'call'}) => [
  for (var i = 0; i < texts.length; i++) ...[
    ToolCallStart('${prefix}_$i', 'fixture_tool'),
    ToolCallArgsDelta('${prefix}_$i', jsonEncode({'text': texts[i]})),
    ToolCallEnd('${prefix}_$i'),
  ],
  const Done('tool_calls'),
];
const _answer = [TextDelta('Completed'), Done('stop')];

Future<AppController> _app(
  _Tool tool, {
  _Adapter? adapter,
  ApiType api = ApiType.chatCompletions,
  AdapterFactory? factory,
  bool hostedSearch = false,
  String? baseUrl,
}) async {
  final database = AppDatabase(NativeDatabase.memory());
  final app = AppController(
    database: database,
    services: _Services(),
    promptTemplate: 'Fixture prompt',
    adapterFactory: factory ?? (_, key, headers) => adapter!,
    extraTools: [tool],
  );
  addTearDown(() async {
    app.dispose();
    await database.close();
  });
  await app.initialize();
  await app.saveProvider(
    ProviderConfig(
      id: 'fixture',
      displayName: 'Fixture',
      apiType: api,
      baseUrl: baseUrl ?? 'https://fixture.invalid/v1',
      model: 'fixture-model',
      capabilities: ProviderCapabilities(
        tools: true,
        vision: true,
        contextWindow: 32000,
        builtInWebSearch: hostedSearch,
      ),
      maxOutputTokens: 256,
    ),
  );
  return app;
}

Future<PermissionRequest> _approval(AppController app) {
  if (app.pendingApproval case final pending?) return Future.value(pending);
  final ready = Completer<PermissionRequest>();
  late void Function() listener;
  listener = () {
    if (app.pendingApproval case final pending?) {
      app.removeListener(listener);
      ready.complete(pending);
    }
  };
  app.addListener(listener);
  return ready.future.timeout(const Duration(seconds: 5));
}

String _sse(JsonMap data) => 'data: ${jsonEncode(data)}\n\n';

String _wire(ApiType api, {required bool tools}) {
  final events = <JsonMap>[];
  if (api == ApiType.chatCompletions) {
    events.add({
      'choices': [
        {
          'index': 0,
          'delta': tools
              ? {
                  'tool_calls': [
                    for (var i = 0; i < 2; i++)
                      {
                        'index': i,
                        'id': 'call_$i',
                        'type': 'function',
                        'function': {
                          'name': 'fixture_tool',
                          'arguments': jsonEncode({
                            'text': i == 0 ? 'one' : '二',
                          }),
                        },
                      },
                  ],
                }
              : {'content': 'Completed'},
          'finish_reason': tools ? 'tool_calls' : 'stop',
        },
      ],
    });
    return '${events.map(_sse).join()}data: [DONE]\n\n';
  }
  if (api == ApiType.responses) {
    if (tools) {
      for (var i = 0; i < 2; i++) {
        final item = <String, Object?>{
          'id': 'item_$i',
          'call_id': 'call_$i',
          'type': 'function_call',
          'name': 'fixture_tool',
          'arguments': jsonEncode({'text': i == 0 ? 'one' : '二'}),
        };
        events.add({
          'type': 'response.output_item.added',
          'output_index': i,
          'item': item,
        });
        events.add({
          'type': 'response.output_item.done',
          'output_index': i,
          'item': item,
        });
      }
    } else {
      events.add({'type': 'response.output_text.delta', 'delta': 'Completed'});
    }
    events.add({'type': 'response.completed', 'response': {}});
    return events.map(_sse).join();
  }
  events.add({'type': 'message_start', 'message': {}});
  if (tools) {
    for (var i = 0; i < 2; i++) {
      events.add({
        'type': 'content_block_start',
        'index': i,
        'content_block': {
          'type': 'tool_use',
          'id': 'call_$i',
          'name': 'fixture_tool',
          'input': {},
        },
      });
      events.add({
        'type': 'content_block_delta',
        'index': i,
        'delta': {
          'type': 'input_json_delta',
          'partial_json': jsonEncode({'text': i == 0 ? 'one' : '二'}),
        },
      });
      events.add({'type': 'content_block_stop', 'index': i});
    }
  } else {
    events.add({
      'type': 'content_block_start',
      'index': 0,
      'content_block': {'type': 'text', 'text': ''},
    });
    events.add({
      'type': 'content_block_delta',
      'index': 0,
      'delta': {'type': 'text_delta', 'text': 'Completed'},
    });
    events.add({'type': 'content_block_stop', 'index': 0});
  }
  events.add({
    'type': 'message_delta',
    'delta': {'stop_reason': tools ? 'tool_use' : 'end_turn'},
  });
  events.add({'type': 'message_stop'});
  return events.map(_sse).join();
}

List<JsonMap> _maps(Object? value) => [
  for (final item in asList(value) ?? []) ?asMap(item),
];

void main() {
  test(
    'main delegates to a distinct Haiku Messages connection and sees only compact evidence',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final screen = FakeScreen({
        'ready': FakeView('com.example.fixture', 'Fixture', [
          FakeWindow(box([button('Start', opens: 'done')])),
        ]),
        'done': FakeView('com.example.fixture', 'Fixture', [
          FakeWindow(box([label('Done'), label('Private screen payload')])),
        ]),
      }, start: 'ready')..fastActions = true;
      final main = _Adapter([
        [
          const ToolCallStart('delegate', 'remote_control'),
          ToolCallArgsDelta(
            'delegate',
            jsonEncode({
              'title': 'Start task',
              'task': 'Tap Start',
              'success_criteria': 'Done is visible',
              'expected_text': ['Done'],
              'expected_app': 'com.example.fixture',
            }),
          ),
          const ToolCallEnd('delegate'),
          const Done('tool_calls'),
        ],
        _answer,
      ]);
      final child = _Adapter([
        [
          const ToolCallStart('tap', 'tap'),
          ToolCallArgsDelta('tap', jsonEncode({'title': 'Start', 'id': 1})),
          const ToolCallEnd('tap'),
          const Done('tool_use'),
        ],
      ]);
      ProviderConfig? childConfig;
      final app = AppController(
        database: database,
        services: _RemoteServices(screen),
        promptTemplate:
            '{{#screen_delegate}}Delegate phone tasks{{/screen_delegate}}{{^screen_control}}No direct screen{{/screen_control}}',
        adapterFactory: (config, key, headers) {
          if (config.id == 'worker') {
            childConfig = config;
            return child;
          }
          return main;
        },
      );
      addTearDown(() async {
        app.dispose();
        screen.dispose();
        await database.close();
      });
      await app.initialize();
      await app.saveProvider(
        ProviderConfig(
          id: 'main',
          displayName: 'Main',
          apiType: ApiType.chatCompletions,
          baseUrl: 'https://main.invalid/v1',
          model: 'main-model',
          capabilities: const ProviderCapabilities(tools: true),
        ),
      );
      await app.saveProvider(
        ProviderConfig(
          id: 'worker',
          displayName: 'Worker',
          apiType: ApiType.messages,
          baseUrl: 'https://worker.invalid/v1',
          model: 'claude-haiku-5-5',
          capabilities: const ProviderCapabilities(tools: true),
        ),
      );
      await app.savePermissionPolicy(
        const PermissionPolicy(fullPermissions: true),
      );
      await app.send('Start the phone task');
      expect(main.requests, hasLength(2));
      expect(child.requests, hasLength(1));
      expect(childConfig!.model, 'claude-haiku-5-5');
      expect(childConfig!.apiType, ApiType.messages);
      expect(childConfig!.reasoningEffort, 'xhigh');
      expect(childConfig!.reasoningMode, ReasoningMode.adaptive);
      expect(
        main.requests.first.tools.map((t) => t.name),
        contains('remote_control'),
      );
      expect(
        main.requests.first.tools.map((t) => t.name),
        isNot(contains('read_screen')),
      );
      expect(
        main.requests.first.systemPrompt,
        contains('Delegate phone tasks'),
      );
      final parentResults = main.requests.last.messages
          .expand((m) => m.content)
          .whereType<ToolResultBlock>()
          .toList();
      expect(parentResults, hasLength(1));
      expect(
        (jsonDecode(parentResults.single.content)
            as Map<String, Object?>)['verified'],
        true,
      );
      expect(
        parentResults.single.content,
        isNot(contains('Private screen payload')),
      );
      expect(parentResults.single.attachments, isEmpty);
      expect(
        app.visibleMessages
            .expand((m) => m.content)
            .whereType<ToolCallBlock>()
            .map((c) => c.name),
        ['remote_control'],
      );
      await app.saveControlSettings(
        const DeviceControlSettings(remoteAgent: false),
      );
      expect(app.delegatesScreen, false);
      await app.saveProvider(
        ProviderConfig(
          id: 'other-worker',
          displayName: 'Any worker',
          apiType: ApiType.responses,
          baseUrl: 'https://another.invalid/v1',
          model: 'gpt-6.1-sol',
          capabilities: const ProviderCapabilities(
            tools: true,
            vision: true,
            reasoning: true,
          ),
          reasoningMode: ReasoningMode.enabled,
          reasoningEffort: 'medium',
          maxOutputTokens: 4096,
        ),
      );
      await app.saveControlSettings(
        const DeviceControlSettings(
          remoteAgent: true,
          remoteAgentProviderId: 'other-worker',
          remoteAgentModelId: 'gpt-6.1-sol',
          remoteAgentEffort: 'low',
        ),
      );
      expect(app.remoteAgentProvider!.model, 'gpt-6.1-sol');
      expect(app.remoteAgentProvider!.apiType, ApiType.responses);
      expect(app.remoteAgentProvider!.reasoningEffort, 'low');
      expect(app.remoteAgentProvider!.maxOutputTokens, 4096);
      expect(app.selectedProvider!.id, 'main');
      await app.saveControlSettings(
        app.controlSettings.copyWith(remoteAgentModelId: 'removed-model'),
      );
      expect(app.remoteAgentProvider, isNull);
    },
  );
  for (final api in [ApiType.responses, ApiType.messages]) {
    for (final deny in [false, true]) {
      test(
        '${api.name} hosted search ${deny ? 'denial' : 'allowance'} gates and audits each request',
        () async {
          final tool = _Tool();
          final adapter = _Adapter([_answer]);
          final app = await _app(
            tool,
            adapter: adapter,
            api: api,
            hostedSearch: true,
            baseUrl: api == ApiType.responses
                ? 'https://api.openai.com/v1'
                : 'https://api.anthropic.com/v1',
          );
          if (deny) {
            await app.savePermissionPolicy(
              const PermissionPolicy(
                overrides: {'web_search': ToolPermission.deny},
              ),
            );
          }
          await app.send('Search with the provider');
          expect(app.errorCode, isNull);
          expect(app.visibleMessages.last.text, 'Completed');
          expect(adapter.requests.single.builtInWebSearch, !deny);
          expect(
            adapter.requests.single.tools.map((tool) => tool.name),
            isNot(contains('web_search')),
          );
          expect(tool.inputs, isEmpty);
          final record = (await app.audit.list()).single;
          expect(record.toolName, 'web_search');
          expect(tryDecodeObject(record.arguments)?['max_calls'], 1);
          expect(
            record.decision,
            deny ? 'denied_by_policy' : 'provider_managed',
          );
          expect(record.isError, deny);
          expect(record.finishedAt, isNotNull);
        },
      );
    }
  }

  test('custom endpoint never receives official hosted search mode', () async {
    final adapter = _Adapter([_answer]);
    final app = await _app(
      _Tool(),
      adapter: adapter,
      api: ApiType.responses,
      hostedSearch: true,
    );
    await app.send('Search');
    expect(adapter.requests.single.builtInWebSearch, isFalse);
    expect(await app.audit.list(), isEmpty);
  });

  test(
    'hosted search Stop while forced approval pending sends no provider request',
    () async {
      final adapter = _Adapter([_answer]);
      final app = await _app(
        _Tool(),
        adapter: adapter,
        api: ApiType.messages,
        hostedSearch: true,
        baseUrl: 'https://api.anthropic.com',
      );
      await app.savePermissionPolicy(
        const PermissionPolicy(overrides: {'web_search': ToolPermission.ask}),
      );
      final sending = app.send('Search after approval');
      final request = await _approval(app);
      expect(request.toolName, 'web_search');
      expect(request.choices, isNot(contains(PermissionChoice.allowInChat)));
      app.stop();
      await sending;
      expect(adapter.requests, isEmpty);
      expect(app.pendingApproval, isNull);
      expect(app.busy, isFalse);
      expect(app.errorCode, isNull);
      expect((await app.audit.list()).single.decision, 'cancelled');
    },
  );

  const pausedSearch = [
    ProviderStateMetadata(
      sourceApi: 'messages',
      content: [
        {
          'type': 'server_tool_use',
          'id': 'hosted_call',
          'name': 'web_search',
          'input': {'query': 'fixture'},
        },
      ],
    ),
    Done('pause_turn'),
  ];
  test(
    'hosted pause_turn continues with provider state and no client tools',
    () async {
      final tool = _Tool();
      final adapter = _Adapter([pausedSearch, _answer]);
      final app = await _app(
        tool,
        adapter: adapter,
        api: ApiType.messages,
        hostedSearch: true,
        baseUrl: 'https://api.anthropic.com/v1',
      );
      await app.send('Continue server search');
      expect(app.errorCode, isNull);
      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests.every((request) => request.builtInWebSearch),
        isTrue,
      );
      expect(
        adapter.requests.last.messages.last.content.single,
        isA<ProviderStateBlock>(),
      );
      expect(app.visibleMessages.last.text, 'Completed');
      expect(tool.inputs, isEmpty);
      final records = await app.audit.list();
      expect(records, hasLength(2));
      expect(
        records.every((record) => record.finishedAt != null && !record.isError),
        isTrue,
      );
    },
  );

  test('hosted pause_turn is bounded by max steps', () async {
    final adapter = _Adapter([pausedSearch, pausedSearch, _answer]);
    final app = await _app(
      _Tool(),
      adapter: adapter,
      api: ApiType.messages,
      hostedSearch: true,
      baseUrl: 'https://api.anthropic.com/v1',
    );
    await app.saveToolSettings(const ToolSettings(maxSteps: 2));
    await app.send('Do not loop forever');
    expect(adapter.requests, hasLength(2));
    expect(app.errorCode, 'toolStepLimit');
    expect(app.busy, isFalse);
    expect(await app.audit.list(), hasLength(2));
  });

  for (final includeText in [false, true]) {
    test(
      'unsolicited tools are audited once with tools disabled (text: $includeText)',
      () async {
        final tool = _Tool();
        final adapter = _Adapter([
          [
            if (includeText) const TextDelta('Accompanying answer'),
            ..._calls(['one', 'two']),
          ],
        ]);
        final app = await _app(tool, adapter: adapter);
        await app.saveToolSettings(const ToolSettings(enabled: false));
        await app.send('Tools disabled');
        expect(tool.inputs, isEmpty);
        expect(adapter.requests, hasLength(1));
        expect(adapter.requests.single.tools, isEmpty);
        expect(app.visibleMessages.last.status, MessageStatus.error);
        expect(app.visibleMessages.last.error, 'toolsLater');
        expect(app.activeToolCallId, isNull);
        final records = await app.audit.list();
        expect(records, hasLength(2));
        expect(records.map((r) => r.decision), everyElement('tools_disabled'));
        expect(records.every((r) => r.finishedAt != null && r.isError), isTrue);
      },
    );
  }

  for (final regenerate in [false, true]) {
    test(
      'audit failure clears active tool indicator after ${regenerate ? 'regenerate' : 'send'}',
      () async {
        final tool = _Tool();
        final adapter = _Adapter([
          if (regenerate) _answer,
          _calls(['one']),
        ]);
        final app = await _app(tool, adapter: adapter);
        if (regenerate) await app.send('Original response');
        await app.database.customStatement('DROP TABLE audit_records');
        if (regenerate) {
          await app.regenerate(app.visibleMessages.last);
        } else {
          await app.send('Will fail audit');
        }
        expect(app.errorCode, 'operationFailed');
        expect(app.busy, isFalse);
        expect(app.activeToolCallId, isNull);
        expect(tool.inputs, isEmpty);
      },
    );
  }

  // On-device models have their own tests in test/on_device.
  for (final api in ApiType.values.where((t) => t != ApiType.onDevice)) {
    test(
      '${api.name}: real adapter streams multi-tool turn and replays paired image results',
      () async {
        final bodies = <JsonMap>[];
        final tool = _Tool(imageResult: true);
        final app = await _app(
          tool,
          api: api,
          factory: (config, key, headers) {
            return ProviderAdapter.create(
              config,
              clientFactory: () => MockClient.streaming((
                request,
                stream,
              ) async {
                bodies.add(tryDecodeObject(await stream.bytesToString())!);
                final wire = _wire(api, tools: bodies.length == 1);
                return http.StreamedResponse(
                  Stream.fromIterable(utf8.encode(wire).map((byte) => [byte])),
                  200,
                  headers: {'content-type': 'text/event-stream'},
                );
              }),
            );
          },
        );
        await app.send('Run both tools');
        expect(app.errorCode, isNull);
        expect(app.visibleMessages.last.text, 'Completed');
        expect(tool.inputs, ['one', '二']);
        expect(bodies, hasLength(2));
        expect(app.visibleMessages.map((m) => m.role), [
          MessageRole.user,
          MessageRole.assistant,
          MessageRole.tool,
          MessageRole.assistant,
        ]);
        expect(await app.audit.list(), hasLength(2));
        final receipts = app.visibleMessages[2].content
            .whereType<ToolResultBlock>()
            .toList();
        expect(receipts.map((r) => r.toolCallId), ['call_0', 'call_1']);
        expect(receipts.first.attachments.single, isA<ImageBlock>());
        final body = bodies.last;
        expect(jsonEncode(body), contains('AQ=='));
        if (api == ApiType.chatCompletions) {
          final messages = _maps(body['messages']);
          final assistant = messages.indexWhere((m) => m['tool_calls'] != null);
          expect(messages.skip(assistant + 1).take(3).map((m) => m['role']), [
            'tool',
            'tool',
            'user',
          ]);
          expect(
            messages
                .where((m) => m['role'] == 'tool')
                .map((m) => m['tool_call_id']),
            ['call_0', 'call_1'],
          );
        } else if (api == ApiType.responses) {
          final items = _maps(body['input']);
          expect(
            items
                .where((m) => m['type'] == 'function_call_output')
                .map((m) => m['call_id']),
            ['call_0', 'call_1'],
          );
        } else {
          final content = [
            for (final m in _maps(body['messages'])) ..._maps(m['content']),
          ];
          expect(
            content
                .where((m) => m['type'] == 'tool_result')
                .map((m) => m['tool_use_id']),
            ['call_0', 'call_1'],
          );
        }
        final conversationId = app.conversation!.id;
        await app.newChat();
        await app.openConversation(conversationId);
        expect(
          app.visibleMessages[2].content.whereType<ToolResultBlock>(),
          hasLength(2),
        );
      },
    );
  }

  test(
    'permission blocks execution; allow and deny each reach the model',
    () async {
      final tool = _Tool(risk: RiskLevel.sensitive);
      final adapter = _Adapter([
        _calls(['one', 'two']),
        _answer,
      ]);
      final app = await _app(tool, adapter: adapter);
      final sending = app.send('Read twice');
      await _approval(app);
      expect(tool.inputs, isEmpty);
      expect(adapter.requests, hasLength(1));
      app.permissionGate.decide(PermissionChoice.allowOnce);
      // Wait until the first approval is cleared before observing the next one.
      await Future<void>.delayed(Duration.zero);
      await _approval(app);
      expect(tool.inputs, ['one']);
      app.permissionGate.decide(PermissionChoice.deny);
      await sending;
      expect(tool.inputs, ['one']);
      final results = adapter.requests.last.messages.last.content
          .whereType<ToolResultBlock>()
          .toList();
      expect(results, hasLength(2));
      expect(jsonDecode(results.last.content), {'error': 'denied_by_user'});
      expect(app.visibleMessages.last.text, 'Completed');
    },
  );

  test(
    'Stop cancels pending approval and records every call without execution',
    () async {
      final tool = _Tool(risk: RiskLevel.high);
      final adapter = _Adapter([
        _calls(['one', 'two']),
        _answer,
      ]);
      final app = await _app(tool, adapter: adapter);
      final sending = app.send('Pending high-risk operations');
      await _approval(app);
      app.stop();
      await sending;
      app.permissionGate.decide(PermissionChoice.allowOnce);
      expect(tool.inputs, isEmpty);
      expect(app.pendingApproval, isNull);
      expect(app.busy, isFalse);
      expect(adapter.requests, hasLength(1));
      final results = app.visibleMessages.last.content
          .whereType<ToolResultBlock>();
      expect(results, hasLength(2));
      expect(
        results.every(
          (r) => tryDecodeObject(r.content)?['error'] == 'cancelled',
        ),
        isTrue,
      );
      expect(
        (await app.audit.list()).map((row) => row.decision),
        everyElement('cancelled'),
      );
      await app.send('Continue with an answer');
      expect(app.visibleMessages.last.text, 'Completed');
    },
  );

  test(
    'Stop after committed effect preserves receipt and skips remaining calls',
    () async {
      late AppController app;
      final tool = _Tool(
        onRun: (context) async {
          app.stop();
          return const ToolResult(
            content: 'Written',
            sideEffects: [
              SideEffect(
                kind: 'file_written',
                summary: 'file.txt',
                backupPath: 'backup',
              ),
            ],
          );
        },
      );
      final adapter = _Adapter([
        _calls(['one', 'two']),
      ]);
      app = await _app(tool, adapter: adapter);
      await app.send('Write files');
      final results = app.visibleMessages.last.content
          .whereType<ToolResultBlock>()
          .toList();
      expect(tool.inputs, ['one']);
      expect(results.first.sideEffects.single.backupPath, 'backup');
      expect(jsonDecode(results.last.content), {'error': 'cancelled'});
      expect(app.sideEffectsAfter(app.visibleMessages.first), hasLength(1));
    },
  );

  test(
    'step limit cannot execute remaining tools and receipts stay paired',
    () async {
      final tool = _Tool();
      final adapter = _Adapter([
        _calls(['one', 'two']),
      ]);
      final app = await _app(tool, adapter: adapter);
      await app.saveToolSettings(const ToolSettings(maxSteps: 1));
      await app.send('Execute too many tools');
      expect(tool.inputs, ['one']);
      expect(adapter.requests, hasLength(1));
      expect(app.errorCode, 'toolStepLimit');
      expect(app.busy, isFalse);
      final results = app.visibleMessages.last.content
          .whereType<ToolResultBlock>()
          .toList();
      expect(results, hasLength(2));
      expect(jsonDecode(results.last.content), {'error': 'step_limit'});
      expect(await app.audit.list(), hasLength(2));
    },
  );

  test(
    'retry after provider failure reuses tool receipts without repeating actions',
    () async {
      final tool = _Tool();
      final adapter = _Adapter([
        _calls(['one']),
        const [
          TextDelta('Partial'),
          ProviderError('Unavailable', statusCode: 503),
        ],
        _answer,
      ]);
      final app = await _app(tool, adapter: adapter);
      await app.send('Use tool then answer');
      final failed = app.visibleMessages.last;
      expect(failed.status, MessageStatus.error);
      expect(tool.inputs, ['one']);
      await app.retryResponse(failed);
      expect(tool.inputs, ['one']);
      expect(app.tree.siblingsOf(failed.id), hasLength(2));
      expect(adapter.requests.last.messages.last.role, MessageRole.tool);
      expect(app.visibleMessages.last.text, 'Completed');
    },
  );

  for (final finalAnswer in [false, true]) {
    test(
      'regenerating ${finalAnswer ? 'final answer' : 'tool-call node'} starts the entire turn again',
      () async {
        final tool = _Tool(
          risk: RiskLevel.action,
          onRun: (context) async => const ToolResult(
            content: 'Written',
            sideEffects: [
              SideEffect(
                kind: 'file_written',
                summary: 'file.txt',
                backupPath: 'backup',
              ),
            ],
          ),
        );
        final adapter = _Adapter([
          _calls(['one']),
          _answer,
          _calls(['two']),
          _answer,
        ]);
        final app = await _app(tool, adapter: adapter);
        await app.savePermissionPolicy(
          const PermissionPolicy(fullPermissions: true),
        );
        await app.send('Write and explain');
        final callMessage = app.visibleMessages[1];
        final originalAnswer = app.visibleMessages.last;
        final user = app.visibleMessages.first;
        await app.regenerate(finalAnswer ? originalAnswer : callMessage);
        expect(tool.inputs, ['one', 'two']);
        expect(adapter.requests[2].messages.last.id, user.id);
        expect(adapter.requests[2].messages, hasLength(1));
        expect(app.visibleMessages[1].parentId, user.id);
        expect(app.tree.siblingsOf(callMessage.id), hasLength(2));
        expect(app.sideEffectsAfter(app.visibleMessages.first), hasLength(1));
        expect(await app.audit.list(), hasLength(2));
        await app.switchBranch(callMessage);
        expect(app.visibleMessages.last.id, originalAnswer.id);
      },
    );
  }

  test(
    'reused call ID in a failed later stream cannot pair with old receipts',
    () async {
      final tool = _Tool();
      final adapter = _Adapter([
        _calls(['one']),
        _answer,
        [
          ..._calls(['never executed']).where((event) => event is! Done),
          const ProviderError('Failed', statusCode: 500),
        ],
        _answer,
      ]);
      final app = await _app(tool, adapter: adapter);
      await app.send('First');
      await app.send('Second');
      expect(app.visibleMessages.last.status, MessageStatus.error);
      await app.send('Third');
      final blocks = [
        for (final message in adapter.requests.last.messages)
          ...message.content,
      ];
      expect(blocks.whereType<ToolCallBlock>(), hasLength(1));
      expect(blocks.whereType<ToolResultBlock>(), hasLength(1));
      expect(tool.inputs, ['one']);
      expect(adapter.requests.last.replayOpaqueReasoning, isFalse);
    },
  );
}
