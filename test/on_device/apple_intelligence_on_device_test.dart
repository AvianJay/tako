import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/on_device/on_device_capability.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/platform/ios/apple_intelligence_on_device.dart';

ProviderConfig _config(LocalModel model) => ProviderConfig(
  id: 'local',
  displayName: 'Local',
  apiType: ApiType.onDevice,
  baseUrl: '',
  model: model.id,
  capabilities: model.profile().capabilities,
  maxOutputTokens: 1024,
);

ChatMessage _user(List<ContentBlock> content) => ChatMessage(
  id: 'u',
  conversationId: 'c',
  role: MessageRole.user,
  createdAt: DateTime.utc(2026),
  content: content,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('test/apple');
  const events = EventChannel('test/apple/events');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final png = Uint8List.fromList(img.encodePng(img.Image(width: 5, height: 3)));
  late AppleIntelligenceOnDevice engine;
  late List<MethodCall> calls;
  late Completer<Map<Object?, Object?>> listening;
  late List<Map<String, Object?>> statuses;
  String? failure;

  Future<void> emit(Object? event, {String? error}) async {
    final delivered = Completer<void>();
    await messenger.handlePlatformMessage(
      events.name,
      error != null
          ? codec.encodeErrorEnvelope(code: error, message: 'private detail')
          : event == null
          ? null
          : codec.encodeSuccessEnvelope(event),
      (_) => delivered.complete(),
    );
    await delivered.future;
  }

  setUp(() {
    failure = null;
    calls = [];
    listening = Completer<Map<Object?, Object?>>();
    statuses = [
      {
        'modelId': appleModel.id,
        'state': 'available',
        'reason': 'apple_disabled',
        'tools': false,
        'contextWindow': 4096,
      },
      {'modelId': appleImageModel.id, 'state': 'ready'},
    ];
    engine = AppleIntelligenceOnDevice(methods: methods, events: events);
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      if (call.method == 'status') return statuses;
      if (call.method == 'prepare' && failure != null) {
        throw PlatformException(code: failure!, message: 'private detail');
      }
      if (call.method == 'prepare') {
        return {
          'modelId': appleModel.id,
          'state': 'ready',
          'tools': true,
          'contextWindow': 4096,
        };
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
    'status explains a model that is not ready and lists the ready one',
    () async {
      await engine.refresh();
      expect(calls.map((call) => call.method), ['status']);
      final text = engine.systemModelStatus;
      expect(text.model.id, appleModel.id);
      expect(text.state, SystemModelState.available);
      expect(text.error, 'apple_disabled');
      final image = engine.models.single;
      expect(image.id, appleImageModel.id);
      expect(image.isSystem, isTrue);
      expect(image.profile().capabilities.imagesOnly, isTrue);
      expect(image.profile().capabilities.imageReferenceInput, isTrue);
      expect(
        _config(image).forModel(image.id).generatesImages,
        isTrue,
        reason: 'an on-device image model serves generate_image',
      );
    },
  );

  test(
    'checking again reports the reason and leaves the model to set up',
    () async {
      await engine.refresh();
      failure = 'apple_not_ready';
      await expectLater(
        engine.prepareSystemModel(modelId: appleModel.id),
        throwsA(
          isA<OnDeviceException>().having(
            (e) => e.code,
            'code',
            'apple_not_ready',
          ),
        ),
      );
      expect(engine.systemModelStatus.state, SystemModelState.failed);
      expect(engine.systemModelStatus.error, 'apple_not_ready');
      failure = null;
      await engine.prepareSystemModel(modelId: appleModel.id);
      expect(engine.models.map((m) => m.id), [
        appleModel.id,
        appleImageModel.id,
      ]);
      expect(engine.models.first.profile().capabilities.tools, isTrue);
      expect(engine.loadedModel, appleModel.id);
    },
  );

  test(
    'instructions carry the system prompt and tools, apart from the transcript',
    () async {
      const request = ChatRequest(
        systemPrompt: 'system rules',
        messages: [],
        maxTokens: 300,
        tools: [
          ToolDefinition(
            name: 'fixture_tool',
            description: 'Returns a value.',
            schema: {'type': 'object'},
          ),
        ],
      );
      final output = engine
          .generate(_config(appleModel), request, cancel: CancelToken())
          .toList();
      final args = await listening.future;
      expect(args['modelId'], appleModel.id);
      expect(args['useTools'], isTrue);
      expect(args['tools'], ['fixture_tool']);
      expect(args['maxOutputTokens'], 300);
      final instructions = args['instructions']! as String;
      expect(instructions, startsWith('system rules'));
      expect(instructions, contains('"name":"fixture_tool"'));
      expect(instructions, contains('kind="tool_calls"'));
      final prompt = jsonDecode(args['prompt']! as String) as Map;
      expect(prompt.keys, ['conversation']);
      await emit({
        'type': 'agent',
        'kind': 'tool_calls',
        'text': '',
        'calls': [
          {'name': 'fixture_tool', 'arguments': '{"text":"one"}'},
        ],
      });
      await emit({'type': 'done', 'reason': 'stop'});
      final events = await output;
      expect(events.whereType<ToolCallStart>().single.name, 'fixture_tool');
      expect(events.whereType<Done>().single.stopReason, 'tool_calls');
    },
  );

  test('a malformed tool reply uses the Apple error code', () async {
    const request = ChatRequest(
      systemPrompt: '',
      messages: [],
      tools: [
        ToolDefinition(name: 'fixture_tool', description: '', schema: {}),
      ],
    );
    final output = engine
        .generate(_config(appleModel), request, cancel: CancelToken())
        .toList();
    await listening.future;
    await emit({
      'type': 'agent',
      'kind': 'tool_calls',
      'text': '',
      'calls': [
        {'name': 'unknown_tool', 'arguments': '{}'},
      ],
    });
    expect(
      (await output).single,
      isA<ProviderError>().having((e) => e.code, 'code', 'apple_invalid_tools'),
    );
  });

  test(
    'an image request sends the newest prompt and its reference, and yields the image',
    () async {
      final request = ChatRequest(
        systemPrompt: 'unused',
        messages: [
          _user(const [TextBlock('an older prompt')]),
          _user([
            const TextBlock('A blue bird'),
            ImageBlock(
              path: 'reference.png',
              mimeType: 'image/png',
              data: base64Encode(png),
            ),
          ]),
        ],
      );
      final output = engine
          .generate(_config(appleImageModel), request, cancel: CancelToken())
          .toList();
      final args = await listening.future;
      expect(args['modelId'], appleImageModel.id);
      expect(args['prompt'], 'A blue bird');
      expect(args['images'], [png]);
      expect(args.containsKey('instructions'), isFalse);
      await emit({
        'type': 'ready',
        'modelId': appleImageModel.id,
        'state': 'ready',
      });
      await emit({'type': 'image', 'data': png});
      await emit({'type': 'done', 'reason': 'stop'});
      final events = await output;
      final image = events.whereType<GeneratedImage>().single;
      expect(image.mimeType, 'image/png');
      expect(base64Decode(image.base64), png);
      expect(events.last, isA<Done>());
    },
  );

  test(
    'Image Playground refuses a second reference image before it is sent',
    () async {
      final reference = ImageBlock(
        path: 'reference.png',
        mimeType: 'image/png',
        data: base64Encode(png),
      );
      final output = await engine
          .generate(
            _config(appleImageModel),
            ChatRequest(
              systemPrompt: '',
              messages: [
                _user([const TextBlock('Combine these'), reference, reference]),
              ],
            ),
            cancel: CancelToken(),
          )
          .toList();
      expect(
        output.single,
        isA<ProviderError>().having((e) => e.code, 'code', 'apple_image_input'),
      );
      expect(listening.isCompleted, isFalse);
    },
  );

  test(
    'setup errors need another check, request errors keep the model ready',
    () async {
      await engine.refresh();
      final first = engine
          .generate(
            _config(appleImageModel),
            ChatRequest(
              systemPrompt: '',
              messages: [
                _user(const [TextBlock('A bird')]),
              ],
            ),
            cancel: CancelToken(),
          )
          .toList();
      await listening.future;
      await emit(null, error: 'apple_guardrail');
      final error = (await first).single as ProviderError;
      expect(error.code, 'apple_guardrail');
      expect(error.message, isNot(contains('private detail')));
      expect(engine.models.map((m) => m.id), [appleImageModel.id]);

      listening = Completer<Map<Object?, Object?>>();
      final second = engine
          .generate(
            _config(appleImageModel),
            ChatRequest(
              systemPrompt: '',
              messages: [
                _user(const [TextBlock('A bird')]),
              ],
            ),
            cancel: CancelToken(),
          )
          .toList();
      await listening.future;
      await emit(null, error: 'apple_disabled');
      expect(
        (await second).single,
        isA<ProviderError>().having((e) => e.code, 'code', 'apple_disabled'),
      );
      expect(engine.models, isEmpty);
      expect(engine.systemModelStatuses.last.state, SystemModelState.failed);
    },
  );
}
