import 'screen_capability.dart';

enum RemoteScreenStatus {
  offline,
  connecting,
  pairing,
  ready,
  denied,
  failed,
  paused,
}

/// Setup is separate from screen reads; discovering a runner never reads apps.
abstract class RemoteScreen extends ScreenCapability {
  String get endpoint;
  RemoteScreenStatus get status;
  String? get errorCode;
  bool get canOverlayApproval => false;
  Future<void> connect({String? endpoint});
  Future<void> disconnect();
}
