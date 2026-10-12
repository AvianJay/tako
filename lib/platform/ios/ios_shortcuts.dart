import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

import '../../core/providers/cancel_token.dart';
import '../../core/shortcuts/shortcuts_capability.dart';
import 'ios_api.g.dart';

/// Runs Shortcuts through the Shortcuts app's x-callback-url API; it calls
/// back to `tako://shortcut/<id>/<status>` when the Shortcut ends.
class IosShortcuts extends ShortcutsCapability implements IosEvents {
  IosShortcuts({IosApi? api, bool listen = true}) : _api = api ?? IosApi() {
    if (listen) IosEvents.setUp(this);
  }

  final IosApi _api;
  final _pending = <String, Completer<ShortcutResult>>{};
  static final _random = Random.secure();

  @override
  bool get isAvailable => true;

  /// The Shortcuts URL for one run. Components are percent-encoded: the
  /// Shortcuts app does not read `+` as a space.
  static Uri runUrl(String id, String name, String? input) {
    String encode(String value) => Uri.encodeComponent(value);
    final callback = 'tako://shortcut/$id';
    return Uri.parse(
      'shortcuts://x-callback-url/run-shortcut'
      '?name=${encode(name)}'
      '${input == null ? '' : '&input=text&text=${encode(input)}'}'
      '&x-success=${encode('$callback/success')}'
      '&x-error=${encode('$callback/error')}'
      '&x-cancel=${encode('$callback/cancel')}',
    );
  }

  @override
  Future<ShortcutResult> run(
    String name, {
    String? input,
    required Duration timeout,
    required CancelToken cancel,
  }) async {
    cancel.throwIfCancelled();
    final id = List.generate(
      16,
      (_) => _random.nextInt(16).toRadixString(16),
    ).join();
    final done = _pending[id] = Completer<ShortcutResult>();
    try {
      final opened = await _api.openUrl(runUrl(id, name, input).toString());
      if (!opened) throw const ShortcutException('shortcuts_not_opened');
      return await cancel.bind(done.future.timeout(timeout));
    } on TimeoutException {
      throw const ShortcutException('timeout');
    } on PlatformException {
      throw const ShortcutException('shortcuts_not_opened');
    } finally {
      _pending.remove(id);
    }
  }

  @override
  void shortcutFinished(
    String id,
    String status,
    String? result,
    String? errorMessage,
  ) {
    final done = _pending.remove(id);
    if (done == null || done.isCompleted) return;
    done.complete(
      ShortcutResult(
        status: const {'success', 'error', 'cancel'}.contains(status)
            ? status
            : 'error',
        output: result,
        error: errorMessage,
      ),
    );
  }
}
