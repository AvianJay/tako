import 'package:flutter_test/flutter_test.dart';
import 'package:tako/app/automation_screen_status.dart';
import 'package:tako/core/notifications/notification_capability.dart';
import 'package:tako/core/screen/screen_capability.dart';
import 'package:tako/l10n/gen/app_localizations_en.dart';

class _Screen extends ScreenCapability {
  @override
  bool get supported => true;
  @override
  bool get enabled => true;
  @override
  bool get screenshotsSupported => false;
  @override
  Set<ScreenObservationMode> get observationModes => const {};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  bool get isAvailable => true;
  final overlays = <ScreenControlOverlay>[];
  final hidden = <String>[];
  @override
  Future<void> showControlOverlay(ScreenControlOverlay data) async {
    overlays.add(data);
  }

  @override
  void hideControlOverlay({String? sessionId, bool endSession = false}) {
    if (sessionId != null) {
      hidden.add(sessionId);
    }
  }
}

class _Notifications extends UnavailableNotifications {
  final bodies = <String>[];
  int cleared = 0;
  @override
  Future<void> showSession({
    required String title,
    required String body,
    required String stop,
    required String channel,
  }) async {
    bodies.add(body);
  }

  @override
  Future<void> clearSession() async {
    cleared++;
  }
}

void main() {
  test(
    'headless phone control shows status and Stop, and clears its own session',
    () async {
      final screen = _Screen(),
          notifications = _Notifications(),
          strings = AppLocalizationsEn();
      final presenter = AutomationScreenStatus(
        screen: screen,
        notifications: notifications,
        strings: strings,
      );
      screen.beginModelSession();
      await presenter.flush();
      expect(screen.overlays.single.stop, strings.stop);
      expect(notifications.bodies, hasLength(1));
      screen.updateModelSession(phase: ScreenSessionPhase.thinking);
      await presenter.flush();
      expect(notifications.bodies.last, strings.screenSessionThinking);
      final id = screen.modelSession!.id;
      screen.endModelSession();
      await presenter.dispose();
      expect(screen.hidden, contains(id));
      expect(notifications.cleared, 1);
      screen.dispose();
      notifications.dispose();
    },
  );
  test(
    'disposing an unused presenter never clears another session notice',
    () async {
      final screen = _Screen(), notifications = _Notifications();
      final presenter = AutomationScreenStatus(
        screen: screen,
        notifications: notifications,
        strings: AppLocalizationsEn(),
      );
      await presenter.dispose();
      expect(notifications.cleared, 0);
      screen.dispose();
      notifications.dispose();
    },
  );
}
