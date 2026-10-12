import '../util/json.dart';

/// One piece of a message's content. Stored as JSON in the database.
sealed class ContentBlock {
  const ContentBlock();

  JsonMap toJson();

  static ContentBlock? fromJson(JsonMap json) {
    return switch (json['type']) {
      'text' => TextBlock(asString(json['text']) ?? ''),
      'image' => ImageBlock(
        path: asString(json['path']) ?? '',
        mimeType: asString(json['mimeType']) ?? 'image/png',
        alt: asString(json['alt']),
      ),
      'file' => FileBlock(
        path: asString(json['path']) ?? '',
        name: asString(json['name']) ?? '',
        mimeType: asString(json['mimeType']) ?? 'application/octet-stream',
        sizeBytes: asInt(json['size']),
        extractedText: asString(json['extractedText']),
      ),
      'reasoning' => ReasoningBlock(
        text: asString(json['text']) ?? '',
        durationMs: asInt(json['durationMs']),
        signature: asString(json['signature']),
        redactedData: asString(json['redacted']),
        encryptedContent: asString(json['encrypted']),
        itemId: asString(json['itemId']),
        sourceApi: asString(json['api']),
        promptHash: asString(json['promptHash']),
      ),
      'providerState' => ProviderStateBlock(
        sourceApi: asString(json['api']) ?? '',
        promptHash: asString(json['promptHash']) ?? '',
        content: [
          for (final value in asList(json['content']) ?? <Object?>[])
            ?asMap(value),
        ],
      ),
      'toolCall' => ToolCallBlock(
        id: asString(json['id']) ?? '',
        name: asString(json['name']) ?? '',
        arguments: asString(json['arguments']) ?? '',
      ),
      'toolResult' => ToolResultBlock(
        toolCallId: asString(json['toolCallId']) ?? '',
        toolName: asString(json['toolName']) ?? '',
        content: asString(json['content']) ?? '',
        isError: asBool(json['isError']) ?? false,
        attachments: ContentBlock.listFromJson(
          asList(json['attachments']) ?? [],
        ),
        sideEffects: [
          for (final e in asList(json['sideEffects']) ?? const <Object?>[])
            if (asMap(e) case final m?) SideEffect.fromJson(m),
        ],
      ),
      _ => null,
    };
  }

  static List<ContentBlock> listFromJson(List<Object?> list) => [
    for (final item in list)
      if (asMap(item) case final m?) ?ContentBlock.fromJson(m),
  ];
}

final class TextBlock extends ContentBlock {
  const TextBlock(this.text);

  final String text;

  @override
  JsonMap toJson() => {'type': 'text', 'text': text};
}

/// Opaque assistant response content for provider-managed search continuation.
/// Hidden in the UI and never replayed to a different provider/model/prompt.
final class ProviderStateBlock extends ContentBlock {
  const ProviderStateBlock({
    required this.sourceApi,
    required this.promptHash,
    required this.content,
  });
  final String sourceApi;
  final String promptHash;
  final List<JsonMap> content;
  @override
  JsonMap toJson() => {
    'type': 'providerState',
    'api': sourceApi,
    'promptHash': promptHash,
    'content': content,
  };
}

/// An image stored in the workspace. [data] (base64) is only filled in for
/// outgoing requests and is never persisted.
final class ImageBlock extends ContentBlock {
  const ImageBlock({
    required this.path,
    required this.mimeType,
    this.alt,
    this.data,
  });

  final String path;
  final String mimeType;
  final String? alt;
  final String? data;

  ImageBlock withData(String base64) =>
      ImageBlock(path: path, mimeType: mimeType, alt: alt, data: base64);

  @override
  JsonMap toJson() => {
    'type': 'image',
    'path': path,
    'mimeType': mimeType,
    if (alt != null) 'alt': alt,
  };
}

/// A file attached by the user, stored in the workspace.
final class FileBlock extends ContentBlock {
  const FileBlock({
    required this.path,
    required this.name,
    required this.mimeType,
    this.sizeBytes,
    this.extractedText,
  });

  final String path;
  final String name;
  final String mimeType;
  final int? sizeBytes;

  /// Frozen text/PDF extraction at attachment import; never re-render history.
  final String? extractedText;

  @override
  JsonMap toJson() => {
    'type': 'file',
    'path': path,
    'name': name,
    'mimeType': mimeType,
    if (sizeBytes != null) 'size': sizeBytes,
    if (extractedText != null) 'extractedText': extractedText,
  };
}

/// Model reasoning ("thinking"). The opaque fields must be sent back
/// unchanged to the same API ([sourceApi]) for some providers.
final class ReasoningBlock extends ContentBlock {
  const ReasoningBlock({
    required this.text,
    this.durationMs,
    this.signature,
    this.redactedData,
    this.encryptedContent,
    this.itemId,
    this.sourceApi,
    this.promptHash,
  });

  final String text;
  final int? durationMs;

  /// Anthropic `thinking.signature`.
  final String? signature;

  /// Anthropic `redacted_thinking.data`.
  final String? redactedData;

  /// OpenAI Responses `reasoning.encrypted_content`.
  final String? encryptedContent;

  /// OpenAI Responses reasoning item id.
  final String? itemId;

  /// [ApiType.name] of the API that produced the block.
  final String? sourceApi;

  /// Hash of the system prompt in effect when the block was produced.
  final String? promptHash;

  bool get hasOpaqueData =>
      signature != null || redactedData != null || encryptedContent != null;

  @override
  JsonMap toJson() => {
    'type': 'reasoning',
    'text': text,
    if (durationMs != null) 'durationMs': durationMs,
    if (signature != null) 'signature': signature,
    if (redactedData != null) 'redacted': redactedData,
    if (encryptedContent != null) 'encrypted': encryptedContent,
    if (itemId != null) 'itemId': itemId,
    if (sourceApi != null) 'api': sourceApi,
    if (promptHash != null) 'promptHash': promptHash,
  };
}

final class ToolCallBlock extends ContentBlock {
  const ToolCallBlock({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;

  /// Raw JSON arguments as produced by the model.
  final String arguments;

  @override
  JsonMap toJson() => {
    'type': 'toolCall',
    'id': id,
    'name': name,
    'arguments': arguments,
  };
}

final class ToolResultBlock extends ContentBlock {
  const ToolResultBlock({
    required this.toolCallId,
    required this.toolName,
    required this.content,
    this.isError = false,
    this.sideEffects = const [],
    this.attachments = const [],
  });

  final String toolCallId;
  final String toolName;
  final String content;
  final bool isError;
  final List<SideEffect> sideEffects;
  final List<ContentBlock> attachments;

  ToolResultBlock withContent(String newContent) => ToolResultBlock(
    toolCallId: toolCallId,
    toolName: toolName,
    content: newContent,
    isError: isError,
    sideEffects: sideEffects,
    attachments: attachments,
  );

  @override
  JsonMap toJson() => {
    'type': 'toolResult',
    'toolCallId': toolCallId,
    'toolName': toolName,
    'content': content,
    if (isError) 'isError': true,
    if (sideEffects.isNotEmpty)
      'sideEffects': [for (final e in sideEffects) e.toJson()],
    if (attachments.isNotEmpty)
      'attachments': [for (final block in attachments) block.toJson()],
  };
}

/// Something a tool did that cannot be undone by rewinding the chat.
class SideEffect {
  const SideEffect({
    required this.kind,
    required this.summary,
    this.backupPath,
    this.memoryUndo,
  });

  factory SideEffect.fromJson(JsonMap json) => SideEffect(
    kind: asString(json['kind']) ?? '',
    summary: asString(json['summary']) ?? '',
    backupPath: asString(json['backupPath']),
    memoryUndo: asMap(json['memoryUndo']),
  );

  /// e.g. `file_written`, `message_sent`, `setting_changed`.
  final String kind;
  final String summary;
  final String? backupPath;

  /// A revision-checked undo receipt for a newly saved memory. Kept separate
  /// from workspace backup paths so file restore can never interpret it.
  final JsonMap? memoryUndo;

  JsonMap toJson() => {
    'kind': kind,
    'summary': summary,
    if (backupPath != null) 'backupPath': backupPath,
    if (memoryUndo != null) 'memoryUndo': memoryUndo,
  };
}
