import '../util/json.dart';

/// Device-control preferences. Availability itself is decided by the
/// user in system settings (accessibility, notification access, Termux).
class DeviceControlSettings {
  const DeviceControlSettings({
    this.screenshots = false,
    this.deleteScreenshotsWithChat = true,
    this.shellTimeoutSeconds = 60,
    this.remoteAgent = true,
    this.remoteAgentProviderId,
    this.remoteAgentModelId,
    this.remoteAgentEffort,
  });

  static const settingsKey = 'device_control.settings';

  /// Attach a screenshot to read_screen for vision models. Off by default:
  /// screenshots show everything on screen and cost many tokens.
  final bool screenshots;

  /// Deleting a chat, or messages after a rewind, also deletes the
  /// screenshots only those messages used. Incognito chats always do.
  final bool deleteScreenshotsWithChat;
  final int shellTimeoutSeconds;

  /// Delegation uses the selected saved connection and its own credentials.
  final bool remoteAgent;
  final String? remoteAgentProviderId;
  final String? remoteAgentModelId;
  final String? remoteAgentEffort;

  factory DeviceControlSettings.fromJson(JsonMap json) => DeviceControlSettings(
    screenshots: asBool(json['screenshots']) ?? false,
    deleteScreenshotsWithChat: asBool(json['deleteScreenshots']) ?? true,
    shellTimeoutSeconds: (asInt(json['shellTimeoutSeconds']) ?? 60).clamp(
      5,
      600,
    ),
    remoteAgent: asBool(json['remoteAgent']) ?? true,
    remoteAgentProviderId: asString(json['remoteAgentProviderId']),
    remoteAgentModelId: asString(json['remoteAgentModelId']),
    remoteAgentEffort: asString(json['remoteAgentEffort']),
  );

  JsonMap toJson() => {
    'screenshots': screenshots,
    'deleteScreenshots': deleteScreenshotsWithChat,
    'shellTimeoutSeconds': shellTimeoutSeconds,
    'remoteAgent': remoteAgent,
    'remoteAgentProviderId': remoteAgentProviderId,
    'remoteAgentModelId': remoteAgentModelId,
    'remoteAgentEffort': remoteAgentEffort,
  };

  DeviceControlSettings copyWith({
    bool? screenshots,
    bool? deleteScreenshotsWithChat,
    int? shellTimeoutSeconds,
    bool? remoteAgent,
    String? remoteAgentProviderId,
    String? remoteAgentModelId,
    String? remoteAgentEffort,
  }) => DeviceControlSettings(
    screenshots: screenshots ?? this.screenshots,
    deleteScreenshotsWithChat:
        deleteScreenshotsWithChat ?? this.deleteScreenshotsWithChat,
    shellTimeoutSeconds: shellTimeoutSeconds ?? this.shellTimeoutSeconds,
    remoteAgent: remoteAgent ?? this.remoteAgent,
    remoteAgentProviderId: remoteAgentProviderId ?? this.remoteAgentProviderId,
    remoteAgentModelId: remoteAgentModelId ?? this.remoteAgentModelId,
    remoteAgentEffort: remoteAgentEffort ?? this.remoteAgentEffort,
  );
}
