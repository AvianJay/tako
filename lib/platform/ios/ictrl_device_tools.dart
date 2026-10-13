import '../../core/providers/cancel_token.dart';
import '../device_tools_capability.dart';
import 'ictrl_screen.dart';

/// Adds app launching to native iOS tools while iCTRL is paired.
class IctrlDeviceTools implements DeviceToolsCapability {
  IctrlDeviceTools({required this.screen, required this.native});
  final IctrlScreen screen;
  final DeviceToolsCapability native;
  final _apps = <String, String>{};
  @override
  bool get isAvailable => native.isAvailable || screen.isAvailable;
  @override
  bool supports(String tool) =>
      native.supports(tool) ||
      {'open_app', 'open_url'}.contains(tool) && screen.isAvailable;
  @override
  Future<Map<String, Object?>> invoke(
    String tool,
    Map<String, Object?> arguments, {
    required CancelToken cancel,
  }) async {
    if (tool == 'open_url' && screen.isAvailable) {
      cancel.throwIfCancelled();
      screen.beginModelSession();
      try {
        await screen.rpc('open_url', {'url': arguments['url']});
      } on Exception {
        throw const DeviceToolException(
          'url_open_failed_check_screen_before_retry',
        );
      }
      return {'remote_opened': true};
    }
    if (tool != 'open_app') {
      return native.invoke(tool, arguments, cancel: cancel);
    }
    if (!screen.isAvailable) throw const DeviceToolException('unavailable');
    final name = arguments['name'] as String? ?? '';
    var bundle = arguments['package'] as String? ?? _apps[name];
    if (bundle == null) {
      final found = await screen.rpc('resolve_app', {'text': name}, cancel);
      final apps = (found['apps'] as List? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .toList();
      if (apps.length != 1) {
        throw DeviceToolException(
          apps.isEmpty ? 'app_not_found' : 'ambiguous_app',
          details: {
            'candidates': apps
                .take(5)
                .map((a) => {'name': a['name'], 'package': a['bundle_id']})
                .toList(),
          },
        );
      }
      bundle = apps.single['bundle_id'] as String;
      _apps[name] = bundle;
    }
    cancel.throwIfCancelled();
    screen.beginModelSession();
    try {
      await screen.rpc('launch_app', {'bundle_id': bundle, 'settle': false});
    } on Exception {
      throw const DeviceToolException(
        'app_launch_failed_check_screen_before_retry',
      );
    }
    return {'launched': true, 'bundle_id': bundle};
  }
}
