import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/providers/cancel_token.dart';
import 'package:tako/core/tools/device_tools.dart';
import 'package:tako/core/tools/tool.dart';
import 'package:tako/core/tools/tool_registry.dart';
import 'package:tako/platform/device_tools_capability.dart';
import 'package:tako/platform/native/device_api.g.dart';
import 'package:tako/platform/native/device_tools.dart';

class FakeDevice implements DeviceToolsCapability {
  final calls = <String>[];
  Set<String> supported = deviceToolNames;
  @override
  bool isAvailable = true;
  @override
  bool supports(String tool) => supported.contains(tool);
  @override
  Future<Map<String, Object?>> invoke(
    String tool,
    Map<String, Object?> args, {
    required CancelToken cancel,
  }) async {
    calls.add(tool);
    return {'ok': true};
  }
}

class FakeApi extends DeviceApi {
  final location = Completer<DeviceLocation>();
  final cancelled = <String>[];
  String? operation;
  PlatformException? failure;
  Completer<void>? write;
  @override
  Future<DeviceLocation> getLocation(String operationId) {
    operation = operationId;
    return location.future;
  }

  @override
  Future<void> cancelOperation(String operationId) async {
    cancelled.add(operationId);
  }

  @override
  Future<String?> clipboardRead() async {
    if (failure != null) throw failure!;
    return 'sample';
  }

  @override
  Future<void> clipboardWrite(String text) => write?.future ?? Future.value();

  @override
  Future<DeviceLaunchResult> setTimer(int seconds, String? label) async =>
      DeviceLaunchResult(launched: true);
}

ToolContext context([CancelToken? cancel]) => ToolContext(
  conversationId: 'chat',
  messageId: 'message',
  cancel: cancel ?? CancelToken(),
);

void main() {
  test(
    'Stop racing a committed write preserves its eventual side effect',
    () async {
      final api = FakeApi()..write = Completer<void>();
      final cancel = CancelToken();
      final registry = ToolRegistry(
        createDeviceTools(NativeDeviceTools(platform: 'Android', api: api)),
      );
      final pending = registry.get('clipboard_write')!.run({
        'text': 'sample',
      }, context(cancel));
      cancel.cancel();
      api.write!.complete();
      final result = await pending;
      expect(result.isError, isFalse);
      expect(jsonDecode(result.content), {'written': true});
      expect(result.sideEffects.single.kind, 'clipboard_written');
      expect(api.cancelled, hasLength(1));
    },
  );

  test(
    'constructing tools and discovering availability never reads private data',
    () {
      final device = FakeDevice()..supported = {'get_device_status'};
      final registry = ToolRegistry(createDeviceTools(device));
      expect(registry.availableTools.map((tool) => tool.name), [
        'get_device_status',
      ]);
      expect(device.calls, isEmpty);
      expect(
        ToolRegistry(
          createDeviceTools(const UnavailableDeviceTools()),
        ).availableTools,
        isEmpty,
      );
    },
  );

  test(
    'device risks preserve sensitive reads and external calendar/URL approval',
    () {
      final tools = createDeviceTools(FakeDevice());
      final risks = {
        for (final tool in tools) tool.name: tool.riskFor({}, context()),
      };
      expect(risks, {
        'get_device_status': RiskLevel.safe,
        'get_location': RiskLevel.sensitive,
        'clipboard_read': RiskLevel.sensitive,
        'clipboard_write': RiskLevel.action,
        'calendar_list': RiskLevel.sensitive,
        'calendar_add': RiskLevel.high,
        'set_alarm': RiskLevel.action,
        'set_timer': RiskLevel.action,
        'open_url': RiskLevel.high,
        'open_app': RiskLevel.action,
      });
      expect(risks.containsKey('notifications_list'), isFalse);
    },
  );

  test(
    'invalid destructive or implicit app payloads never reach native bridge',
    () async {
      final device = FakeDevice();
      final registry = ToolRegistry(createDeviceTools(device));
      for (final args in [
        {'package': 'intent://action', 'title': 'Open app'},
        {'package': 'com.example.app;rm -rf', 'title': 'Open app'},
        {
          'package': 'com.example.app',
          'command': 'hidden',
          'title': 'Open app',
        },
        {'package': 'com.example.app'},
        {'package': 'com.example.app', 'title': ' '},
      ]) {
        expect(
          (await registry.get('open_app')!.run(args, context())).isError,
          isTrue,
        );
      }
      expect(device.calls, isEmpty);
      expect(
        validDeviceArguments('open_app', {
          'package': 'tw.avianjay.tako',
          'title': 'Open Tako',
        }),
        isTrue,
      );
    },
  );

  test(
    'only absolute HTTP URLs without credentials or control characters pass',
    () {
      for (final url in [
        'javascript:alert(1)',
        'file:///private',
        'https://name:password@example.com/',
        '//example.com',
        'https://example.com/\nother',
        'https:///',
      ]) {
        expect(
          validDeviceArguments('open_url', {'url': url}),
          isFalse,
          reason: url,
        );
      }
      expect(
        validDeviceArguments('open_url', {
          'url': 'https://example.com/path?q=ok',
        }),
        isTrue,
      );
    },
  );

  test(
    'calendar ranges require explicit timezones and reject normalized invalid dates',
    () {
      const base = {
        'start': '2026-10-11T10:00:00+08:00',
        'end': '2026-10-11T11:00:00+08:00',
      };
      expect(validDeviceArguments('calendar_list', base), isTrue);
      for (final args in [
        {...base, 'start': '2026-10-11T10:00:00'},
        {...base, 'start': '2026-02-30T10:00:00Z'},
        {...base, 'start': '2026-10-11T29:00:00Z'},
        {...base, 'end': base['start']},
        {...base, 'end': '2028-10-11T11:00:00Z'},
        {...base, 'limit': 101},
        {...base, 'limit': 3.5},
      ]) {
        expect(validDeviceArguments('calendar_list', args), isFalse);
      }
      expect(
        validDeviceArguments('calendar_add', {
          ...base,
          'calendar_id': 1,
          'title': ' ',
        }),
        isFalse,
      );
    },
  );

  test('alarm and timer bounds prevent overflow and silent coercion', () {
    expect(
      validDeviceArguments('set_alarm', {'hour': 23, 'minute': 59}),
      isTrue,
    );
    expect(
      validDeviceArguments('set_alarm', {'hour': 24, 'minute': 0}),
      isFalse,
    );
    expect(validDeviceArguments('set_timer', {'seconds': 0}), isFalse);
    expect(validDeviceArguments('set_timer', {'seconds': 1.1}), isFalse);
    expect(validDeviceArguments('set_timer', {'seconds': double.nan}), isFalse);
    expect(validDeviceArguments('set_timer', {'seconds': 86401}), isFalse);
  });

  test('stopping before execution never touches the device', () async {
    final device = FakeDevice();
    final cancel = CancelToken()..cancel();
    final tool = ToolRegistry(createDeviceTools(device)).get('clipboard_read')!;
    await expectLater(
      tool.run({}, context(cancel)),
      throwsA(isA<RequestCancelled>()),
    );
    expect(device.calls, isEmpty);
  });

  test(
    'stopping pending location calls native cancellation and ignores late result',
    () async {
      final api = FakeApi();
      final device = NativeDeviceTools(platform: 'Android', api: api);
      final cancel = CancelToken();
      final pending = device.invoke('get_location', {}, cancel: cancel);
      final check = expectLater(pending, throwsA(isA<RequestCancelled>()));
      cancel.cancel();
      await check;
      expect(api.cancelled, [api.operation]);
      api.location.complete(
        DeviceLocation(
          latitude: 25,
          longitude: 121,
          accuracyMeters: 100,
          timestampMillis: 1,
        ),
      );
      await Future<void>.delayed(Duration.zero);
    },
  );

  test('finished calls remove native cancellation listeners', () async {
    final api = FakeApi();
    final cancel = CancelToken();
    await NativeDeviceTools(
      platform: 'Android',
      api: api,
    ).invoke('clipboard_read', {}, cancel: cancel);
    cancel.cancel();
    expect(api.cancelled, isEmpty);
  });

  test('native errors cannot leak private details into tool results', () async {
    final api = FakeApi()
      ..failure = PlatformException(
        code: 'secret_code',
        message: 'private clipboard',
        details: 'private account',
      );
    final registry = ToolRegistry(
      createDeviceTools(NativeDeviceTools(platform: 'Android', api: api)),
    );
    final result = await registry.get('clipboard_read')!.run({}, context());
    expect(jsonDecode(result.content), {'error': 'device_operation_failed'});
    expect(result.isError, isTrue);
  });

  test(
    'external clock actions report launch without claiming completion',
    () async {
      final registry = ToolRegistry(
        createDeviceTools(
          NativeDeviceTools(platform: 'Android', api: FakeApi()),
        ),
      );
      final result = await registry.get('set_timer')!.run({
        'seconds': 60,
      }, context());
      expect(jsonDecode(result.content), {
        'launched': true,
        'completion_verified': false,
      });
      expect(result.sideEffects.single.kind, 'timer_requested');
    },
  );
}
