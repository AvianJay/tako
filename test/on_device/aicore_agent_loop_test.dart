import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/app/app_controller.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/files/workspace.dart';
import 'package:tako/core/on_device/on_device_capability.dart';
import 'package:tako/core/permissions/permission_gate.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/core/tools/tool.dart';
import 'package:tako/core/util/json.dart';
import 'package:tako/data/database.dart';
import 'package:tako/platform/android/aicore_on_device.dart';
import 'package:tako/platform/capabilities.dart';
import 'package:tako/platform/services.dart';

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

class _Services extends PlatformServices {
  _Services(this._engine);
  final OnDeviceCapability _engine;
  @override
  OnDeviceCapability get onDevice => _engine;
  @override
  final WorkspaceCapability workspace = _Workspace();
  @override
  Future<DeviceContext> deviceContext() async =>
      const DeviceContext(model: 'fixture');
  @override
  Future<String?> readSecret(String reference) async => null;
  @override
  Future<void> writeSecret(String reference, String? value) async {}
}

class _Available implements Capability {
  @override
  bool get isAvailable => true;
}

class _Tool extends Tool {
  int runs = 0;
  @override
  String get name => 'fixture_tool';
  @override
  String get description => 'Return the requested fixture value.';
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
  RiskLevel riskFor(JsonMap args, ToolContext ctx) => RiskLevel.sensitive;
  @override
  Future<ToolResult> run(JsonMap args, ToolContext ctx) async {
    ctx.cancel.throwIfCancelled();
    runs++;
    return ToolResult(content: jsonEncode({'value': args['text']}));
  }
}

Future<PermissionRequest> approval(AppController app) {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methods = MethodChannel('test/agent/aicore');
  const events = EventChannel('test/agent/aicore/events');
  const codec = StandardMethodCodec();
  const metadata = {
    'modelId': 'aicore:gemini-nano',
    'state': 'ready',
    'tools': true,
    'contextWindow': 32000,
    'baseModelName': 'fixture nano',
  };
  late AicoreOnDevice engine;
  late AppDatabase database;
  late AppController app;
  late _Tool tool;
  late List<JsonMap> requests;
  bool malformed = false;
  bool invalidArguments = false;

  Future<void> emit(Map<String, Object?> value) async {
    final delivered = Completer<void>();
    await messenger.handlePlatformMessage(
      events.name,
      codec.encodeSuccessEnvelope(value),
      (_) => delivered.complete(),
    );
    await delivered.future;
  }

  setUp(() async {
    malformed = invalidArguments = false;
    requests = [];
    tool = _Tool();
    engine = AicoreOnDevice(methods: methods, events: events);
    messenger.setMockMethodCallHandler(methods, (call) async {
      if (call.method == 'status') return [metadata];
      if (call.method == 'prepare') return metadata;
      return null;
    });
    messenger.setMockMethodCallHandler(MethodChannel(events.name), (
      call,
    ) async {
      if (call.method != 'listen') return null;
      final args = call.arguments as Map<Object?, Object?>;
      expect(args['useTools'], isTrue);
      final prompt = jsonDecode(args['prompt']! as String) as JsonMap;
      requests.add(prompt);
      final first = requests.length == 1;
      scheduleMicrotask(() async {
        await emit({'type': 'ready', ...metadata});
        await emit(
          first
              ? {
                  'type': 'agent',
                  'kind': 'tool_calls',
                  'text': '',
                  'calls': [
                    {
                      'name': malformed ? 'unknown_tool' : 'fixture_tool',
                      'arguments': jsonEncode({
                        'text': invalidArguments ? 42 : 'one',
                      }),
                    },
                  ],
                }
              : {
                  'type': 'agent',
                  'kind': 'answer',
                  'text': 'Completed',
                  'calls': [],
                },
        );
        await emit({'type': 'done', 'reason': 'stop'});
      });
      return null;
    });
    database = AppDatabase(NativeDatabase.memory());
    app = AppController(
      titleGenerator: (_, _, _) async => null,
      database: database,
      services: _Services(engine),
      promptTemplate: 'Use the supplied tools. Never invent tool results.',
      extraTools: [tool],
    );
    await app.initialize();
    await engine.refresh();
    await app.useOnDeviceModel(engine.models.single, providerName: 'On device');
  });

  tearDown(() async {
    app.dispose();
    engine.dispose();
    await database.close();
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(MethodChannel(events.name), null);
  });

  for (final choice in [PermissionChoice.allowOnce, PermissionChoice.deny]) {
    test(
      'native structured reply uses permission $choice, receipt replay and the agent loop',
      () async {
        final sending = app.send('Read a fixture value');
        final pending = await approval(app);
        expect(pending.toolName, 'fixture_tool');
        expect(pending.arguments, {'text': 'one'});
        expect(tool.runs, 0);
        expect(requests, hasLength(1));
        app.permissionGate.decide(choice);
        await sending;
        expect(tool.runs, choice == PermissionChoice.allowOnce ? 1 : 0);
        expect(requests, hasLength(2));
        final history = requests.last['conversation'] as List<Object?>;
        final content = [
          for (final message in history.cast<JsonMap>())
            ...(message['content'] as List<Object?>).cast<JsonMap>(),
        ];
        final call = content.singleWhere(
          (block) => block['type'] == 'tool_call',
        );
        final receipt = content.singleWhere(
          (block) => block['type'] == 'tool_result',
        );
        expect(receipt['id'], call['id']);
        expect(receipt['untrusted'], isTrue);
        expect(
          jsonDecode(receipt['text']! as String),
          choice == PermissionChoice.allowOnce
              ? {'value': 'one'}
              : {'error': 'denied_by_user'},
        );
        expect(app.visibleMessages.last.text, 'Completed');
        expect(app.visibleMessages.last.status, MessageStatus.done);
        expect(await app.audit.list(), hasLength(1));
      },
    );
  }

  test(
    'existing schema validation rejects invalid parameters without running the tool',
    () async {
      invalidArguments = true;
      await app.send('Read a fixture');
      expect(tool.runs, 0);
      expect(app.pendingApproval, isNull);
      expect(requests, hasLength(2));
      final results = app.visibleMessages
          .expand((m) => m.content)
          .whereType<ToolResultBlock>();
      expect(jsonDecode(results.single.content), {
        'error': 'invalid_arguments',
        'path': r'$.text',
        'expected': 'string',
        'hint':
            'Correct this field using the tool schema. No action was executed.',
      });
      expect((await app.audit.list()).single.isError, isTrue);
    },
  );

  test(
    'malformed model calls never reach permission or the tool executor',
    () async {
      malformed = true;
      await app.send('Read a fixture');
      expect(tool.runs, 0);
      expect(app.pendingApproval, isNull);
      expect(requests, hasLength(1));
      expect(await app.audit.list(), isEmpty);
      expect(app.visibleMessages.last.error, 'aicoreInvalidTools');
    },
  );

  test(
    'Stop during approval runs no tool and starts no continuation',
    () async {
      final sending = app.send('Read a fixture');
      await approval(app);
      app.stop();
      await sending;
      expect(tool.runs, 0);
      expect(requests, hasLength(1));
      expect(app.pendingApproval, isNull);
      expect((await app.audit.list()).single.decision, 'cancelled');
    },
  );
}
