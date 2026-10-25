import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/on_device/on_device_capability.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/platform/android/aicore_on_device.dart';

final config = ProviderConfig(
  id: 'local',
  displayName: 'Local',
  apiType: ApiType.onDevice,
  baseUrl: '',
  model: aicoreModel.id,
  capabilities: aicoreModel.profile().capabilities,
  maxOutputTokens: 1024,
);
const request = ChatRequest(systemPrompt: 'Answer briefly.', messages: []);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('test/aicore');
  const events = EventChannel('test/aicore/events');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late AicoreOnDevice engine;
  late List<MethodCall> calls;
  late Completer<Map<Object?, Object?>> listening;
  String? failure;
  bool available = true;
  bool structured = true;
  Map<String, Object?> metadata({String? id, String state = 'ready'}) => {
    'modelId': id ?? aicoreModel.id,
    'state': state,
    'tools': structured,
    'contextWindow': 8192,
    'baseModelName': 'nano-v4',
  };

  Future<void> emit(Object? event, {String? error}) async {
    final delivered = Completer<void>();
    await messenger.handlePlatformMessage(
      events.name,
      error != null
          ? codec.encodeErrorEnvelope(
              code: error,
              message: 'private SDK detail',
            )
          : event == null
          ? null
          : codec.encodeSuccessEnvelope(event),
      (_) => delivered.complete(),
    );
    await delivered.future;
  }

  setUp(() {
    failure = null;
    available = true;
    structured = true;
    calls = [];
    listening = Completer<Map<Object?, Object?>>();
    engine = AicoreOnDevice(methods: methods, events: events);
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      if (call.method == 'status') {
        return [
          metadata(state: available ? 'available' : 'unavailable'),
          metadata(id: aicorePreviewModel.id, state: 'unavailable'),
        ];
      }
      if (call.method == 'prepare' && failure != null) {
        throw PlatformException(code: failure!, message: 'private SDK detail');
      }
      if (call.method == 'prepare') {
        return metadata(
          id: (call.arguments as Map<Object?, Object?>)['modelId'] as String?,
        );
      }
      return null;
    });
    messenger.setMockMethodCallHandler(MethodChannel(events.name), (
      call,
    ) async {
      if (call.method == 'listen') {
        listening.complete(call.arguments as Map<Object?, Object?>);
      }
      return null;
    });
  });

  tearDown(() {
    engine.dispose();
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(MethodChannel(events.name), null);
  });

  test(
    'preflight never downloads; setup detects tool capability and token limit',
    () async {
      await engine.refresh();
      expect(calls.map((call) => call.method), ['status']);
      expect(engine.systemModelStatus.state, SystemModelState.available);
      expect(engine.models, isEmpty);
      await engine.prepareSystemModel();
      expect(engine.models.single.id, aicoreModel.id);
      expect(engine.models.single.info, isNull);
      expect(engine.models.single.isSystem, isTrue);
      final capabilities = engine.models.single.profile().capabilities;
      expect(
        [capabilities.tools, capabilities.vision, capabilities.reasoning],
        [true, false, false],
      );
      expect(capabilities.contextWindow, 8192);
      await engine.unload();
      expect(engine.loadedModel, isNull);
      expect(engine.models.single.id, aicoreModel.id);
    },
  );

  test(
    'unsupported service and preparation failures remain actionable',
    () async {
      available = false;
      await engine.refresh();
      expect(engine.isAvailable, isFalse);
      expect(engine.systemModelStatus.state, SystemModelState.unavailable);
      available = true;
      await engine.refresh();
      failure = 'aicore_update';
      await expectLater(
        engine.prepareSystemModel(),
        throwsA(
          isA<OnDeviceException>().having(
            (e) => e.code,
            'code',
            'aicore_update',
          ),
        ),
      );
      expect(engine.systemModelStatus.error, 'aicore_update');
      expect(engine.loadedModel, isNull);
      expect(engine.loadingModel, isNull);
    },
  );

  test(
    'streaming preserves chunks and the output limit, with one completion',
    () async {
      final result = engine
          .generate(
            config,
            const ChatRequest(
              systemPrompt: 'system',
              messages: [],
              maxTokens: 321,
            ),
            cancel: CancelToken(),
          )
          .toList();
      final args = await listening.future;
      expect(args['maxOutputTokens'], 321);
      await emit({'type': 'ready', ...metadata()});
      await emit({'type': 'text', 'text': 'Hello'});
      await emit({'type': 'text', 'text': ' there'});
      await emit({'type': 'done', 'reason': 'length'});
      final output = await result;
      expect(output.whereType<TextDelta>().map((e) => e.text), [
        'Hello',
        ' there',
      ]);
      expect(output.whereType<Done>().single.stopReason, 'length');
      expect(engine.loadedModel, aicoreModel.id);
      expect(engine.loadingModel, isNull);
    },
  );

  test(
    'Stop cancels a pending native preparation without error or Done',
    () async {
      final cancel = CancelToken();
      final result = engine.generate(config, request, cancel: cancel).toList();
      final args = await listening.future;
      cancel.cancel();
      // Already queued native callbacks may arrive after Stop.
      await emit({'type': 'text', 'text': 'late'});
      expect(await result, isEmpty);
      final stop = calls.singleWhere((call) => call.method == 'cancel');
      expect((stop.arguments as Map)['requestId'], args['requestId']);
      expect(engine.loadingModel, isNull);
    },
  );

  test(
    'native errors retain their code without exposing SDK details',
    () async {
      final result = engine
          .generate(config, request, cancel: CancelToken())
          .toList();
      await listening.future;
      await emit(null, error: 'aicore_request_too_large');
      final error = (await result).single as ProviderError;
      expect(error.code, 'aicore_request_too_large');
      expect(error.message, isNot(contains('private SDK detail')));
      expect(engine.loadingModel, isNull);
    },
  );

  test('an interrupted stream is an error', () async {
    final result = engine
        .generate(config, request, cancel: CancelToken())
        .toList();
    await listening.future;
    await emit(null);
    expect(
      (await result).single,
      isA<ProviderError>().having((e) => e.code, 'code', 'incomplete_stream'),
    );
  });

  test(
    'prompt preserves roles, frozen context and files, excluding opaque state',
    () {
      final prompt =
          jsonDecode(
                aicorePrompt(
                  ChatRequest(
                    systemPrompt: 'system rules',
                    messages: [
                      ChatMessage(
                        id: 'u',
                        conversationId: 'c',
                        role: MessageRole.user,
                        createdAt: DateTime.utc(2026),
                        contextEnvelope: '<context>frozen</context>',
                        content: const [
                          TextBlock('hello'),
                          FileBlock(
                            path: 'doc.txt',
                            name: 'doc.txt',
                            mimeType: 'text/plain',
                            extractedText: 'file text',
                          ),
                          ImageBlock(
                            path: 'image.png',
                            mimeType: 'image/png',
                            data: 'private image bytes',
                          ),
                        ],
                      ),
                      ChatMessage(
                        id: 'a',
                        conversationId: 'c',
                        role: MessageRole.assistant,
                        createdAt: DateTime.utc(2026),
                        content: const [
                          TextBlock('reply'),
                          ReasoningBlock(
                            text: 'private reasoning',
                            signature: 'secret',
                          ),
                          ProviderStateBlock(
                            sourceApi: 'responses',
                            promptHash: 'h',
                            content: [
                              {'opaque': 'secret'},
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
              as Map<String, Object?>;
      expect(prompt['system'], 'system rules');
      final history = (prompt['conversation'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(history[0]['role'], 'user');
      expect(
        jsonEncode(history[0]['content']),
        contains('<context>frozen</context>'),
      );
      expect(jsonEncode(history[0]['content']), contains('file text'));
      expect(history[1], {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'reply'},
        ],
      });
      expect(jsonEncode(prompt), isNot(contains('private image bytes')));
      expect(jsonEncode(prompt), isNot(contains('secret')));
    },
  );

  test(
    'preview setup uses its own ID and detects models without tools',
    () async {
      structured = false;
      await engine.prepareSystemModel(modelId: aicorePreviewModel.id);
      expect(engine.models.single.id, aicorePreviewModel.id);
      expect(engine.models.single.profile().capabilities.tools, isFalse);
      expect(engine.loadedModel, aicorePreviewModel.id);
      expect(engine.systemModelStatus.state, SystemModelState.unavailable);
    },
  );

  const toolRequest = ChatRequest(
    systemPrompt: 'tools',
    messages: [],
    tools: [
      ToolDefinition(
        name: 'fixture_tool',
        description: 'Returns a value.',
        schema: {
          'type': 'object',
          'properties': {
            'text': {'type': 'string'},
          },
          'required': ['text'],
        },
      ),
    ],
  );

  test('a failed preview switch clears the previous warm model', () async {
    await engine.prepareSystemModel();
    expect(engine.loadedModel, aicoreModel.id);
    failure = 'aicore_unavailable';
    await expectLater(
      engine.prepareSystemModel(modelId: aicorePreviewModel.id),
      throwsA(isA<OnDeviceException>()),
    );
    expect(engine.loadedModel, isNull);
    expect(engine.loadingModel, isNull);
    expect(engine.models.single.id, aicoreModel.id);
  });

  test(
    'tools are published only after a complete structured reply and Done',
    () async {
      final output = <ProviderEvent>[];
      final complete = Completer<void>();
      final subscription = engine
          .generate(config, toolRequest, cancel: CancelToken())
          .listen(output.add, onDone: complete.complete);
      final args = await listening.future;
      expect(args['useTools'], isTrue);
      final prompt =
          jsonDecode(args['prompt']! as String) as Map<String, Object?>;
      expect(prompt['tools'], hasLength(1));
      await emit({
        'type': 'agent',
        'kind': 'tool_calls',
        'text': '',
        'calls': [
          {'name': 'fixture_tool', 'arguments': '{"text":"one"}'},
        ],
      });
      expect(output, isEmpty);
      await emit({'type': 'done', 'reason': 'stop'});
      await complete.future;
      await subscription.cancel();
      final start = output.whereType<ToolCallStart>().single;
      expect(start.name, 'fixture_tool');
      expect(output.whereType<ToolCallArgsDelta>().single.id, start.id);
      expect(output.whereType<ToolCallEnd>().single.id, start.id);
      expect(output.whereType<Done>().single.stopReason, 'tool_calls');
    },
  );

  test(
    'a structured answer becomes assistant text instead of displaying JSON',
    () async {
      final result = engine
          .generate(config, toolRequest, cancel: CancelToken())
          .toList();
      await listening.future;
      await emit({
        'type': 'agent',
        'kind': 'answer',
        'text': 'The result is one.',
        'calls': [],
      });
      await emit({'type': 'done', 'reason': 'stop'});
      final output = await result;
      expect(output.whereType<TextDelta>().single.text, 'The result is one.');
      expect(output.whereType<ToolCallStart>(), isEmpty);
      expect(output.whereType<Done>().single.stopReason, 'stop');
    },
  );

  test(
    'stopping an unfinished tool round discards the buffered calls',
    () async {
      final cancel = CancelToken();
      final result = engine
          .generate(config, toolRequest, cancel: cancel)
          .toList();
      await listening.future;
      await emit({
        'type': 'agent',
        'kind': 'tool_calls',
        'text': '',
        'calls': [
          {'name': 'fixture_tool', 'arguments': '{}'},
        ],
      });
      cancel.cancel();
      expect(await result, isEmpty);
    },
  );

  test(
    'malformed tool rounds and tool replies with missing completion never publish calls',
    () async {
      final result = engine
          .generate(config, toolRequest, cancel: CancelToken())
          .toList();
      await listening.future;
      await emit({
        'type': 'agent',
        'kind': 'tool_calls',
        'text': '',
        'calls': [
          {'name': 'fixture_tool', 'arguments': '{}'},
          {'name': 'unknown_tool', 'arguments': '{}'},
        ],
      });
      final output = await result;
      expect(
        output.single,
        isA<ProviderError>().having(
          (e) => e.code,
          'code',
          'aicore_invalid_tools',
        ),
      );
    },
  );

  test(
    'a pending valid tool reply is discarded when the native stream breaks',
    () async {
      final result = engine
          .generate(config, toolRequest, cancel: CancelToken())
          .toList();
      await listening.future;
      await emit({
        'type': 'agent',
        'kind': 'tool_calls',
        'text': '',
        'calls': [
          {'name': 'fixture_tool', 'arguments': '{}'},
        ],
      });
      await emit(null);
      final output = await result;
      expect(
        output.single,
        isA<ProviderError>().having((e) => e.code, 'code', 'incomplete_stream'),
      );
    },
  );

  test('truncated structured output never publishes tool calls', () async {
    final result = engine
        .generate(config, toolRequest, cancel: CancelToken())
        .toList();
    await listening.future;
    await emit({
      'type': 'agent',
      'kind': 'tool_calls',
      'text': '',
      'calls': [
        {'name': 'fixture_tool', 'arguments': '{}'},
      ],
    });
    await emit({'type': 'done', 'reason': 'length'});
    expect(
      (await result).single,
      isA<ProviderError>().having(
        (e) => e.code,
        'code',
        'aicore_invalid_tools',
      ),
    );
  });

  group('plain JSON fallback', () {
    const answer = {
      'kind': 'answer',
      'text': 'The result is one.',
      'calls': <Object?>[],
    };
    const toolCall = {
      'kind': 'tool_calls',
      'text': '',
      'calls': [
        {'name': 'fixture_tool', 'arguments': '{"text":"one"}'},
      ],
    };
    final toolJson = jsonEncode(toolCall);
    Map<String, Object?> event(String type, Map<String, Object?> reply) =>
        type == 'agent_json'
        ? {'type': type, 'json': jsonEncode(reply)}
        : {'type': type, ...reply};

    for (final entry in {'answer': answer, 'tool call': toolCall}.entries) {
      test('${entry.key} is validated and buffered until Done', () async {
        final output = <ProviderEvent>[];
        final complete = Completer<void>();
        final subscription = engine
            .generate(config, toolRequest, cancel: CancelToken())
            .listen(output.add, onDone: complete.complete);
        addTearDown(subscription.cancel);
        await listening.future;
        await emit(event('agent_json', entry.value));
        expect(output, isEmpty);
        await emit({'type': 'done', 'reason': 'stop'});
        await complete.future;
        expect(output.whereType<ProviderError>(), isEmpty);
        if (entry.key == 'answer') {
          expect(output.whereType<TextDelta>().single.text, answer['text']);
          expect(output.whereType<ToolCallStart>(), isEmpty);
          expect(output.whereType<Done>().single.stopReason, 'stop');
        } else {
          final start = output.whereType<ToolCallStart>().single;
          expect(start.name, 'fixture_tool');
          final args = output.whereType<ToolCallArgsDelta>().single;
          expect(args.id, start.id);
          expect(jsonDecode(args.jsonFragment), {'text': 'one'});
          expect(output.whereType<ToolCallEnd>().single.id, start.id);
          expect(output.whereType<Done>().single.stopReason, 'tool_calls');
        }
      });
    }

    final invalidJson = <String, Object?>{
      'missing payload': null,
      'non-string payload': toolCall,
      'malformed JSON': '{"kind":',
      'non-object JSON': '[]',
      'wrong field type': jsonEncode({...answer, 'calls': ''}),
      'unknown tool': jsonEncode({
        ...toolCall,
        'calls': [
          {'name': 'unknown_tool', 'arguments': '{}'},
        ],
      }),
      'trailing text': '$toolJson extra text',
      'markdown fence': '```json\n$toolJson\n```',
      'oversized payload': '$toolJson${' ' * 262144}',
    };
    for (final entry in invalidJson.entries) {
      test('${entry.key} never publishes calls', () async {
        final result = engine
            .generate(config, toolRequest, cancel: CancelToken())
            .toList();
        await listening.future;
        await emit({'type': 'agent_json', 'json': entry.value});
        expect(
          (await result).single,
          isA<ProviderError>().having(
            (e) => e.code,
            'code',
            'aicore_invalid_tools',
          ),
        );
      });
    }

    test('requires tools in the request', () async {
      final result = engine
          .generate(config, request, cancel: CancelToken())
          .toList();
      await listening.future;
      await emit(event('agent_json', toolCall));
      expect(
        (await result).single,
        isA<ProviderError>().having(
          (e) => e.code,
          'code',
          'aicore_invalid_tools',
        ),
      );
    });

    for (final (first, second) in [
      ('agent_json', 'agent_json'),
      ('agent_json', 'agent'),
      ('agent', 'agent_json'),
    ]) {
      test('$first followed by $second discards both tool rounds', () async {
        final result = engine
            .generate(config, toolRequest, cancel: CancelToken())
            .toList();
        await listening.future;
        await emit(event(first, toolCall));
        await emit(event(second, toolCall));
        expect(
          (await result).single,
          isA<ProviderError>().having(
            (e) => e.code,
            'code',
            'aicore_invalid_tools',
          ),
        );
      });
    }

    for (final ending in [
      'stream end',
      'length',
      'missing reason',
      'native error',
      'cancelled',
    ]) {
      test('$ending discards a complete but uncommitted tool round', () async {
        final cancel = CancelToken();
        final result = engine
            .generate(config, toolRequest, cancel: cancel)
            .toList();
        await listening.future;
        await emit(event('agent_json', toolCall));
        switch (ending) {
          case 'stream end':
            await emit(null);
          case 'length':
            await emit({'type': 'done', 'reason': 'length'});
          case 'missing reason':
            await emit({'type': 'done'});
          case 'native error':
            await emit(null, error: 'aicore_failed');
          case 'cancelled':
            cancel.cancel();
        }
        final output = await result;
        if (ending == 'cancelled') {
          expect(output, isEmpty);
        } else {
          expect(
            output.single,
            isA<ProviderError>().having((e) => e.code, 'code', switch (ending) {
              'stream end' => 'incomplete_stream',
              'native error' => 'aicore_failed',
              _ => 'aicore_invalid_tools',
            }),
          );
        }
      });
    }
  });
}
