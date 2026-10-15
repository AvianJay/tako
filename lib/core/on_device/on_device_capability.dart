import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../platform/capabilities.dart';
import '../providers/providers.dart';
import 'gguf.dart';

/// A model file or a model managed by the device's system service.
class LocalModel {
  const LocalModel({
    required this.id,
    required this.sizeBytes,
    required GgufInfo this.info,
    this.projector,
    this.catalogId,
  }) : _systemProfile = null,
       _name = null;

  const LocalModel.system({
    required this.id,
    required String name,
    required ModelProfile profile,
  }) : sizeBytes = 0,
       info = null,
       projector = null,
       catalogId = null,
       _name = name,
       _systemProfile = profile;

  /// The file name or a reserved system model ID, shared by settings and chats.
  final String id;
  final int sizeBytes;
  final GgufInfo? info;
  final String? _name;
  final ModelProfile? _systemProfile;
  bool get isSystem => _systemProfile != null;
  String get displayName => _name ?? info?.name ?? id;

  /// File name of the vision projector loaded with this model.
  final String? projector;

  /// The recommended model this file was downloaded as.
  final String? catalogId;

  /// Settings for a newly added model. Memory grows with the context, so it
  /// starts small; thinking is slow on a phone, so it starts off.
  ModelProfile profile() =>
      _systemProfile ??
      ModelProfile(
        id: id,
        autoDetect: true,
        capabilities: ProviderCapabilities(
          tools: info!.supportsTools,
          vision: projector != null,
          reasoning: info!.supportsThinking,
          contextWindow: min(
            info!.contextLength ?? defaultContext,
            defaultContext,
          ),
        ),
        maxOutputTokens: 2048,
      );

  static const defaultContext = 8192;
}

const aicoreModel = LocalModel.system(
  id: 'aicore:gemini-nano',
  name: 'Gemini Nano (AICore)',
  // A conservative chat budget; the service rejects requests beyond its limit.
  profile: ModelProfile(
    id: 'aicore:gemini-nano',
    autoDetect: true,
    capabilities: ProviderCapabilities(contextWindow: 4096),
    maxOutputTokens: 1024,
  ),
);

const aicorePreviewModel = LocalModel.system(
  id: 'aicore:gemini-nano-preview',
  name: 'Gemini Nano (AICore Preview)',
  profile: ModelProfile(
    id: 'aicore:gemini-nano-preview',
    autoDetect: true,
    capabilities: ProviderCapabilities(contextWindow: 4096),
    maxOutputTokens: 1024,
  ),
);

bool isAicoreModel(String id) =>
    id == aicoreModel.id || id == aicorePreviewModel.id;

/// Apple's on-device foundation model. Instructions, prompt and reply share
/// its documented 4,096-token context.
const appleModel = LocalModel.system(
  id: 'apple:foundation-model',
  name: 'Apple Foundation Model',
  profile: ModelProfile(
    id: 'apple:foundation-model',
    autoDetect: true,
    capabilities: ProviderCapabilities(tools: true, contextWindow: 4096),
    maxOutputTokens: 1024,
  ),
);

/// Image Playground, which takes a prompt and at most one reference image.
const appleImageModel = LocalModel.system(
  id: 'apple:image-playground',
  name: 'Image Playground',
  profile: ModelProfile(
    id: 'apple:image-playground',
    autoDetect: true,
    capabilities: ProviderCapabilities(
      contextWindow: 4096,
      imageGeneration: ImageGenerationMode.onDevice,
      imageReferenceInput: true,
    ),
    maxOutputTokens: 1024,
  ),
);

bool isAppleModel(String id) => id == appleModel.id || id == appleImageModel.id;

/// Models that the system stores and runs, so there is no file to delete.
bool isSystemModel(String id) => isAicoreModel(id) || isAppleModel(id);

enum SystemModelState { unavailable, available, preparing, ready, failed }

class SystemModelStatus {
  const SystemModelStatus(this.state, {this.error, this.model = aicoreModel});
  final SystemModelState state;
  final String? error;
  final LocalModel model;
}

enum DownloadState { running, verifying, paused, failed }

/// A model or projector being downloaded into the model folder. A paused or
/// failed download keeps its partial file and resumes where it stopped.
class ModelDownload {
  const ModelDownload({
    required this.id,
    required this.url,
    required this.received,
    this.total,
    this.state = DownloadState.running,
    this.error,
    this.projectorFor,
    this.catalogId,
  });

  /// The file name the download becomes.
  final String id;
  final Uri url;
  final int received;
  final int? total;
  final DownloadState state;

  /// An [OnDeviceException.code].
  final String? error;

  /// The model this projector is for.
  final String? projectorFor;
  final String? catalogId;

  double? get fraction =>
      total == null || total == 0 ? null : (received / total!).clamp(0, 1);
}

class OnDeviceException implements Exception {
  const OnDeviceException(this.code);

  /// `not_gguf`, `is_projector`, `not_projector`, `exists`, `unsupported_url`,
  /// `http_<status>`, `checksum`, `size`, `no_space`, `network` or
  /// `model_missing`.
  final String code;
  @override
  String toString() => code;
}

/// Runs local models and manages files owned by the app.
/// Models live outside the workspace, so file tools never see them.
abstract class OnDeviceCapability extends ChangeNotifier implements Capability {
  /// Null on platforms without system models (AICore or Apple Intelligence).
  /// Checking availability never downloads a model; preparation is
  /// explicitly started by the user.
  SystemModelStatus? get systemModelStatus => null;
  List<SystemModelStatus> get systemModelStatuses => [?systemModelStatus];
  Future<void> prepareSystemModel({
    String modelId = 'aicore:gemini-nano',
  }) async => throw const OnDeviceException('aicore_unavailable');

  /// Models, not projectors: a projector belongs to its model.
  List<LocalModel> get models;
  List<ModelDownload> get downloads;

  /// The model in memory, if any.
  String? get loadedModel;

  /// The model being read into memory for a response.
  String? get loadingModel;

  /// Bytes used by models, projectors and partial downloads.
  int get storageBytes;

  /// Use more CPU cores: faster answers, but the phone may stutter. The next
  /// response loads the model again with the new setting.
  bool preferSpeed = false;

  Future<void> refresh();

  /// Lets the user pick a GGUF file and moves it into the model folder.
  /// Null when the picker is dismissed.
  Future<LocalModel?> importModel();

  /// Lets the user pick a vision projector for [modelId].
  Future<void> importProjector(String modelId);

  /// Starts or resumes a download. [sha256] and [size], when known, are
  /// checked before the file is used.
  Future<void> download(
    Uri url, {
    required String fileName,
    String? sha256,
    int? size,
    String? catalogId,
    String? projectorFor,
  });

  /// Stops a download and keeps what was received.
  void pauseDownload(String id);

  /// Stops a download and deletes what was received.
  Future<void> removeDownload(String id);

  /// Deletes the model with its projector.
  Future<void> delete(String modelId);
  Future<void> removeProjector(String modelId);

  /// Frees the memory the loaded model uses.
  Future<void> unload();

  /// [config] names the model and its context, output and thinking settings.
  /// A missing file model ends with a `model_missing` error. System models
  /// are addressed by their reserved IDs and prepared by the system service.
  Stream<ProviderEvent> generate(
    ProviderConfig config,
    ChatRequest request, {
    required CancelToken cancel,
  });
}

class UnavailableOnDevice extends OnDeviceCapability {
  @override
  bool get isAvailable => false;
  @override
  List<LocalModel> get models => const [];
  @override
  List<ModelDownload> get downloads => const [];
  @override
  String? get loadedModel => null;
  @override
  String? get loadingModel => null;
  @override
  int get storageBytes => 0;
  @override
  Future<void> refresh() async {}
  @override
  Future<LocalModel?> importModel() async => null;
  @override
  Future<void> importProjector(String modelId) async {}
  @override
  Future<void> download(
    Uri url, {
    required String fileName,
    String? sha256,
    int? size,
    String? catalogId,
    String? projectorFor,
  }) async => throw const OnDeviceException('unavailable');
  @override
  void pauseDownload(String id) {}
  @override
  Future<void> removeDownload(String id) async {}
  @override
  Future<void> delete(String modelId) async {}
  @override
  Future<void> removeProjector(String modelId) async {}
  @override
  Future<void> unload() async {}
  @override
  Stream<ProviderEvent> generate(
    ProviderConfig config,
    ChatRequest request, {
    required CancelToken cancel,
  }) => Stream.value(
    const ProviderError(
      'On-device models are not available on this device',
      code: 'unavailable',
    ),
  );
}
