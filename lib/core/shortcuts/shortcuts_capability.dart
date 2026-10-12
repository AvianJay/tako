import 'package:flutter/foundation.dart';

import '../../platform/capabilities.dart';
import '../providers/cancel_token.dart';

class ShortcutResult {
  const ShortcutResult({required this.status, this.output, this.error});

  /// `success`, `error` or `cancel`, as the Shortcuts app reports it.
  final String status;

  /// Text the Shortcut returned. Untrusted.
  final String? output;
  final String? error;
}

class ShortcutException implements Exception {
  const ShortcutException(this.code);

  /// `unavailable`, `shortcuts_not_opened` or `timeout`.
  final String code;
  @override
  String toString() => code;
}

/// list_shortcuts and run_shortcut: the user's Shortcuts on iOS. iOS cannot
/// list them to apps, so the user names the ones the model may see and run.
abstract class ShortcutsCapability extends ChangeNotifier
    implements Capability {
  /// The Shortcuts the user allowed, by their exact names.
  List<String> names = const [];

  /// Opens the Shortcuts app to run [name] and waits for it to call back.
  Future<ShortcutResult> run(
    String name, {
    String? input,
    required Duration timeout,
    required CancelToken cancel,
  });
}

class UnavailableShortcuts extends ShortcutsCapability {
  @override
  bool get isAvailable => false;
  @override
  Future<ShortcutResult> run(
    String name, {
    String? input,
    required Duration timeout,
    required CancelToken cancel,
  }) async => throw const ShortcutException('unavailable');
}
