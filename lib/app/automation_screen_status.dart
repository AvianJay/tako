import '../core/notifications/notification_capability.dart';
import '../core/screen/screen_capability.dart';
import '../l10n/gen/app_localizations.dart';
import 'app_info.dart';

/// Shows the existing native frame and Stop notification without a widget tree.
/// Updates drain before the execution lease is released.
class AutomationScreenStatus {
  AutomationScreenStatus({
    required this.screen,
    required this.notifications,
    required this.strings,
  }) {
    screen.addListener(_changed);
    _changed();
  }
  final ScreenCapability screen;
  final NotificationCapability notifications;
  final AppLocalizations strings;
  Future<void> _pending = Future.value();
  (String, String, ScreenSessionPhase)? _last;
  String? _shown;
  bool _closed = false;
  void _changed() {
    if (_closed) {
      return;
    }
    final session = screen.modelSession;
    final title = switch (session?.phase) {
      ScreenSessionPhase.thinking => strings.screenSessionThinking,
      ScreenSessionPhase.waitingApproval => strings.screenSessionWaiting,
      _ =>
        session?.title.isNotEmpty == true
            ? session!.title
            : strings.readScreenTool,
    };
    final stamp = session == null ? null : (session.id, title, session.phase);
    if (stamp == _last) {
      return;
    }
    _last = stamp;
    _pending = _pending
        .then((_) async {
          if (stamp == null) {
            await _clear();
            return;
          }
          if (_closed || screen.modelSession?.id != stamp.$1) {
            return;
          }
          _shown = stamp.$1;
          await screen.showControlOverlay(
            ScreenControlOverlay(
              sessionId: stamp.$1,
              label: strings.screenSessionTitle(kAppName),
              title: stamp.$2,
              stop: strings.stop,
              phase: stamp.$3,
            ),
          );
          await notifications.showSession(
            title: strings.screenSessionTitle(kAppName),
            body: stamp.$2,
            stop: strings.stop,
            channel: strings.screenChannel,
          );
        })
        .catchError((Object _) {});
  }

  Future<void> flush() => _pending;
  Future<void> _clear() async {
    final shown = _shown;
    if (shown == null) {
      return;
    }
    _shown = null;
    screen.hideControlOverlay(sessionId: shown, endSession: false);
    await notifications.clearSession();
  }

  Future<void> dispose() async {
    _closed = true;
    screen.removeListener(_changed);
    await _pending;
    await _clear();
  }
}
