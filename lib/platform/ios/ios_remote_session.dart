import 'dart:async';

import 'package:flutter/services.dart';

/// ActivityKit is a status surface; the native task grants finite background time.
class IosRemoteSession {
  static const _channel = MethodChannel('tw.avianjay.tako/remote_session');
  IosRemoteSession({required this.onStop, this.onDiagnostics}) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'stop' || call.method == 'backgroundExpired') onStop();
      if (call.method == 'diagnosticsChanged') _diagnostics(call.arguments);
    });
  }
  final void Function() onStop;
  final void Function(Map<String, Object?> values)? onDiagnostics;
  void _diagnostics(Object? value) {
    if (value is Map) {
      onDiagnostics?.call(Map<String, Object?>.from(value));
    }
  }

  Future<void> setActive(bool active) async {
    await _send(active ? 'start' : 'end');
    await refreshDiagnostics();
  }

  Future<void> refreshDiagnostics() async {
    try {
      _diagnostics(await _channel.invokeMethod<Object?>('diagnostics'));
    } on PlatformException {
      // Diagnostic availability does not control device actions.
    } on MissingPluginException {
      // Tests and non-iOS hosts.
    }
  }

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
