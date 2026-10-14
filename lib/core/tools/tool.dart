import '../../platform/capabilities.dart';
import '../chat/content_block.dart';
import '../permissions/risk_level.dart';
import '../providers/cancel_token.dart';

export '../permissions/risk_level.dart';

class ToolContext {
  const ToolContext({
    required this.conversationId,
    required this.messageId,
    required this.cancel,
    this.lastCall = true,
    this.targetLabel,
    this.targetIsPassword = false,
    this.target,
    this.targetDetails = const {},
    this.expectedTargetCheck,
  });

  final String conversationId;
  final String messageId;
  final CancelToken cancel;

  /// No other call of the same response runs after this one.
  final bool lastCall;

  /// Trusted observation metadata, never solely the model's claimed label/type.
  /// Screen/browser tools resolve it in [TargetResolvingTool.resolveTarget]
  /// before risk classification and permission.
  final String? targetLabel;
  final bool targetIsPassword;

  /// Opaque resolved target, consumed only by the tool that produced it.
  final Object? target;

  /// Plain-language facts about the target shown in the approval sheet.
  final Map<String, String> targetDetails;

  /// An opaque fingerprint retained by a controlled REPL element reference.
  final String? expectedTargetCheck;

  ToolContext withTarget({
    required Object target,
    String? label,
    bool isPassword = false,
    Map<String, String> details = const {},
  }) => ToolContext(
    conversationId: conversationId,
    messageId: messageId,
    cancel: cancel,
    lastCall: lastCall,
    targetLabel: label,
    targetIsPassword: isPassword,
    target: target,
    targetDetails: Map.unmodifiable(details),
    expectedTargetCheck: expectedTargetCheck,
  );
}

class ToolResult {
  const ToolResult({
    required this.content,
    this.isError = false,
    this.sideEffects = const [],
    this.attachments = const [],
    this.data,
  });

  final String content;
  final bool isError;
  final List<SideEffect> sideEffects;
  final List<ContentBlock> attachments;

  /// Host-only structured data. Not persisted or replayed as a second tool result.
  final Map<String, Object?>? data;
}

abstract class Tool {
  String get name;
  String get description;
  Map<String, Object?> get schema;
  Capability get requires;
  RiskLevel riskFor(Map<String, Object?> args, ToolContext ctx);
  Future<ToolResult> run(Map<String, Object?> args, ToolContext ctx);
}

/// A tool acting on a live element (a page or screen node). Resolution reads
/// the element without changing anything; the executor then classifies risk
/// and asks permission using the returned context's trusted metadata.
abstract interface class TargetResolvingTool implements Tool {
  /// Throws [ToolTargetException] when the target cannot be used.
  Future<ToolContext> resolveTarget(Map<String, Object?> args, ToolContext ctx);
}

class ToolTargetException implements Exception {
  const ToolTargetException(this.code);
  final String code;
  @override
  String toString() => code;
}
