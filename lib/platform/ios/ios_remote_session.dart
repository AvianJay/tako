import 'dart:async';

import 'package:flutter/services.dart';

/// ActivityKit is a status surface; the native task grants finite background time.
class IosRemoteSession {
  static const _channel = MethodChannel('tw.avianjay.tako/remote_session');
  IosRemoteSession({
    required this.onStop,
    this.onDiagnostics,
    this.onReturnToApp,
  }) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'stop' || call.method == 'backgroundExpired') {
        _diagnostics({
          'processing_state': 'expired',
          'stop_reason': call.method == 'backgroundExpired'
              ? 'system_expiration'
              : 'user_stop',
        });
        onStop();
      }
      if (call.method == 'diagnosticsChanged') _diagnostics(call.arguments);
    });
  }
  final void Function() onStop;
  final void Function(Map<String, Object?> values)? onDiagnostics;
  final Future<void> Function()? onReturnToApp;
  Future<void> _pending = Future<void>.value();
  void _diagnostics(Object? value) {
    if (value is Map) {
      onDiagnostics?.call(Map<String, Object?>.from(value));
    }
  }

  Future<void> setActive(bool active) {
    final operation = _pending.then((_) async {
      if (!active) {
        try {
          // Keep native background time until iCTRL brings the local app back.
          await onReturnToApp?.call();
        } catch (_) {
          // Returning is best effort; native resources must always be released.
        }
      }
      await _send(active ? 'start' : 'end');
      await refreshDiagnostics();
    });
    _pending = operation.catchError((Object _) {});
    return operation;
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
