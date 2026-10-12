import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/on_device/gguf.dart';
import 'package:tako/core/on_device/on_device_capability.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/platform/on_device/combined_on_device.dart';

const fileModel = LocalModel(
  id: 'model.gguf',
  sizeBytes: 99,
  info: GgufInfo(architecture: 'qwen3'),
);
const request = ChatRequest(systemPrompt: '', messages: []);
ProviderConfig config(String id) => ProviderConfig(
  id: 'local',
  displayName: 'Local',
  apiType: ApiType.onDevice,
  baseUrl: '',
  model: id,
);

class Engine extends UnavailableOnDevice {
  Engine(this.name, this.trace, this.models);
  final String name;
  final List<String> trace;
  @override
  List<LocalModel> models;
  @override
  bool get isAvailable => true;
  @override
  int get storageBytes => name == 'files' ? 99 : 0;
  @override
  String? loadedModel;
  Completer<void>? held;
  final started = Completer<void>();
  @override
  Future<void> unload() async {
    trace.add('$name:unload');
    loadedModel = null;
  }

  @override
  Future<void> prepareSystemModel({
    String modelId = 'aicore:gemini-nano',
  }) async {
    trace.add('$name:prepare');
    models = [aicoreModel];
    loadedModel = aicoreModel.id;
    notifyListeners();
  }

  @override
  Stream<ProviderEvent> generate(
    ProviderConfig config,
    ChatRequest request, {
    required CancelToken cancel,
  }) async* {
    trace.add('$name:${config.model}');
    loadedModel = config.model;
    if (!started.isCompleted) started.complete();
    try {
      if (held case final pending?) await cancel.bind(pending.future);
      yield TextDelta(name);
      yield const Done('stop');
    } on RequestCancelled {
      trace.add('$name:cancel');
    }
  }
}

void main() {
  late List<String> trace;
  late Engine files;
  late Engine system;
  late CombinedOnDevice combined;
  setUp(() {
    trace = [];
    files = Engine('files', trace, [fileModel]);
    system = Engine('system', trace, [aicoreModel]);
    combined = CombinedOnDevice(files: files, system: system);
  });
  tearDown(() => combined.dispose());

  test(
    'routes by model ID and unloads the other engine before switching',
    () async {
      await combined
          .generate(config(fileModel.id), request, cancel: CancelToken())
          .toList();
      await combined
          .generate(config(aicoreModel.id), request, cancel: CancelToken())
          .toList();
      combined.preferSpeed = true;
      await combined
          .generate(config(fileModel.id), request, cancel: CancelToken())
          .toList();
      expect(trace, [
        'files:model.gguf',
        'files:unload',
        'system:aicore:gemini-nano',
        'system:unload',
        'files:model.gguf',
      ]);
      expect(files.preferSpeed, isTrue);
      expect(combined.models.map((m) => m.id), [aicoreModel.id, fileModel.id]);
      expect(combined.storageBytes, 99);
      expect(combined.loadedModel, fileModel.id);
    },
  );

  test(
    'preview models route to the system engine and cannot be deleted as files',
    () async {
      await combined
          .generate(
            config(aicorePreviewModel.id),
            request,
            cancel: CancelToken(),
          )
          .toList();
      expect(trace, ['system:aicore:gemini-nano-preview']);
      await expectLater(
        combined.delete(aicorePreviewModel.id),
        throwsA(isA<OnDeviceException>()),
      );
    },
  );

  test(
    'queued system generation waits for file cancellation and releases the queue',
    () async {
      files.held = Completer<void>();
      final token = CancelToken();
      final first = combined
          .generate(config(fileModel.id), request, cancel: token)
          .toList();
      await files.started.future;
      final second = combined
          .generate(config(aicoreModel.id), request, cancel: CancelToken())
          .toList();
      expect(system.started.isCompleted, isFalse);
      token.cancel();
      expect(await first, isEmpty);
      expect((await second).whereType<TextDelta>().single.text, 'system');
      expect(trace, [
        'files:model.gguf',
        'files:cancel',
        'files:unload',
        'system:aicore:gemini-nano',
      ]);
    },
  );

  test(
    'preparation releases file memory; the system model cannot be deleted',
    () async {
      files.loadedModel = fileModel.id;
      await combined.prepareSystemModel();
      expect(trace, ['files:unload', 'system:prepare']);
      await expectLater(
        combined.delete(aicoreModel.id),
        throwsA(isA<OnDeviceException>()),
      );
      expect(system.models, [aicoreModel]);
    },
  );
}
