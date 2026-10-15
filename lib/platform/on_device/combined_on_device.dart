import 'dart:async';

import '../../core/on_device/on_device_capability.dart';
import '../../core/providers/providers.dart';

/// Keeps file models and the system models (AICore or Apple Intelligence)
/// behind the same provider. Serializes responses and releases the other
/// engine before switching.
class CombinedOnDevice extends OnDeviceCapability {
  CombinedOnDevice({required this.files, required this.system}) {
    files.addListener(notifyListeners);
    system.addListener(notifyListeners);
  }

  final OnDeviceCapability files;
  final OnDeviceCapability system;
  Future<void> _queue = Future.value();

  @override
  bool get isAvailable => files.isAvailable || system.isAvailable;
  @override
  List<LocalModel> get models => [...system.models, ...files.models];
  @override
  List<ModelDownload> get downloads => files.downloads;
  @override
  String? get loadedModel => system.loadedModel ?? files.loadedModel;
  @override
  String? get loadingModel => system.loadingModel ?? files.loadingModel;
  @override
  int get storageBytes => files.storageBytes;
  @override
  SystemModelStatus? get systemModelStatus => system.systemModelStatus;
  @override
  List<SystemModelStatus> get systemModelStatuses => system.systemModelStatuses;

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
  Future<void> refresh() async =>
      Future.wait([files.refresh(), system.refresh()]);
  @override
  Future<void> prepareSystemModel({String modelId = 'aicore:gemini-nano'}) =>
      _exclusive(() async {
        await files.unload();
        await system.prepareSystemModel(modelId: modelId);
      });
  @override
  Future<LocalModel?> importModel() => files.importModel();
  @override
  Future<void> importProjector(String modelId) =>
      files.importProjector(modelId);
  @override
  Future<void> download(
    Uri url, {
    required String fileName,
    String? sha256,
    int? size,
    String? catalogId,
    String? projectorFor,
  }) => files.download(
    url,
    fileName: fileName,
    sha256: sha256,
    size: size,
    catalogId: catalogId,
    projectorFor: projectorFor,
  );
  @override
  void pauseDownload(String id) => files.pauseDownload(id);
  @override
  Future<void> removeDownload(String id) => files.removeDownload(id);
  @override
  Future<void> delete(String modelId) async {
    if (isSystemModel(modelId)) {
      throw const OnDeviceException('system_model');
    }
    await files.delete(modelId);
  }

  @override
  Future<void> removeProjector(String modelId) =>
      files.removeProjector(modelId);
  @override
  Future<void> unload() => _exclusive(() async {
    await system.unload();
    await files.unload();
  });

  @override
  Stream<ProviderEvent> generate(
    ProviderConfig config,
    ChatRequest request, {
    required CancelToken cancel,
  }) async* {
    final release = await _acquire();
    try {
      if (cancel.isCancelled) return;
      final useSystem = isSystemModel(config.model);
      final engine = useSystem ? system : files;
      final other = useSystem ? files : system;
      if (other.loadedModel != null) await other.unload();
      if (cancel.isCancelled) return;
      files.preferSpeed = preferSpeed;
      yield* engine.generate(config, request, cancel: cancel);
    } finally {
      release();
    }
  }

  @override
  void dispose() {
    files.removeListener(notifyListeners);
    system.removeListener(notifyListeners);
    files.dispose();
    system.dispose();
    super.dispose();
  }
}
