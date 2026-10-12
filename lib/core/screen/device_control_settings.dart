import '../util/json.dart';

/// Device-control preferences. Availability itself is decided by the
/// user in system settings (accessibility, notification access, Termux).
class DeviceControlSettings {
  const DeviceControlSettings({
    this.screenshots = false,
    this.deleteScreenshotsWithChat = true,
    this.shellTimeoutSeconds = 60,
  });

  static const settingsKey = 'device_control.settings';

  /// Attach a screenshot to read_screen for vision models. Off by default:
  /// screenshots show everything on screen and cost many tokens.
  final bool screenshots;

  /// Deleting a chat, or messages after a rewind, also deletes the
  /// screenshots only those messages used. Incognito chats always do.
  final bool deleteScreenshotsWithChat;
  final int shellTimeoutSeconds;

  factory DeviceControlSettings.fromJson(JsonMap json) => DeviceControlSettings(
    screenshots: asBool(json['screenshots']) ?? false,
    deleteScreenshotsWithChat: asBool(json['deleteScreenshots']) ?? true,
    shellTimeoutSeconds: (asInt(json['shellTimeoutSeconds']) ?? 60).clamp(
      5,
      600,
    ),
  );

  JsonMap toJson() => {
    'screenshots': screenshots,
    'deleteScreenshots': deleteScreenshotsWithChat,
    'shellTimeoutSeconds': shellTimeoutSeconds,
  };

  DeviceControlSettings copyWith({
    bool? screenshots,
    bool? deleteScreenshotsWithChat,
    int? shellTimeoutSeconds,
  }) => DeviceControlSettings(
    screenshots: screenshots ?? this.screenshots,
    deleteScreenshotsWithChat:
        deleteScreenshotsWithChat ?? this.deleteScreenshotsWithChat,
    shellTimeoutSeconds: shellTimeoutSeconds ?? this.shellTimeoutSeconds,
  );
}
