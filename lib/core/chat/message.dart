import '../util/json.dart';
import 'content_block.dart';

enum MessageRole { user, assistant, tool }

enum MessageStatus { streaming, done, error, stopped }

final class TokenUsage {
  const TokenUsage({this.inputTokens, this.outputTokens, this.totalTokens});

  factory TokenUsage.fromJson(JsonMap json) => TokenUsage(
    inputTokens: asInt(json['inputTokens']),
    outputTokens: asInt(json['outputTokens']),
    totalTokens: asInt(json['totalTokens']),
  );

  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;

  JsonMap toJson() => {
    if (inputTokens != null) 'inputTokens': inputTokens,
    if (outputTokens != null) 'outputTokens': outputTokens,
    if (totalTokens != null) 'totalTokens': totalTokens,
  };
}

/// An immutable message node. Envelopes and timestamps belong to the node and
/// must never be regenerated while assembling later requests.
final class ChatMessage {
  ChatMessage({
    required this.id,
    required this.conversationId,
    this.parentId,
    required this.role,
    required List<ContentBlock> content,
    required DateTime createdAt,
    this.timezoneOffsetMinutes = 0,
    this.providerId,
    this.model,
    this.status = MessageStatus.done,
    this.contextEnvelope,
    this.usage,
    this.error,
  }) : content = List.unmodifiable(content),
       createdAt = createdAt.toUtc();

  factory ChatMessage.fromJson(JsonMap json) => ChatMessage(
    id: asString(json['id'])!,
    conversationId: asString(json['conversationId'])!,
    parentId: asString(json['parentId']),
    role: MessageRole.values.byName(asString(json['role'])!),
    content: ContentBlock.listFromJson(asList(json['content']) ?? []),
    createdAt: DateTime.parse(asString(json['createdAt'])!),
    timezoneOffsetMinutes: asInt(json['timezoneOffsetMinutes']) ?? 0,
    providerId: asString(json['providerId']),
    model: asString(json['model']),
    status: MessageStatus.values.byName(asString(json['status']) ?? 'done'),
    contextEnvelope: asString(json['contextEnvelope']),
    usage: asMap(json['usage']) == null
        ? null
        : TokenUsage.fromJson(asMap(json['usage'])!),
    error: asString(json['error']),
  );

  final String id;
  final String conversationId;
  final String? parentId;
  final MessageRole role;
  final List<ContentBlock> content;
  final DateTime createdAt;
  final int timezoneOffsetMinutes;
  final String? providerId;
  final String? model;
  final MessageStatus status;
  final String? contextEnvelope;
  final TokenUsage? usage;
  final String? error;

  String get text => content.whereType<TextBlock>().map((b) => b.text).join();

  String get requestText => role == MessageRole.user && contextEnvelope != null
      ? '$contextEnvelope\n$text'
      : text;

  DateTime get wallTime =>
      createdAt.add(Duration(minutes: timezoneOffsetMinutes));

  ChatMessage copyWith({
    List<ContentBlock>? content,
    MessageStatus? status,
    TokenUsage? usage,
    String? error,
    bool clearError = false,
  }) => ChatMessage(
    id: id,
    conversationId: conversationId,
    parentId: parentId,
    role: role,
    content: content ?? this.content,
    createdAt: createdAt,
    timezoneOffsetMinutes: timezoneOffsetMinutes,
    providerId: providerId,
    model: model,
    status: status ?? this.status,
    contextEnvelope: contextEnvelope,
    usage: usage ?? this.usage,
    error: clearError ? null : (error ?? this.error),
  );

  JsonMap toJson() => {
    'id': id,
    'conversationId': conversationId,
    'parentId': parentId,
    'role': role.name,
    'content': [for (final block in content) block.toJson()],
    'createdAt': createdAt.toIso8601String(),
    'timezoneOffsetMinutes': timezoneOffsetMinutes,
    'providerId': providerId,
    'model': model,
    'status': status.name,
    'contextEnvelope': contextEnvelope,
    if (usage != null) 'usage': usage!.toJson(),
    if (error != null) 'error': error,
  };
}
