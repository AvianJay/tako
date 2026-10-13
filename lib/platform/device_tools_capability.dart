import '../core/providers/cancel_token.dart';
import 'capabilities.dart';

/// Device reads and actions are invoked only after the tool permission gate.
/// No implementation may prefetch private data while discovering capabilities.
abstract interface class DeviceToolsCapability implements Capability {
  bool supports(String tool);
  Future<Map<String, Object?>> invoke(
    String tool,
    Map<String, Object?> arguments, {
    required CancelToken cancel,
  });
}

class DeviceToolException implements Exception {
  const DeviceToolException(this.code, {this.details = const {}});
  final String code;

  /// Extra fields for the model, e.g. candidate apps for an ambiguous name.
  final Map<String, Object?> details;
  @override
  String toString() => code;
}

class UnavailableDeviceTools implements DeviceToolsCapability {
  const UnavailableDeviceTools();
  @override
  bool get isAvailable => false;
  @override
  bool supports(String tool) => false;
  @override
  Future<Map<String, Object?>> invoke(
    String tool,
    Map<String, Object?> arguments, {
    required CancelToken cancel,
  }) async => throw const DeviceToolException('unavailable');
}

const deviceToolNames = <String>{
  'get_device_status',
  'get_location',
  'clipboard_read',
  'clipboard_write',
  'calendar_list',
  'calendar_add',
  'set_alarm',
  'set_timer',
  'open_url',
  'open_app',
  'resolve_app',
};
