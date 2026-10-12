import 'dart:async';

import '../tools/tool.dart';
import 'permission_policy.dart';
import 'risk_classifier.dart';

export 'permission_policy.dart';
export 'risk_level.dart';

enum PermissionChoice { allowOnce, allowInChat, alwaysAllow, deny }

class PermissionRequest {
  const PermissionRequest({
    required this.toolName,
    required this.arguments,
    required this.risk,
    required this.conversationId,
    this.forceAsk = false,
    this.details = const {},
    this.target,
  });

  final String toolName;
  final Map<String, Object?> arguments;
  final RiskLevel risk;
  final String conversationId;
  final bool forceAsk;

  /// Trusted target facts (element label, page), keyed by kind for display.
  final Map<String, String> details;

  /// The resolved target (e.g. a screen element), for highlighting it.
  final Object? target;

  /// High-risk requests always require their own confirmation. Only the
  /// separate explicit settings switch may change that rule.
  List<PermissionChoice> get choices => risk == RiskLevel.high
      ? const [PermissionChoice.allowOnce, PermissionChoice.deny]
      : forceAsk
      ? const [
          PermissionChoice.allowOnce,
          PermissionChoice.alwaysAllow,
          PermissionChoice.deny,
        ]
      : risk == RiskLevel.action
      ? const [
          PermissionChoice.allowInChat,
          PermissionChoice.alwaysAllow,
          PermissionChoice.deny,
        ]
      : PermissionChoice.values;
}

class PermissionDecision {
  const PermissionDecision(this.allowed, this.reason);
  final bool allowed;
  final String reason;
}

class PermissionGate {
  PermissionGate({
    PermissionPolicy? policy,
    this.onPolicyChanged,
    this.onPendingChanged,
  }) : policy = policy ?? const PermissionPolicy();

  PermissionPolicy policy;
  final Future<void> Function(PermissionPolicy)? onPolicyChanged;
  final void Function(PermissionRequest?)? onPendingChanged;
  final _chatApprovals = <String, Set<String>>{};
  PermissionRequest? _pending;
  Completer<PermissionChoice>? _answer;

  PermissionRequest? get pendingApproval => _pending;

  void decide(PermissionChoice choice) {
    final answer = _answer;
    final pending = _pending;
    if (answer == null || answer.isCompleted || pending == null) return;
    if (!pending.choices.contains(choice)) return;
    answer.complete(choice);
  }

  void forgetConversation(String conversationId) =>
      _chatApprovals.remove(conversationId);

  /// Whether [toolName] at [risk] would run now without asking: by policy,
  /// full permissions, or an approval for the whole chat. Never prompts; an
  /// approval for one call does not count.
  bool allowsWithoutAsking({
    required String toolName,
    required RiskLevel risk,
    required String conversationId,
  }) {
    final override = policy.overrides[toolName];
    if (override == ToolPermission.deny || override == ToolPermission.ask) {
      return false;
    }
    if (risk == RiskLevel.high) return policy.skipHighRiskConfirmations;
    if (override == ToolPermission.allow || policy.fullPermissions) return true;
    if (risk == RiskLevel.safe) return true;
    return _chatApprovals[conversationId]?.contains(toolName) ?? false;
  }

  Future<PermissionDecision> authorize({
    required String toolName,
    required Map<String, Object?> args,
    required RiskLevel risk,
    required ToolContext context,
  }) async {
    context.cancel.throwIfCancelled();
    if (RiskClassifier.isPasswordEntry(toolName, args, context)) {
      return const PermissionDecision(false, 'password_entry_blocked');
    }
    final override = policy.overrides[toolName];
    if (override == ToolPermission.deny) {
      return const PermissionDecision(false, 'denied_by_policy');
    }
    if (risk == RiskLevel.high) {
      if (policy.skipHighRiskConfirmations && override != ToolPermission.ask) {
        return const PermissionDecision(true, 'high_risk_opt_in');
      }
    } else if (override != ToolPermission.ask) {
      if (override == ToolPermission.allow || policy.fullPermissions) {
        return const PermissionDecision(true, 'allowed_by_policy');
      }
      if (risk == RiskLevel.safe) {
        return const PermissionDecision(true, 'safe');
      }
      if (_chatApprovals[context.conversationId]?.contains(toolName) ?? false) {
        return const PermissionDecision(true, 'allowed_in_chat');
      }
    }
    if (_pending != null) {
      // The agent loop executes calls sequentially. Failing closed avoids
      // accidentally resolving an approval belonging to a different call.
      return const PermissionDecision(false, 'approval_busy');
    }
    final answer = Completer<PermissionChoice>();
    _answer = answer;
    _pending = PermissionRequest(
      toolName: toolName,
      arguments: Map.unmodifiable(args),
      risk: risk,
      conversationId: context.conversationId,
      forceAsk: override == ToolPermission.ask,
      details: context.targetDetails,
      target: context.target,
    );
    try {
      onPendingChanged?.call(_pending);
      final choice = await context.cancel.bind(answer.future);
      context.cancel.throwIfCancelled();
      if (choice == PermissionChoice.deny) {
        return const PermissionDecision(false, 'denied_by_user');
      }
      if (risk != RiskLevel.high) {
        if (choice == PermissionChoice.alwaysAllow) {
          final updated = policy.copyWith(
            overrides: {...policy.overrides, toolName: ToolPermission.allow},
          );
          await onPolicyChanged?.call(updated);
          context.cancel.throwIfCancelled();
          policy = updated;
        } else if (choice == PermissionChoice.allowInChat ||
            (risk == RiskLevel.action && override != ToolPermission.ask)) {
          _chatApprovals
              .putIfAbsent(context.conversationId, () => <String>{})
              .add(toolName);
        }
      }
      return PermissionDecision(true, choice.name);
    } finally {
      _answer = null;
      _pending = null;
      onPendingChanged?.call(null);
    }
  }
}
