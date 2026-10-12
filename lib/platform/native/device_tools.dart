import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/providers/cancel_token.dart';
import '../../core/tools/device_tools.dart' show matchApps, similarApps;
import '../device_tools_capability.dart';
import 'device_api.g.dart';

/// Device tools of the Android or iOS host app. iOS has no public way to
/// set alarms or timers or to open other apps by name.
const iosDeviceToolNames = {
  'get_device_status',
  'get_location',
  'clipboard_read',
  'clipboard_write',
  'calendar_list',
  'calendar_add',
  'open_url',
};

/// The native bridge is called only by Tool.run after PermissionGate.
class NativeDeviceTools implements DeviceToolsCapability {
  NativeDeviceTools({
    required this.platform,
    this.tools = deviceToolNames,
    DeviceApi? api,
  }) : _api = api ?? DeviceApi();

  /// `Android` or `iOS`, as get_device_status reports it.
  final String platform;
  final Set<String> tools;
  final DeviceApi _api;
  static int _sequence = 0;

  @override
  bool get isAvailable => true;
  @override
  bool supports(String tool) => tools.contains(tool);

  @override
  Future<Map<String, Object?>> invoke(
    String tool,
    Map<String, Object?> arguments, {
    required CancelToken cancel,
  }) async {
    cancel.throwIfCancelled();
    if (!supports(tool)) throw const DeviceToolException('unavailable');
    final id = '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    // Remove listeners after completion and never surface native error details.
    void abort() {
      unawaited(_api.cancelOperation(id).catchError((Object _) {}));
    }

    cancel.addListener(abort);
    try {
      final pending = _invoke(tool, arguments, id);
      // Preserve committed write/launch results when Stop races the reply, so
      // the executor can persist their side effects.
      return await (_actionTools.contains(tool)
          ? pending
          : cancel.bind(pending));
    } on PlatformException catch (error) {
      cancel.throwIfCancelled();
      throw DeviceToolException(
        _safeCodes.contains(error.code)
            ? error.code
            : 'device_operation_failed',
      );
    } on MissingPluginException {
      throw const DeviceToolException('unavailable');
    } on FormatException {
      throw const DeviceToolException('invalid_arguments');
    } on TypeError {
      throw const DeviceToolException('invalid_arguments');
    } finally {
      cancel.removeListener(abort);
    }
  }

  Future<Map<String, Object?>> _invoke(
    String tool,
    Map<String, Object?> args,
    String id,
  ) async {
    switch (tool) {
      case 'get_device_status':
        final snapshot = await _api.snapshot();
        return {
          'platform': platform,
          'os_version': snapshot.osVersion,
          'model': snapshot.model,
          if (snapshot.batteryPercent != null)
            'battery_percent': snapshot.batteryPercent,
          if (snapshot.network != null) 'network': snapshot.network,
        };
      case 'get_location':
        final location = await _api.getLocation(id);
        return {
          'latitude': location.latitude,
          'longitude': location.longitude,
          'accuracy_meters': location.accuracyMeters,
          'timestamp': _iso(location.timestampMillis),
        };
      case 'clipboard_read':
        return {'text': await _api.clipboardRead(), 'maximum_characters': 6000};
      case 'clipboard_write':
        await _api.clipboardWrite(args['text'] as String);
        return {'written': true};
      case 'calendar_list':
        final listing = await _api.calendarList(
          id,
          _millis(args['start']),
          _millis(args['end']),
          (args['limit'] as num?)?.toInt() ?? 20,
        );
        return {
          'calendars': [
            for (final calendar in listing.calendars)
              {
                'id': calendar.id,
                'name': calendar.name,
                'writable': calendar.writable,
              },
          ],
          'events': [
            for (final event in listing.events)
              {
                'id': event.id,
                'calendar_id': event.calendarId,
                'title': event.title,
                'start': _iso(event.startMillis),
                'end': _iso(event.endMillis),
                'all_day': event.allDay,
                if (event.location != null) 'location': event.location,
              },
          ],
          'truncated': listing.truncated,
        };
      case 'calendar_add':
        final eventId = await _api.calendarAdd(
          id,
          DeviceEventDraft(
            calendarId: (args['calendar_id'] as num).toInt(),
            title: args['title'] as String,
            startMillis: _millis(args['start']),
            endMillis: _millis(args['end']),
            notes: args['description'] as String?,
            location: args['location'] as String?,
          ),
        );
        return {'created': true, 'event_id': eventId};
      case 'set_alarm':
        return _launched(
          await _api.setAlarm(
            (args['hour'] as num).toInt(),
            (args['minute'] as num).toInt(),
            args['label'] as String?,
          ),
        );
      case 'set_timer':
        return _launched(
          await _api.setTimer(
            (args['seconds'] as num).toInt(),
            args['label'] as String?,
          ),
        );
      case 'open_url':
        return _launched(await _api.openUrl(args['url'] as String));
      case 'open_app':
        final package =
            args['package'] as String? ??
            await _packageNamed(args['name'] as String);
        return _launched(await _api.openApp(package));
      default:
        throw const DeviceToolException('unavailable');
    }
  }

  /// Resolves an app name after approval. Only similar names are returned
  /// when nothing matches, never the full list of installed apps.
  Future<String> _packageNamed(String name) async {
    final apps = [
      for (final app in await _api.listApps())
        (label: app.label, packageName: app.packageName),
    ];
    final found = matchApps(name, apps);
    if (found.length == 1) return found.single.packageName;
    if (found.isEmpty) {
      throw DeviceToolException(
        'app_not_found',
        details: {
          'similar': [
            for (final app in similarApps(name, apps).take(8)) app.label,
          ],
        },
      );
    }
    throw DeviceToolException(
      'ambiguous_app_name',
      details: {
        'candidates': [
          for (final app in found.take(8))
            {'name': app.label, 'package': app.packageName},
        ],
      },
    );
  }

  Map<String, Object?> _launched(DeviceLaunchResult result) => {
    'launched': result.launched,
    'completion_verified': false,
  };
  int _millis(Object? value) =>
      DateTime.parse(value as String).millisecondsSinceEpoch;
  String _iso(int millis) => DateTime.fromMillisecondsSinceEpoch(
    millis,
    isUtc: true,
  ).toIso8601String();
}

const _actionTools = {
  'clipboard_write',
  'calendar_add',
  'set_alarm',
  'set_timer',
  'open_url',
  'open_app',
};

const _safeCodes = {
  'unavailable',
  'invalid_arguments',
  'permission_denied',
  'cancelled',
  'timeout',
  'permission_request_busy',
  'location_unavailable',
  'location_timeout',
  'foreground_required',
  'calendar_unavailable',
  'calendar_not_writable',
  'app_not_found',
  'device_operation_failed',
};
