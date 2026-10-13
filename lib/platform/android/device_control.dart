import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/notifications/notification_capability.dart';
import '../../core/providers/cancel_token.dart';
import '../../core/screen/screen_capability.dart';
import '../../core/shell/shell_capability.dart';
import 'control_api.g.dart';

/// Native error codes are produced by Tako's own Kotlin code. Anything else
/// (an unexpected exception name) is replaced, never shown to the model.
String _code(PlatformException error, String fallback) =>
    RegExp(r'^[a-z][a-z_]{1,60}$').hasMatch(error.code) ? error.code : fallback;

/// Screen control through the accessibility service (`full` flavor).
class AndroidScreen extends ScreenCapability {
  AndroidScreen({ScreenApi? api}) : _api = api ?? ScreenApi();
  final ScreenApi _api;
  bool _supported = false;
  bool _enabled = false;
  bool _screenshots = false;

  @override
  bool get supported => _supported;
  @override
  bool get enabled => _enabled;
  @override
  bool get screenshotsSupported => _screenshots;
  @override
  Set<ScreenObservationMode> get observationModes => isAvailable
      ? {
          ScreenObservationMode.elements,
          if (_screenshots) ScreenObservationMode.screenshot,
        }
      : const {};

  @override
  Future<void> refresh() async {
    try {
      final status = await _api.status();
      if (status.supported == _supported &&
          status.enabled == _enabled &&
          status.screenshots == _screenshots) {
        return;
      }
      _supported = status.supported;
      _enabled = status.enabled;
      _screenshots = status.screenshots;
      if (!_enabled) endModelSession();
      notifyListeners();
    } on PlatformException {
      // Keep the last known state.
    } on MissingPluginException {
      // No engine binding in this isolate.
    }
  }

  @override
  Future<void> openSettings() => _api.openSettings();
  @override
  Future<void> openAppInfo() => _api.openAppInfo();

  Future<T> _call<T>(Future<T> Function() call, CancelToken? cancel) async {
    cancel?.throwIfCancelled();
    try {
      return await (cancel == null ? call() : cancel.bind(call()));
    } on PlatformException catch (error) {
      cancel?.throwIfCancelled();
      final code = _code(error, 'screen_failed');
      if (code == 'screen_control_off') unawaited(refresh());
      throw ScreenException(code);
    } on MissingPluginException {
      throw const ScreenException('screen_control_off');
    }
  }

  @override
  Future<ScreenTree> snapshot({
    required bool screenshot,
    required CancelToken cancel,
  }) async {
    final data = await _call(() => _api.snapshot(screenshot, 1500), cancel);
    return ScreenTree(
      token: data.token,
      packageName: data.packageName,
      appLabel: data.appLabel,
      width: data.width,
      height: data.height,
      ownAppInFront: data.ownAppInFront,
      windows: [for (final window in data.windows) _window(window)],
      nodes: [for (final node in data.nodes) _node(node)],
      truncated: data.truncated,
      image: data.image,
      imageWidth: data.imageWidth,
      imageHeight: data.imageHeight,
    );
  }

  @override
  Future<ScreenTargetInfo> resolveNode(
    int token,
    int node,
    CancelToken cancel,
  ) async => _target(await _call(() => _api.resolveNode(token, node), cancel));

  @override
  Future<ScreenTargetInfo> resolvePoint(
    double x,
    double y,
    CancelToken cancel,
  ) async => _target(await _call(() => _api.resolvePoint(x, y), cancel));

  @override
  Future<ScreenTargetInfo> resolveFocus(CancelToken cancel) async =>
      _target(await _call(_api.resolveFocus, cancel));

  @override
  Future<ScreenActionOutcome> act(ScreenAction action) async {
    final result = await _call(
      () => _api.act(
        ScreenActionData(
          action: action.action,
          token: action.token,
          node: action.node,
          check: action.check,
          x: action.x,
          y: action.y,
          windowId: action.windowId,
          text: action.text,
          submit: action.submit,
          direction: action.direction,
          key: action.key,
        ),
      ),
      null,
    );
    return ScreenActionOutcome(
      method: result.method,
      packageName: result.packageName,
      appLabel: result.appLabel,
      changed: result.changed,
    );
  }

  @override
  void endModelSession() {
    final id = modelSession?.id;
    super.endModelSession();
    if (id != null) hideControlOverlay(sessionId: id, endSession: true);
  }

  @override
  Future<void> showControlOverlay(ScreenControlOverlay overlay) async {
    try {
      await _api.showControlOverlay(
        ControlOverlayData(
          sessionId: overlay.sessionId,
          label: overlay.label,
          title: overlay.title,
          stop: overlay.stop,
          phase: overlay.phase.name,
        ),
      );
    } on PlatformException {
      // The service may have been disabled while this update was queued.
    } on MissingPluginException {
      // No native screen control in this engine.
    }
  }

  @override
  void hideControlOverlay({String? sessionId, bool endSession = false}) {
    final id = sessionId ?? modelSession?.id;
    if (id == null) return;
    unawaited(
      _api.hideControlOverlay(id, endSession).catchError((Object _) {}),
    );
  }

  @override
  Future<String?> showApproval(ScreenApproval approval) async {
    try {
      final box = approval.highlight;
      return await _api.showApproval(
        ApprovalOverlayData(
          title: approval.title,
          subtitle: approval.subtitle,
          detailLabels: [for (final detail in approval.details) detail.$1],
          detailValues: [for (final detail in approval.details) detail.$2],
          note: approval.note,
          arguments: approval.arguments,
          choiceIds: [for (final choice in approval.choices) choice.$1],
          choiceLabels: [for (final choice in approval.choices) choice.$2],
          denyId: approval.denyId,
          highRisk: approval.highRisk,
          left: box?.left,
          top: box?.top,
          right: box?.right,
          bottom: box?.bottom,
        ),
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  void hideApproval() {
    unawaited(_api.hideApproval().catchError((Object _) {}));
  }

  static ScreenBounds _bounds(int left, int top, int right, int bottom) =>
      ScreenBounds(left, top, right, bottom);

  static ScreenWindow _window(ScreenWindowData data) => ScreenWindow(
    id: data.id,
    packageName: data.packageName,
    title: data.title,
    type: data.type,
    own: data.own,
    bounds: _bounds(data.left, data.top, data.right, data.bottom),
  );

  static ScreenNode _node(ScreenNodeData data) => ScreenNode(
    parent: data.parent,
    window: data.window,
    className: data.className,
    text: data.text,
    description: data.description,
    hint: data.hint,
    viewId: data.viewId,
    state: data.state,
    flags: data.flags,
    bounds: _bounds(data.left, data.top, data.right, data.bottom),
    check: data.check,
  );

  static ScreenTargetInfo _target(ScreenTargetData data) => ScreenTargetInfo(
    token: data.token,
    node: data.node,
    window: _window(data.window),
    appLabel: data.appLabel,
    target: data.target == null ? null : _node(data.target!),
    ancestors: [for (final node in data.ancestors) _node(node)],
    descendants: [for (final node in data.descendants) _node(node)],
    actionText: data.actionText,
    windowText: data.windowText,
    width: data.width,
    height: data.height,
  );
}

/// run_shell through Termux's RUN_COMMAND service.
class AndroidShell extends ShellCapability {
  AndroidShell({ShellApi? api}) : _api = api ?? ShellApi();
  final ShellApi _api;
  bool _installed = false;
  bool _permitted = false;
  static int _sequence = 0;

  @override
  bool get installed => _installed;
  @override
  bool get permitted => _permitted;
  @override
  String get environment => 'Termux on this phone';

  @override
  Future<void> refresh() async {
    try {
      final status = await _api.status();
      if (status.installed == _installed && status.permission == _permitted) {
        return;
      }
      _installed = status.installed;
      _permitted = status.permission;
      notifyListeners();
    } on PlatformException {
      // Keep the last known state.
    } on MissingPluginException {
      // No engine binding in this isolate.
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      return await _api.requestPermission();
    } on PlatformException {
      return false;
    } finally {
      await refresh();
    }
  }

  @override
  Future<bool> openSetup() async {
    try {
      return await _api.openTermux();
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<ShellResult> run(
    String command, {
    required Duration timeout,
    required CancelToken cancel,
  }) async {
    cancel.throwIfCancelled();
    final id = '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    var cancelled = false;
    void abort() {
      cancelled = true;
      unawaited(_api.cancel(id).catchError((Object _) {}));
    }

    cancel.addListener(abort);
    try {
      final result = await _api.run(id, command, timeout.inMilliseconds);
      if (result.error case final error?) {
        throw ShellException(
          RegExp(r'^[a-z][a-z_]{1,60}$').hasMatch(error)
              ? error
              : 'termux_error',
          result.errorMessage,
        );
      }
      return ShellResult(
        exitCode: result.exitCode,
        stdout: result.stdout,
        stderr: result.stderr,
        stdoutLength: result.stdoutLength,
        stderrLength: result.stderrLength,
      );
    } on PlatformException catch (error) {
      // The command was already sent: report it as cancelled, not failed.
      if (cancelled || error.code == 'cancelled') {
        return const ShellResult.cancelled();
      }
      throw ShellException(_code(error, 'termux_unavailable'));
    } on MissingPluginException {
      throw const ShellException('unavailable');
    } finally {
      cancel.removeListener(abort);
    }
  }
}

/// notifications_list through the notification listener, and Tako's own
/// notifications.
class AndroidNotifications extends NotificationCapability {
  AndroidNotifications({NotificationApi? api})
    : _api = api ?? NotificationApi();
  final NotificationApi _api;
  bool _access = false;
  bool _canPost = false;

  @override
  bool get access => _access;
  @override
  bool get canPost => _canPost;

  @override
  Future<void> refresh() async {
    try {
      final status = await _api.status();
      if (status.access == _access && status.canPost == _canPost) return;
      _access = status.access;
      _canPost = status.canPost;
      notifyListeners();
    } on PlatformException {
      // Keep the last known state.
    } on MissingPluginException {
      // No engine binding in this isolate.
    }
  }

  @override
  Future<void> openAccessSettings() => _api.openAccessSettings();

  @override
  Future<bool> requestPostPermission() async {
    try {
      return await _api.requestPostPermission();
    } on PlatformException {
      return false;
    } finally {
      await refresh();
    }
  }

  @override
  Future<List<DeviceNotification>> list({
    required int limit,
    required CancelToken cancel,
  }) async {
    cancel.throwIfCancelled();
    try {
      final items = await cancel.bind(_api.list(limit));
      return [
        for (final item in items)
          DeviceNotification(
            packageName: item.packageName,
            appLabel: item.appLabel,
            title: item.title,
            text: item.text,
            lines: item.lines,
            postedAt: DateTime.fromMillisecondsSinceEpoch(item.postedAt),
            ongoing: item.ongoing,
            category: item.category,
          ),
      ];
    } on PlatformException catch (error) {
      cancel.throwIfCancelled();
      throw NotificationException(_code(error, 'notification_read_failed'));
    } on MissingPluginException {
      throw const NotificationException('unavailable');
    }
  }

  Future<void> _quietly(Future<void> Function() call) async {
    try {
      await call();
    } on PlatformException {
      // Notifications are best-effort.
    } on MissingPluginException {
      // No engine binding in this isolate.
    }
  }

  @override
  Future<void> showSession({
    required String title,
    required String body,
    required String stop,
    required String channel,
  }) => _quietly(() => _api.showSession(title, body, stop, channel));

  @override
  Future<void> clearSession() => _quietly(_api.clearSession);

  @override
  Future<void> showAlert(
    String kind, {
    required String title,
    required String body,
    required String channel,
  }) => _quietly(() => _api.showAlert(kind, title, body, channel));

  @override
  Future<void> cancelAlert(String kind) =>
      _quietly(() => _api.cancelAlert(kind));
}

/// Routes native signals: Stop from the notification, and status changes
/// (the user toggled a service in system settings).
class AndroidControlEvents implements ControlEvents {
  AndroidControlEvents({required this.screen, required this.onStatusChanged});
  final ScreenCapability screen;
  final void Function() onStatusChanged;

  void attach() => ControlEvents.setUp(this);

  @override
  void stopRequested() => screen.takeOver();

  @override
  void statusChanged() => onStatusChanged();
}
