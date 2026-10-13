import 'dart:async';

import 'package:flutter/services.dart';

/// ActivityKit is a status surface; the native task grants finite background time.
class IosRemoteSession {
  static const _channel = MethodChannel('tw.avianjay.tako/remote_session');
  IosRemoteSession({required this.onStop}) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'stop' || call.method == 'backgroundExpired') onStop();
    });
  }
  final void Function() onStop;
  Future<void> setActive(bool active) => _send(active ? 'start' : 'end');
  Future<void> progress(String method, int count) =>
      _send('progress', {'method': method, 'count': count});
  Future<void> _send(String method, [Map<String, Object?>? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on PlatformException {
      /* Live Activities may be disabled by the user. */
    } on MissingPluginException {
      /* Tests and older hosts. */
    }
  }
}
