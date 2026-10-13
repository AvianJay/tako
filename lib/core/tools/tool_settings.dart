import '../util/json.dart';

class ToolSettings {
  const ToolSettings({
    this.enabled = true,
    this.maxSteps = 20,
    this.maxScreenSteps = 50,
    this.maxOutputChars = 6000,
    this.disabled = const {},
  });
  final bool enabled;

  /// Start checking for repeated tool sequences after this many calls.
  /// Productive turns may continue beyond this threshold.
  final int maxSteps;

  /// The loop-check threshold for a turn that controls the screen: each step is an
  /// action and a look, so it needs more calls than other tasks.
  final int maxScreenSteps;
  final int maxOutputChars;
  final Set<String> disabled;
  factory ToolSettings.fromJson(JsonMap json) => ToolSettings(
    enabled: asBool(json['enabled']) ?? true,
    maxSteps: (asInt(json['maxSteps']) ?? 20).clamp(1, 100),
    maxScreenSteps: (asInt(json['maxScreenSteps']) ?? 50).clamp(1, 200),
    maxOutputChars: (asInt(json['maxOutputChars']) ?? 6000).clamp(256, 60000),
    disabled: {
      for (final name in asList(json['disabled']) ?? [])
        if (name is String) name,
    },
  );
  JsonMap toJson() => {
    'enabled': enabled,
    'maxSteps': maxSteps,
    'maxScreenSteps': maxScreenSteps,
    'maxOutputChars': maxOutputChars,
    'disabled': disabled.toList(),
  };
  ToolSettings copyWith({
    bool? enabled,
    int? maxSteps,
    int? maxScreenSteps,
    int? maxOutputChars,
    Set<String>? disabled,
  }) => ToolSettings(
    enabled: enabled ?? this.enabled,
    maxSteps: maxSteps ?? this.maxSteps,
    maxScreenSteps: maxScreenSteps ?? this.maxScreenSteps,
    maxOutputChars: maxOutputChars ?? this.maxOutputChars,
    disabled: disabled ?? this.disabled,
  );
}
