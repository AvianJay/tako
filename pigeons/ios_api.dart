import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'tako',
    dartOut: 'lib/platform/ios/ios_api.g.dart',
    swiftOut: 'ios/Runner/IosApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'IosApiError'),
  ),
)
/// iOS-only services of the host app.
@HostApi()
abstract class IosApi {
  /// Keeps the directory at [path] out of iCloud and computer backups.
  void excludeFromBackup(String path);

  /// Opens [url] in the app that handles it; false when none does.
  @async
  bool openUrl(String url);
}

/// Calls from the host app.
@FlutterApi()
abstract class IosEvents {
  /// A Shortcut started by run_shortcut called back to `tako://shortcut/`
  /// [id] with [status] `success`, `error` or `cancel`.
  void shortcutFinished(
    String id,
    String status,
    String? result,
    String? errorMessage,
  );
}
