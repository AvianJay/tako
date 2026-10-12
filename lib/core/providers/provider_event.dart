sealed class ProviderEvent {
  const ProviderEvent();
}

/// A structured provider-side search receipt. Text claims, citations and a
/// pending server tool call are not evidence that a search was performed.
final class HostedSearchEvent extends ProviderEvent {
  const HostedSearchEvent({required this.success, this.errorCode});
  final bool success;
  final String? errorCode;
}

final class ProviderStateMetadata extends ProviderEvent {
  const ProviderStateMetadata({required this.sourceApi, required this.content});
  final String sourceApi;
  final List<Map<String, Object?>> content;
}

final class TextDelta extends ProviderEvent {
  const TextDelta(this.text);
  final String text;
}

final class ReasoningDelta extends ProviderEvent {
  const ReasoningDelta(this.text, {this.blockIndex = 0});
  final String text;
  final int blockIndex;
}

/// Opaque reasoning is never displayed. Store it with its reasoning block and
/// return it unchanged only to the API that produced it.
final class ReasoningMetadata extends ProviderEvent {
  const ReasoningMetadata({
    required this.blockIndex,
    required this.sourceApi,
    this.signature,
    this.redactedData,
    this.encryptedContent,
    this.itemId,
  });
  final int blockIndex;
  final String sourceApi;
  final String? signature;
  final String? redactedData;
  final String? encryptedContent;
  final String? itemId;
}

final class ToolCallStart extends ProviderEvent {
  const ToolCallStart(this.id, this.name);
  final String id;
  final String name;
}

final class ToolCallArgsDelta extends ProviderEvent {
  const ToolCallArgsDelta(this.id, this.jsonFragment);
  final String id;
  final String jsonFragment;
}

final class ToolCallEnd extends ProviderEvent {
  const ToolCallEnd(this.id);
  final String id;
}

final class Usage extends ProviderEvent {
  const Usage({this.inputTokens, this.outputTokens, this.totalTokens});
  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;
}

final class Done extends ProviderEvent {
  const Done(this.stopReason);
  final String? stopReason;
}

final class ProviderError extends ProviderEvent implements Exception {
  const ProviderError(this.message, {this.statusCode, this.code});
  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() =>
      statusCode == null ? message : 'HTTP $statusCode: $message';
}
