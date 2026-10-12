import 'package:flutter/foundation.dart';

import '../../platform/capabilities.dart';
import '../providers/cancel_token.dart';

class ShellException implements Exception {
  const ShellException(this.code, [this.message]);
  final String code;

  /// The shell environment's own explanation, e.g. a Termux setup error.
  final String? message;
  @override
  String toString() => code;
}

class ShellResult {
  const ShellResult({
    this.exitCode = -1,
    this.stdout = '',
    this.stderr = '',
    int? stdoutLength,
    int? stderrLength,
    this.cancelled = false,
  }) : stdoutLength = stdoutLength ?? stdout.length,
       stderrLength = stderrLength ?? stderr.length;

  /// Stop arrived after the command was sent; it may still be running.
  const ShellResult.cancelled()
    : exitCode = -1,
      stdout = '',
      stderr = '',
      stdoutLength = 0,
      stderrLength = 0,
      cancelled = true;

  final int exitCode;
  final String stdout;
  final String stderr;

  /// Lengths before the environment truncated the output.
  final int stdoutLength;
  final int stderrLength;
  final bool cancelled;
}

/// run_shell: Termux on Android.
abstract class ShellCapability extends ChangeNotifier implements Capability {
  bool get installed;

  /// The user granted the permission to run commands.
  bool get permitted;

  @override
  bool get isAvailable => installed && permitted;

  /// The template's `shell_env`.
  String get environment;

  Future<void> refresh();
  Future<bool> requestPermission();
  Future<bool> openSetup();

  /// Once sent, a command is committed: Stop returns
  /// [ShellResult.cancelled] instead of throwing, so its receipt is kept.
  Future<ShellResult> run(
    String command, {
    required Duration timeout,
    required CancelToken cancel,
  });
}

class UnavailableShell extends ShellCapability {
  @override
  bool get installed => false;
  @override
  bool get permitted => false;
  @override
  String get environment => '';
  @override
  Future<void> refresh() async {}
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<bool> openSetup() async => false;
  @override
  Future<ShellResult> run(
    String command, {
    required Duration timeout,
    required CancelToken cancel,
  }) async => throw const ShellException('unavailable');
}
