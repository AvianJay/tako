import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'tako',
    dartOut: 'lib/platform/native/device_api.g.dart',
    kotlinOut: 'android/app/src/main/kotlin/tw/avianjay/tako/DeviceApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'tw.avianjay.tako'),
    swiftOut: 'ios/Runner/DeviceApi.g.swift',
  ),
)
class DeviceSnapshot {
  DeviceSnapshot({
    required this.osVersion,
    required this.model,
    this.batteryPercent,
    this.network,
  });
  String osVersion;
  String model;
  int? batteryPercent;
  String? network;
}

class DeviceLocation {
  DeviceLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestampMillis,
  });
  double latitude;
  double longitude;
  double accuracyMeters;
  int timestampMillis;
}

class DeviceCalendar {
  DeviceCalendar({
    required this.id,
    required this.name,
    required this.writable,
  });
  int id;
  String name;
  bool writable;
}

class DeviceCalendarEvent {
  DeviceCalendarEvent({
    required this.id,
    required this.calendarId,
    required this.title,
    required this.startMillis,
    required this.endMillis,
    required this.allDay,
    this.location,
  });
  int id;
  int calendarId;
  String title;
  int startMillis;
  int endMillis;
  bool allDay;
  String? location;
}

class DeviceCalendarListing {
  DeviceCalendarListing({
    required this.calendars,
    required this.events,
    required this.truncated,
  });
  List<DeviceCalendar> calendars;
  List<DeviceCalendarEvent> events;
  bool truncated;
}

class DeviceEventDraft {
  DeviceEventDraft({
    required this.calendarId,
    required this.title,
    required this.startMillis,
    required this.endMillis,
    this.notes,
    this.location,
  });
  int calendarId;
  String title;
  int startMillis;
  int endMillis;
  String? notes;
  String? location;
}

class DeviceLaunchResult {
  DeviceLaunchResult({required this.launched});
  bool launched;
}

class DeviceAppEntry {
  DeviceAppEntry({required this.label, required this.packageName});
  String label;
  String packageName;
}

@HostApi()
abstract class DeviceApi {
  DeviceSnapshot snapshot();
  @async
  DeviceLocation getLocation(String operationId);
  String? clipboardRead();
  void clipboardWrite(String text);
  @async
  DeviceCalendarListing calendarList(
    String operationId,
    int startMillis,
    int endMillis,
    int limit,
  );
  @async
  int calendarAdd(String operationId, DeviceEventDraft draft);
  DeviceLaunchResult setAlarm(int hour, int minute, String? label);
  DeviceLaunchResult setTimer(int seconds, String? label);
  DeviceLaunchResult openUrl(String url);
  DeviceLaunchResult openApp(String packageName);

  /// Launchable apps (label and package); read only by open_app after approval.
  List<DeviceAppEntry> listApps();
  void cancelOperation(String operationId);
}
