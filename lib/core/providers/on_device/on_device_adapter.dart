import '../../on_device/on_device_capability.dart';
import '../cancel_token.dart';
import '../provider_adapter.dart';
import '../provider_config.dart';
import '../provider_event.dart';

/// A model running inside the app. Nothing leaves the device.
class OnDeviceAdapter implements ProviderAdapter {
  OnDeviceAdapter(this.config, this.onDevice);
  final ProviderConfig config;
  final OnDeviceCapability onDevice;

  @override
  Stream<ProviderEvent> send(
    ChatRequest request, {
    required CancelToken cancel,
  }) async* {
    if (cancel.isCancelled) return;
    yield* onDevice.generate(config, request, cancel: cancel);
  }

  @override
  Future<List<ModelInfo>> listModels({CancelToken? cancel}) async {
    cancel?.throwIfCancelled();
    await onDevice.refresh();
    return [
      for (final model in onDevice.models)
        ModelInfo(id: model.id, displayName: model.info.name ?? model.id),
    ];
  }
}
