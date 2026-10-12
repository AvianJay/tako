import '../util/json.dart';

final class Conversation {
  Conversation({
    required this.id,
    this.title = 'New chat',
    required DateTime createdAt,
    required DateTime updatedAt,
    required this.systemPrompt,
    this.activeLeafId,
    this.providerId,
    this.model,
    this.promptConfigKey,
    this.incognito = false,
    this.memoryProfile,
    this.userNotes,
  }) : createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc();

  factory Conversation.fromJson(JsonMap json) => Conversation(
    id: asString(json['id'])!,
    title: asString(json['title']) ?? '',
    createdAt: DateTime.parse(asString(json['createdAt'])!),
    updatedAt: DateTime.parse(asString(json['updatedAt'])!),
    systemPrompt: asString(json['systemPrompt']) ?? '',
    activeLeafId: asString(json['activeLeafId']),
    providerId: asString(json['providerId']),
    model: asString(json['model']),
    promptConfigKey: asString(json['promptConfigKey']),
    incognito: asBool(json['incognito']) ?? false,
    memoryProfile: asString(json['memoryProfile']),
    userNotes: asString(json['userNotes']),
  );

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String systemPrompt;
  final String? activeLeafId;
  final String? providerId;
  final String? model;

  /// Non-secret provider inputs used for this frozen prompt, including when
  /// provider settings were edited while another conversation was active.
  final String? promptConfigKey;

  /// Memory is off and the chat is deleted once the user leaves it.
  final bool incognito;

  /// Pinned profile and personalization notes as of this conversation's
  /// start. Re-rendering the prompt reuses them, so edits apply to new chats.
  /// Null for chats created before these snapshots existed.
  final String? memoryProfile;
  final String? userNotes;

  Conversation copyWith({
    String? title,
    DateTime? updatedAt,
    String? systemPrompt,
    String? activeLeafId,
    bool clearActiveLeaf = false,
    String? providerId,
    String? model,
    String? promptConfigKey,
    String? memoryProfile,
    String? userNotes,
  }) => Conversation(
    id: id,
    title: title ?? this.title,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    activeLeafId: clearActiveLeaf ? null : (activeLeafId ?? this.activeLeafId),
    providerId: providerId ?? this.providerId,
    model: model ?? this.model,
    promptConfigKey: promptConfigKey ?? this.promptConfigKey,
    incognito: incognito,
    memoryProfile: memoryProfile ?? this.memoryProfile,
    userNotes: userNotes ?? this.userNotes,
  );

  JsonMap toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'systemPrompt': systemPrompt,
    'activeLeafId': activeLeafId,
    'providerId': providerId,
    'model': model,
    'promptConfigKey': promptConfigKey,
    if (incognito) 'incognito': true,
    if (memoryProfile != null) 'memoryProfile': memoryProfile,
    if (userNotes != null) 'userNotes': userNotes,
  };
}
