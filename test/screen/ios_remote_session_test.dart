import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/platform/ios/ios_remote_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tw.avianjay.tako/remote_session');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'scheduler diagnostics survive expiration and end without secrets',
    () async {
      var stops = 0;
      final events = <Map<String, Object?>>[];
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'diagnostics') {
          return {
            'build': '17',
            'processing_state': 'submission_failed',
            'error_domain': 'BGTaskSchedulerErrorDomain',
            'error_code': 1,
          };
        }
        return null;
      });
      final session = IosRemoteSession(
        onStop: () => stops++,
        onDiagnostics: events.add,
      );
      await session.setActive(true);
      expect(events.single['error_code'], 1);
      Future<void> native(String method, [Object? args]) async {
        await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, args),
          ),
          (ByteData? reply) {},
        );
      }

      await native('diagnosticsChanged', {
        'processing_state': 'running',
        'registered': true,
        'submitted': true,
        'handler_started': true,
      });
      expect(events.last['handler_started'], true);
      await native('backgroundExpired');
      expect(stops, 1);
      expect(events.last['stop_reason'], 'system_expiration');
      await native('stop');
      expect(stops, 2);
      expect(events.last['stop_reason'], 'user_stop');
      await session.setActive(false);
      expect(calls, ['start', 'diagnostics', 'end', 'diagnostics']);
      expect(events.last['processing_state'], 'submission_failed');
    },
  );

  test('hosts without native diagnostics still start and stop', () async {
    final session = IosRemoteSession(onStop: () {});
    await session.setActive(true);
    await session.progress('tap', 1);
    await session.setActive(false);
  });

  test(
    'return to app finishes before releasing native background time',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      final session = IosRemoteSession(
        onStop: () {},
        onReturnToApp: () async => calls.add('return'),
      );
      await session.setActive(true);
      await session.setActive(false);
      expect(calls, ['start', 'diagnostics', 'return', 'end', 'diagnostics']);
    },
  );

  test('a failed return still releases native resources', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    final session = IosRemoteSession(
      onStop: () {},
      onReturnToApp: () async => throw StateError('offline'),
    );
    await session.setActive(true);
    await session.setActive(false);
    expect(calls, ['start', 'diagnostics', 'end', 'diagnostics']);
  });
}
