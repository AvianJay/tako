import 'package:flutter/foundation.dart';

import '../../platform/capabilities.dart';
import '../providers/cancel_token.dart';

class NotificationException implements Exception {
  const NotificationException(this.code);
  final String code;
  @override
  String toString() => code;
}

class DeviceNotification {
  const DeviceNotification({
    required this.packageName,
    required this.appLabel,
    this.title,
    this.text,
    this.lines = const [],
    required this.postedAt,
    this.ongoing = false,
    this.category,
  });
  final String packageName;
  final String appLabel;
  final String? title;
  final String? text;

  /// Latest messages of a conversation, or the lines of an inbox summary.
  final List<String> lines;
  final DateTime postedAt;
  final bool ongoing;
  final String? category;
}

/// Reading other apps' notifications (notifications_list) and posting the
/// app's own: the ongoing screen-control notice and reminders.
abstract class NotificationCapability extends ChangeNotifier
    implements Capability {
  /// The user granted notification access.
  bool get access;

  /// The app may post notifications.
  bool get canPost;

  @override
  bool get isAvailable => access;

  Future<void> refresh();
  Future<void> openAccessSettings();
  Future<bool> requestPostPermission();
  Future<List<DeviceNotification>> list({
    required int limit,
    required CancelToken cancel,
  });

  /// The ongoing "controlling the screen" notification with a Stop action.
  Future<void> showSession({
    required String title,
    required String body,
    required String stop,
    required String channel,
  });
  Future<void> clearSession();

  /// [kind] is `approval` or `reply`. Tapping the notification opens the app.
  Future<void> showAlert(
    String kind, {
    required String title,
    required String body,
    required String channel,
  });
  Future<void> cancelAlert(String kind);
}

class UnavailableNotifications extends NotificationCapability {
  @override
  bool get access => false;
  @override
  bool get canPost => false;
  @override
  Future<void> refresh() async {}
  @override
  Future<void> openAccessSettings() async {}
  @override
  Future<bool> requestPostPermission() async => false;
  @override
  Future<List<DeviceNotification>> list({
    required int limit,
    required CancelToken cancel,
  }) async => throw const NotificationException('unavailable');
  @override
  Future<void> showSession({
    required String title,
    required String body,
    required String stop,
    required String channel,
  }) async {}
  @override
  Future<void> clearSession() async {}
  @override
  Future<void> showAlert(
    String kind, {
    required String title,
    required String body,
    required String channel,
  }) async {}
  @override
  Future<void> cancelAlert(String kind) async {}
}
