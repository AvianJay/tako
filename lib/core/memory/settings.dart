import '../util/json.dart';

class MemorySettings {
  const MemorySettings({this.enabled = true});
  static const settingsKey = 'memory.settings';
  final bool enabled;

  factory MemorySettings.fromJson(JsonMap json) =>
      MemorySettings(enabled: asBool(json['enabled']) ?? true);

  JsonMap toJson() => {'enabled': enabled};
}

enum ReplyStyle { concise, normal, detailed }

class PersonalizationSettings {
  const PersonalizationSettings({
    this.displayName = '',
    this.userNotes = '',
    this.replyStyle = ReplyStyle.normal,
  });

  static const settingsKey = 'personalization.settings';
  static const maxNameLength = 100;
  static const maxNotesLength = 4000;

  final String displayName;
  final String userNotes;
  final ReplyStyle replyStyle;

  factory PersonalizationSettings.fromJson(JsonMap json) =>
      PersonalizationSettings(
        displayName: _bounded(asString(json['displayName']) ?? '', 100),
        userNotes: _bounded(asString(json['userNotes']) ?? '', 4000),
        replyStyle:
            ReplyStyle.values
                .where((style) => style.name == json['replyStyle'])
                .firstOrNull ??
            ReplyStyle.normal,
      );

  /// The `user_notes` prompt variable. A conversation stores the rendered
  /// value when it starts, so editing these settings affects only new chats.
  /// The normal style adds nothing, keeping the section absent by default.
  String get promptNotes => [
    if (displayName.trim().isNotEmpty)
      'Preferred name: ${displayName.replaceAll(RegExp(r'\s+'), ' ').trim()}',
    if (userNotes.trim().isNotEmpty) userNotes.trim(),
    ?switch (replyStyle) {
      ReplyStyle.concise =>
        'Reply style: concise. Keep replies brief and direct.',
      ReplyStyle.normal => null,
      ReplyStyle.detailed =>
        'Reply style: detailed. Explain thoroughly, with useful context and examples.',
    },
  ].join('\n');

  JsonMap toJson() => {
    'displayName': _bounded(displayName, maxNameLength),
    'userNotes': _bounded(userNotes, maxNotesLength),
    'replyStyle': replyStyle.name,
  };
}

String _bounded(String value, int length) =>
    String.fromCharCodes(value.runes.take(length));
