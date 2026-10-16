import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../app/app_info.dart';
import '../../core/permissions/permission_gate.dart';
import '../../core/screen/remote_screen.dart';
import '../../core/screen/screen_capability.dart';
import '../../core/screen/screen_reading.dart';
import '../../l10n/gen/app_localizations.dart';
import '../chat/tool_widgets.dart';

/// Connects device control with the UI while the app may be hidden behind
/// the app the model operates:
/// - reports whether the app is in front;
/// - shows the ongoing "controlling the screen" notification with Stop;
/// - draws pending approvals over other apps (or, without screen control,
///   posts a notification that opens the app);
/// - posts "replied" when a response that used the screen ends while hidden.
class DeviceControlBridge extends ConsumerStatefulWidget {
  const DeviceControlBridge({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<DeviceControlBridge> createState() =>
      _DeviceControlBridgeState();
}

class _DeviceControlBridgeState extends ConsumerState<DeviceControlBridge>
    with WidgetsBindingObserver {
  late final AppController _app = ref.read(appControllerProvider);
  PermissionRequest? _overlaid;
  PermissionRequest? _alerted;
  bool _sessionShown = false;
  bool _usedScreen = false;
  bool _wasGenerating = false;
  bool _replyShown = false;
  (String, String, String)? _sessionNotice;
  (String, String, String, ScreenSessionPhase)? _controlStatus;
  String? _controlSessionId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _app.addListener(_sync);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _app.removeListener(_sync);
    final notifications = _app.services.notifications;
    if (_overlaid != null) _app.services.screen.hideApproval();
    if (_sessionShown) unawaited(notifications.clearSession());
    if (_controlSessionId != null) {
      _app.services.screen.hideControlOverlay(sessionId: _controlSessionId);
    }
    if (_alerted != null) unawaited(notifications.cancelAlert('approval'));
    if (_replyShown) unawaited(notifications.cancelAlert('reply'));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Inactive still shows the app (e.g. under the notification shade).
    _app.setAppForeground(
      state == AppLifecycleState.resumed || state == AppLifecycleState.inactive,
    );
    _sync();
  }

  /// The system is short of memory: an idle on-device model is most of what
  /// Tako holds, and it loads again for the next response.
  @override
  void didHaveMemoryPressure() {
    if (!_app.busy) unawaited(_app.services.onDevice.unload());
  }

  void _sync() {
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    final screen = _app.services.screen;
    final notifications = _app.services.notifications;
    final pending = _app.pendingApproval;
    final session = screen.modelSession;
    final phase = pending != null
        ? ScreenSessionPhase.waitingApproval
        : session?.phase ?? ScreenSessionPhase.acting;
    final title = switch (phase) {
      ScreenSessionPhase.thinking => l.screenSessionThinking,
      ScreenSessionPhase.waitingApproval => l.screenSessionWaiting,
      ScreenSessionPhase.acting =>
        session?.title.isNotEmpty == true ? session!.title : l.readScreenTool,
    };

    if (screen.modelActive != _sessionShown) {
      _sessionShown = screen.modelActive;
      if (_sessionShown) {
        _usedScreen = true;
      }
    }
    final notice = screen.modelActive
        ? (session?.id ?? '', l.screenSessionTitle(kAppName), title)
        : null;
    if (notice != _sessionNotice) {
      _sessionNotice = notice;
      if (notice == null) {
        unawaited(notifications.clearSession());
      } else {
        unawaited(
          notifications.showSession(
            title: notice.$2,
            body: notice.$3,
            stop: l.stop,
            channel: l.screenChannel,
          ),
        );
      }
    }
    final control =
        screen.modelActive && !_app.appInForeground && session != null
        ? (session.id, l.screenSessionTitle(kAppName), title, phase)
        : null;
    if (control != _controlStatus) {
      _controlStatus = control;
      if (control == null) {
        if (_controlSessionId != null) {
          screen.hideControlOverlay(
            sessionId: _controlSessionId,
            endSession: !screen.modelActive,
          );
          _controlSessionId = null;
        }
      } else {
        _controlSessionId = control.$1;
        unawaited(
          screen.showControlOverlay(
            ScreenControlOverlay(
              sessionId: control.$1,
              label: control.$2,
              title: control.$3,
              stop: l.stop,
              phase: control.$4,
            ),
          ),
        );
      }
    }

    if (_wasGenerating && !_app.isGenerating) {
      if (_usedScreen && !_app.appInForeground) {
        _replyShown = true;
        unawaited(
          notifications.showAlert(
            'reply',
            title: l.replyReadyTitle(kAppName),
            body: l.replyReadyBody,
            channel: l.alertChannel,
          ),
        );
      }
      _usedScreen = false;
    }
    _wasGenerating = _app.isGenerating;
    if (_replyShown && _app.appInForeground) {
      _replyShown = false;
      unawaited(notifications.cancelAlert('reply'));
    }

    if (pending == null || _app.appInForeground) {
      // In front, the in-app approval sheet takes over.
      if (_overlaid != null) {
        _overlaid = null;
        screen.hideApproval();
      }
      if (_alerted != null) {
        _alerted = null;
        unawaited(notifications.cancelAlert('approval'));
      }
      return;
    }
    if (identical(pending, _overlaid) || identical(pending, _alerted)) return;
    // iOS has no approval overlay. Keep the request pending for the in-app
    // approval sheet; never turn lack of an overlay into an automatic denial.
    if (screen is RemoteScreen && !screen.canOverlayApproval) return;
    if (screen.isAvailable) {
      _overlaid = pending;
      unawaited(_showOverApps(pending, l));
    } else {
      _alerted = pending;
      unawaited(
        notifications.showAlert(
          'approval',
          title: l.approvalNeededTitle(kAppName),
          body: l.approvalNeededBody,
          channel: l.alertChannel,
        ),
      );
    }
  }

  Future<void> _showOverApps(
    PermissionRequest request,
    AppLocalizations l,
  ) async {
    final target = request.target is ScreenTarget
        ? request.target! as ScreenTarget
        : null;
    final choice = await _app.services.screen.showApproval(
      ScreenApproval(
        title: l.approvalTitle,
        subtitle:
            '${toolLabel(request.toolName, l)} · ${riskLabel(request.risk, l)}',
        details: [
          for (final MapEntry(:key, :value) in request.details.entries)
            (approvalDetailLabel(key, l), value),
        ],
        note: l.approvalBody,
        arguments: const JsonEncoder.withIndent(
          '  ',
        ).convert(request.arguments),
        choices: [
          for (final choice in request.choices)
            (choice.name, choiceLabel(choice, l)),
        ],
        denyId: PermissionChoice.deny.name,
        highRisk: request.risk == RiskLevel.high,
        highlight: target == null
            ? null
            : target.isPoint
            ? ScreenBounds(
                target.x!.round() - 24,
                target.y!.round() - 24,
                target.x!.round() + 24,
                target.y!.round() + 24,
              )
            : target.bounds,
      ),
    );
    if (identical(_overlaid, request)) _overlaid = null;
    // Ignore a stale answer: only the request still pending may be decided.
    if (choice == null || !identical(_app.pendingApproval, request)) return;
    for (final value in PermissionChoice.values) {
      if (value.name == choice) _app.decideApproval(value);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
