import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:path/path.dart' as p;
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/platform/on_device/llama_on_device.dart';

import 'gguf_fixture.dart';

class FakeRunner implements LlamaRunner {
  final loads = <(String, String?, int)>[];
  final requests = <List<llama.LlamaChatMessage>>[];
  final toolLists = <List<llama.ToolDefinition>?>[];
  Object? loadError;
  int cancels = 0;
  int unloads = 0;
  StreamController<llama.LlamaCompletionChunk>? held;
  final threads = <int>[];

  @override
  Future<void> load(
    String model,
    String? projector, {
    required int contextSize,
    required int threads,
  }) async {
    loads.add((p.basename(model), projector, contextSize));
    this.threads.add(threads);
    if (loadError case final error?) throw error;
  }

  @override
  Stream<llama.LlamaCompletionChunk> create(
    List<llama.LlamaChatMessage> messages, {
    required llama.GenerationParams params,
    required List<llama.ToolDefinition>? tools,
    required bool thinking,
  }) {
    requests.add(messages);
    toolLists.add(tools);
    if (held case final controller?) return controller.stream;
    return Stream.fromIterable([_chunk(content: 'Hi'), _chunk(finish: 'stop')]);
  }

  @override
  void cancel() {
    cancels++;
    held?.close();
  }

  @override
  Future<void> unload() async => unloads++;
}

llama.LlamaCompletionChunk _chunk({String? content, String? finish}) =>
    llama.LlamaCompletionChunk(
      id: 'x',
      object: 'chat.completion.chunk',
      created: 0,
      model: 'm',
      choices: [
        llama.LlamaCompletionChunkChoice(
          index: 0,
          finishReason: finish,
          delta: llama.LlamaCompletionChunkDelta(content: content),
        ),
      ],
    );

ProviderConfig config({String model = 'model.gguf', int context = 4096}) =>
    ProviderConfig(
      id: 'on-device',
      displayName: 'On-device',
      apiType: ApiType.onDevice,
      baseUrl: '',
      model: model,
      capabilities: ProviderCapabilities(contextWindow: context, tools: true),
    );

final request = ChatRequest(
  systemPrompt: 'system',
  messages: [
    ChatMessage(
      id: 'u',
      conversationId: 'c',
      role: MessageRole.user,
      content: const [TextBlock('hello')],
      createdAt: DateTime.utc(2026, 10, 12),
    ),
  ],
  tools: const [
    ToolDefinition(
      name: 'get_device_status',
      description: 'Battery and network.',
      schema: {'type': 'object', 'properties': {}},
    ),
  ],
);

void main() {
  late Directory root;
  late FakeRunner runner;
  late LlamaOnDevice onDevice;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tako-on-device');
    final models = Directory(p.join(root.path, 'models'))..createSync();
    File(p.join(models.path, 'model.gguf')).writeAsBytesSync(ggufBytes());
    File(p.join(models.path, 'other.gguf')).writeAsBytesSync(ggufBytes());
    runner = FakeRunner();
    onDevice = LlamaOnDevice(
      directory: () async => models,
      runner: () => runner,
      supported: true,
      processors: 8,
    );
    await onDevice.refresh();
  });

  tearDown(() => root.delete(recursive: true));

  Future<List<ProviderEvent>> send(ProviderConfig config, [CancelToken? c]) =>
      ProviderAdapter.create(
        config,
        onDevice: onDevice,
      ).send(request, cancel: c ?? CancelToken()).toList();

  test('lists the models in the folder', () async {
    final models = await ProviderAdapter.create(
      config(),
      onDevice: onDevice,
    ).listModels();
    expect(models.map((m) => (m.id, m.displayName)), [
      ('model.gguf', 'Fixture Model'),
      ('other.gguf', 'Fixture Model'),
    ]);
    expect(onDevice.models.first.profile().capabilities.contextWindow, 8192);
  });

  test('loads a model once and answers with it', () async {
    final first = await send(config());
    expect(first.whereType<TextDelta>().single.text, 'Hi');
    expect(first.last, isA<Done>());
    await send(config());
    expect(runner.loads, [('model.gguf', null, 4096)]);
    expect(onDevice.loadedModel, 'model.gguf');
    expect(runner.requests.last.first.content, 'system');
    expect(runner.toolLists.last!.single.name, 'get_device_status');

    // Another model or context size loads again.
    await send(config(model: 'other.gguf'));
    await send(config(model: 'other.gguf', context: 8192));
    expect(runner.loads.skip(1), [
      ('other.gguf', null, 4096),
      ('other.gguf', null, 8192),
    ]);
  });

  test('a missing model or a failed load is reported', () async {
    final missing = await send(config(model: 'gone.gguf'));
    expect((missing.single as ProviderError).code, 'model_missing');
    expect(runner.loads, isEmpty);

    runner.loadError = Exception('out of memory');
    final failed = await send(config());
    final error = failed.single as ProviderError;
    expect(error.code, 'model_load');
    expect(error.message, contains('out of memory'));
    expect(onDevice.loadedModel, isNull);
  });

  test('responses run one at a time and Stop cancels', () async {
    runner.held = StreamController();
    final cancel = CancelToken();
    final first = send(config(), cancel);
    await pumpEventQueue();
    runner.held!.add(_chunk(content: 'Part'));
    final second = send(config());
    await pumpEventQueue();
    expect(runner.requests, hasLength(1));

    cancel.cancel();
    expect(runner.cancels, 1);
    final events = await first;
    expect(events.whereType<TextDelta>().single.text, 'Part');
    expect(events.whereType<ProviderError>(), isEmpty);

    runner.held = null;
    expect((await second).whereType<TextDelta>().single.text, 'Hi');
    expect(runner.requests, hasLength(2));
  });

  test('deleting the loaded model frees it first', () async {
    await send(config());
    await onDevice.delete('model.gguf');
    expect(runner.unloads, 1);
    expect(onDevice.loadedModel, isNull);
    expect(onDevice.models.map((m) => m.id), ['other.gguf']);
  });

  test('a core is left for the phone unless speed is preferred', () async {
    await send(config());
    onDevice.preferSpeed = true;
    await send(config());
    // The changed setting loads the model again.
    expect(runner.threads, [3, 4]);
    expect(runner.loads, hasLength(2));

    // Big.LITTLE phones: 8 cores have 4 big ones at most.
    expect(
      [
        for (final cores in [2, 4, 6, 8, 12])
          llamaThreads(cores, preferSpeed: false),
      ],
      [1, 2, 2, 3, 4],
    );
    expect(
      [
        for (final cores in [2, 4, 6, 8, 12])
          llamaThreads(cores, preferSpeed: true),
      ],
      [1, 2, 3, 4, 6],
    );
  });

  test('unsupported devices offer nothing', () {
    final unsupported = LlamaOnDevice(
      directory: () async => root,
      supported: false,
    );
    expect(unsupported.isAvailable, isFalse);
  });
}
