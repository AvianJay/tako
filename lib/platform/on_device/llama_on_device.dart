import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:llamadart/llamadart.dart' as llama;

import '../../core/on_device/on_device_capability.dart';
import '../../core/providers/providers.dart';
import 'llama_mapping.dart';
import 'model_files.dart';

/// CPU threads for llama.cpp on a device with [processors] cores. Phones have
/// few big cores, and using them all makes the whole phone stutter, so unless
/// [preferSpeed] one is left for the system and the app.
int llamaThreads(int processors, {required bool preferSpeed}) {
  final half = processors ~/ 2;
  return preferSpeed
      ? half.clamp(1, 6)
      : (half - 1).clamp(processors >= 4 ? 2 : 1, 4);
}

/// The part of llama.cpp Tako uses, so tests can run without native code.
abstract interface class LlamaRunner {
  Future<void> load(
    String model,
    String? projector, {
    required int contextSize,
    required int threads,
  });
  Stream<llama.LlamaCompletionChunk> create(
    List<llama.LlamaChatMessage> messages, {
    required llama.GenerationParams params,
    required List<llama.ToolDefinition>? tools,
    required bool thinking,
  });
  void cancel();
  Future<void> unload();
}

class LlamadartRunner implements LlamaRunner {
  llama.LlamaEngine? _engine;
  static var _logging = false;

  @override
  Future<void> load(
    String model,
    String? projector, {
    required int contextSize,
    required int threads,
  }) async {
    if (kDebugMode && !_logging) {
      // Load details and timings only; debug builds never ship.
      _logging = true;
      await llama.LlamaLogging.configure(
        level: llama.LlamaLogLevel.info,
        handler: (record) => debugPrint('llama: ${record.message}'),
      );
    }
    final engine = _engine ??= llama.LlamaEngine(llama.LlamaBackend());
    await engine.setModel(
      llama.LlamaModel(
        llama.ModelSource.path(model),
        projector: projector == null ? null : llama.ModelSource.path(projector),
      ),
      params: llama.ModelParams(
        contextSize: contextSize,
        numberOfThreads: threads,
        numberOfThreadsBatch: threads,
      ),
    );
  }

  @override
  Stream<llama.LlamaCompletionChunk> create(
    List<llama.LlamaChatMessage> messages, {
    required llama.GenerationParams params,
    required List<llama.ToolDefinition>? tools,
    required bool thinking,
  }) {
    final chunks = _engine!.create(
      messages,
      params: params,
      tools: tools,
      parallelToolCalls: true,
      enableThinking: thinking,
    );
    if (!kDebugMode) return chunks;
    final clock = Stopwatch()..start();
    return chunks.transform(
      StreamTransformer.fromHandlers(
        handleData: (chunk, sink) {
          debugPrint(
            'llama: chunk at ${clock.elapsedMilliseconds} ms: '
            '${chunk.text.length} text, ${chunk.thinking.length} thinking, '
            '${chunk.toolCalls.length} calls, finish ${chunk.finishReason}',
          );
          sink.add(chunk);
        },
        handleDone: (sink) {
          debugPrint('llama: done at ${clock.elapsedMilliseconds} ms');
          sink.close();
        },
      ),
    );
  }

  @override
  void cancel() => _engine?.cancelGeneration();

  @override
  Future<void> unload() async {
    final engine = _engine;
    _engine = null;
    await engine?.dispose();
  }
}

/// llama.cpp ships for 64-bit Android and iOS devices only.
bool get onDeviceSupported => switch (Abi.current()) {
  Abi.androidArm64 || Abi.androidX64 || Abi.iosArm64 => true,
  _ => false,
};

class LlamaOnDevice extends OnDeviceCapability {
  LlamaOnDevice({
    required Future<Directory> Function() directory,
    LlamaRunner Function()? runner,
    http.Client Function()? clientFactory,
    Future<(File, String)?> Function()? pickFile,
    bool? supported,
    int? processors,
  }) : _directory = directory,
       _runnerFactory = runner ?? LlamadartRunner.new,
       _clientFactory = clientFactory,
       _pickFile = pickFile ?? _pick,
       _supported = supported ?? onDeviceSupported,
       _processors = processors ?? Platform.numberOfProcessors;

  final Future<Directory> Function() _directory;
  final LlamaRunner Function() _runnerFactory;
  final http.Client Function()? _clientFactory;
  final Future<(File, String)?> Function() _pickFile;
  final bool _supported;
  final int _processors;
  ModelFiles? _files;
  LlamaRunner? _runner;
  String? _loadedKey;
  String? _loaded;
  String? _loading;
  Future<void> _queue = Future.value();

  @override
  bool get isAvailable => _supported;
  @override
  List<LocalModel> get models => _files?.models ?? const [];
  @override
  List<ModelDownload> get downloads => _files?.downloads ?? const [];
  @override
  String? get loadedModel => _loaded;

  @override
  String? get loadingModel => _loading;
  @override
  int get storageBytes => _files?.storageBytes ?? 0;

  Future<ModelFiles> _ready() async {
    if (_files case final files?) return files;
    final directory = await _directory();
    await directory.create(recursive: true);
    return _files ??= ModelFiles(
      directory,
      onChanged: notifyListeners,
      clientFactory: _clientFactory,
    );
  }

  @override
  Future<void> refresh() async {
    if (!_supported) return;
    await (await _ready()).refresh();
  }

  /// The picker hands over its own copy of the file, which Tako may move.
  static Future<(File, String)?> _pick() async {
    final picked = await FilePicker.pickFile();
    final path = picked?.path;
    return path == null ? null : (File(path), picked!.name);
  }

  @override
  Future<LocalModel?> importModel() async {
    final files = await _ready();
    if (await _pickFile() case (final file, final name)) {
      return files.importModel(file, name);
    }
    return null;
  }

  @override
  Future<void> importProjector(String modelId) async {
    final files = await _ready();
    if (await _pickFile() case (final file, final name)) {
      await _exclusive(() async {
        if (_loaded == modelId) await _unload();
        await files.importProjector(file, name, modelId);
      });
    }
  }

  @override
  Future<void> download(
    Uri url, {
    required String fileName,
    String? sha256,
    int? size,
    String? catalogId,
    String? projectorFor,
  }) async => (await _ready()).download(
    url,
    fileName: fileName,
    sha256: sha256,
    size: size,
    catalogId: catalogId,
    projectorFor: projectorFor,
  );

  @override
  void pauseDownload(String id) => _files?.pause(id);

  @override
  Future<void> removeDownload(String id) async =>
      (await _ready()).removeDownload(id);

  @override
  Future<void> delete(String modelId) => _exclusive(() async {
    if (_loaded == modelId) await _unload();
    await (await _ready()).delete(modelId);
  });

  @override
  Future<void> removeProjector(String modelId) => _exclusive(() async {
    if (_loaded == modelId) await _unload();
    await (await _ready()).removeProjector(modelId);
  });

  @override
  Future<void> unload() => _exclusive(_unload);

  Future<void> _unload() async {
    final runner = _runner;
    _runner = null;
    _loaded = _loadedKey = null;
    notifyListeners();
    await runner?.unload();
  }

  /// Waits for every earlier response and model change; call the result when
  /// done.
  Future<void Function()> _acquire() {
    final previous = _queue;
    final released = Completer<void>();
    _queue = released.future;
    return previous.then((_) => released.complete);
  }

  Future<T> _exclusive<T>(Future<T> Function() work) async {
    final release = await _acquire();
    try {
      return await work();
    } finally {
      release();
    }
  }

  @override
  Stream<ProviderEvent> generate(
    ProviderConfig config,
    ChatRequest request, {
    required CancelToken cancel,
  }) async* {
    // One response at a time: llama.cpp holds a single context.
    final release = await _acquire();
    try {
      if (cancel.isCancelled) return;
      yield* _generate(config, request, cancel);
    } finally {
      release();
    }
  }

  Stream<ProviderEvent> _generate(
    ProviderConfig config,
    ChatRequest request,
    CancelToken cancel,
  ) async* {
    final files = await _ready();
    LocalModel? find() =>
        files.models.where((m) => m.id == config.model).firstOrNull;
    // The folder is read lazily; a model added since is found by reading it.
    if (find() == null) await files.refresh();
    final model = find();
    if (model == null) {
      yield const ProviderError(
        'The model file is not on this device',
        code: 'model_missing',
      );
      return;
    }
    final contextSize =
        config.capabilities.contextWindow ?? LocalModel.defaultContext;
    final projector = model.projector == null
        ? null
        : files.path(model.projector!);
    final threads = llamaThreads(_processors, preferSpeed: preferSpeed);
    final key = '${model.id}\n$projector\n$contextSize\n$threads';
    final runner = _runner ??= _runnerFactory();
    if (_loadedKey != key) {
      _loading = model.id;
      notifyListeners();
      try {
        await runner.load(
          files.path(model.id),
          projector,
          contextSize: contextSize,
          threads: threads,
        );
        _loaded = model.id;
        _loadedKey = key;
      } catch (error) {
        await _unload();
        yield ProviderError(
          'Could not load the model: ${_describe(error)}',
          code: 'model_load',
        );
        return;
      } finally {
        _loading = null;
        notifyListeners();
      }
    }
    if (cancel.isCancelled) return;
    final generation = llamaGeneration(config, request);
    void stop() => runner.cancel();
    cancel.addListener(stop);
    try {
      await for (final event in providerEvents(
        runner.create(
          llamaMessages(request, vision: projector != null),
          params: generation.params,
          tools: request.tools.isEmpty ? null : llamaTools(request.tools),
          thinking: generation.thinking,
        ),
      )) {
        // A stopped generation ends like a finished one; it is neither.
        if (cancel.isCancelled) return;
        yield event;
      }
    } catch (error) {
      if (!cancel.isCancelled) {
        yield ProviderError(
          'The model failed: ${_describe(error)}',
          code: 'generation_failed',
        );
      }
    } finally {
      cancel.removeListener(stop);
    }
  }

  static String _describe(Object error) {
    final text = error.toString();
    return text.length > 300 ? '${text.substring(0, 300)}…' : text;
  }
}
