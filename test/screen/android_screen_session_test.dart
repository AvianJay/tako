import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/screen/screen_capability.dart';
import 'package:tako/platform/android/control_api.g.dart';
import 'package:tako/platform/android/device_control.dart';

class _SessionApi extends ScreenApi {
  bool enabled = true;
  final starts = <String>[];
  final ends = <(String, bool)>[];
  final overlays = <(String, bool)>[];

  @override
  Future<ScreenStatusData> status() async =>
      ScreenStatusData(supported: true, enabled: enabled, screenshots: true);

  @override
  Future<void> beginControlSession(String sessionId) async =>
      starts.add(sessionId);

  @override
  Future<void> endControlSession(String sessionId, bool returnToApp) async =>
      ends.add((sessionId, returnToApp));

  @override
  Future<void> hideControlOverlay(String sessionId, bool endSession) async =>
      overlays.add((sessionId, endSession));
}

void main() {
  test(
    'background completion releases the session without bringing Tako forward',
    () async {
      final api = _SessionApi();
      final screen = AndroidScreen(api: api);
      await screen.refresh();
      screen.beginModelSession();
      final id = screen.modelSession!.id;
      screen.endModelSession(returnToApp: false);
      expect(api.ends, [(id, false)]);
      screen.dispose();
    },
  );
  test('wakefulness spans thinking and temporary overlay hiding', () async {
    final api = _SessionApi();
    final screen = AndroidScreen(api: api);
    await screen.refresh();
    screen.beginModelSession();
    final id = screen.modelSession!.id;
    screen.updateModelSession(title: 'Read Settings');
    screen.updateModelSession(phase: ScreenSessionPhase.thinking);
    screen.hideControlOverlay(sessionId: id);
    expect(api.starts, [id]);
    expect(api.ends, isEmpty);
    expect(api.overlays, [(id, false)]);

    screen.endModelSession();
    screen.endModelSession();
    expect(api.ends, [(id, true)]);
    expect(api.overlays.last, (id, true));
    screen.dispose();
    expect(api.ends, hasLength(1));
  });

  test('Stop returns to the app; disposal only releases resources', () async {
    final api = _SessionApi();
    final screen = AndroidScreen(api: api);
    await screen.refresh();
    screen.beginModelSession();
    final first = screen.modelSession!.id;
    screen.takeOver();
    screen.beginModelSession();
    final second = screen.modelSession!.id;
    screen.dispose();
    expect(api.starts, [first, second]);
    expect(api.ends, [(first, true), (second, false)]);
  });

  test('unavailable screen control acquires no session resources', () async {
    final api = _SessionApi()..enabled = false;
    final screen = AndroidScreen(api: api);
    await screen.refresh();
    screen.beginModelSession();
    screen.endModelSession();
    screen.dispose();
    expect(api.starts, isEmpty);
    expect(api.ends, isEmpty);
  });
}
