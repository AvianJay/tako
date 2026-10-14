import 'dart:convert';

import '../../data/audit_repository.dart';
import '../chat/content_block.dart';
import '../permissions/permission_gate.dart';
import '../permissions/risk_classifier.dart';
import '../providers/cancel_token.dart';
import '../util/json.dart';
import 'tool.dart';
import 'tool_registry.dart';

class ToolExecution {
  const ToolExecution({
    required this.result,
    this.attachments = const [],
    this.data,
  });
  final ToolResultBlock result;
  final List<ContentBlock> attachments;
  final Map<String, Object?>? data;
}

class ToolExecutor {
  ToolExecutor({
    required this.registry,
    required this.permissions,
    required this.audit,
    int maxOutputChars = 6000,
  }) : maxOutputChars = maxOutputChars.clamp(256, 60000);

  final ToolRegistry registry;
  final PermissionGate permissions;
  final AuditRepository audit;
  final int maxOutputChars;

  /// Record a loop/budget rejection before any primitive can commit an action.
  Future<ToolExecution> reject(
    ToolCallBlock call,
    ToolContext context,
    String code,
  ) async {
    final id = await audit.start(
      conversationId: context.conversationId,
      messageId: context.messageId,
      toolCallId: call.id,
      toolName: call.name,
      arguments: call.arguments,
      risk: RiskLevel.high,
    );
    final content = jsonEncode({'error': code});
    await audit.finish(
      id,
      decision: code,
      resultSummary: content,
      isError: true,
    );
    return ToolExecution(
      result: ToolResultBlock(
        toolCallId: call.id,
        toolName: call.name,
        content: content,
        isError: true,
      ),
    );
  }

  Future<ToolExecution> execute(ToolCallBlock call, ToolContext context) async {
    final tool = registry.get(call.name);
    final args = tryDecodeObject(call.arguments);
    final argumentIssue = tool != null && args != null
        ? _validate(args, tool.schema)
        : null;
    var risk = RiskLevel.safe;
    var invalid = tool == null
        ? 'tool_unavailable'
        : args == null
        ? 'invalid_arguments'
        : argumentIssue != null
        ? 'invalid_arguments'
        : null;
    var cancelledEarly = false;
    if (tool is TargetResolvingTool && args != null && invalid == null) {
      // Resolve the live element before classification, so permission uses
      // its trusted label and password state rather than the model's claim.
      try {
        context = await tool.resolveTarget(args, context);
      } on RequestCancelled {
        cancelledEarly = true;
      } on ToolTargetException catch (error) {
        invalid = error.code;
      } catch (_) {
        invalid = 'tool_failed';
      }
    }
    if (tool != null && args != null && invalid == null && !cancelledEarly) {
      try {
        risk = RiskClassifier.classify(
          toolName: tool.name,
          declaredRisk: tool.riskFor(args, context),
          args: args,
          context: context,
          highRiskKeywords: permissions.policy.highRiskKeywords,
        );
      } catch (_) {
        invalid = 'invalid_arguments';
      }
    }
    // Creating the record precedes permission and execution. If the database
    // cannot record a call, execution fails closed before any side effect.
    final auditId = await audit.start(
      conversationId: context.conversationId,
      messageId: context.messageId,
      toolCallId: call.id,
      toolName: call.name,
      arguments: call.arguments,
      risk: risk,
    );
    var decision = 'rejected';
    ToolResult result;
    try {
      if (cancelledEarly) throw const RequestCancelled();
      context.cancel.throwIfCancelled();
      if (invalid != null || tool == null || args == null) {
        result = argumentIssue != null && invalid == 'invalid_arguments'
            ? ToolResult(
                content: jsonEncode({
                  'error': 'invalid_arguments',
                  'path': argumentIssue.path,
                  'expected': argumentIssue.expected,
                  'hint':
                      'Correct this field using the tool schema. No action was executed.',
                }),
                isError: true,
              )
            : _error(invalid ?? 'invalid_arguments');
      } else {
        final approval = await permissions.authorize(
          toolName: tool.name,
          args: args,
          risk: risk,
          context: context,
        );
        decision = approval.reason;
        context.cancel.throwIfCancelled();
        if (!approval.allowed) {
          result = _error(
            approval.reason == 'password_entry_blocked'
                ? 'password_entry_blocked'
                : 'denied_by_user',
          );
        } else if (registry.get(call.name) != tool) {
          result = _error('tool_unavailable');
          decision = 'disabled_before_execution';
        } else {
          // Do not race the completed call against cancellation: a tool may
          // already have committed a side effect and its receipt must be kept.
          // Implementations observe the token before committing or during IO.
          result = await tool.run(args, context);
        }
      }
    } on RequestCancelled {
      decision = 'cancelled';
      result = _error('cancelled');
    } catch (_) {
      // Tool exceptions can contain files, URLs, or native error payloads.
      // Return a stable error without exposing the exception or release logs.
      result = _error('tool_failed');
    }
    final content = _truncate(result.content);
    final attachments = result.attachments.take(8).toList(growable: false);
    final block = ToolResultBlock(
      toolCallId: call.id,
      toolName: call.name,
      content: content,
      isError: result.isError,
      sideEffects: result.sideEffects,
      attachments: attachments,
    );
    await audit.finish(
      auditId,
      decision: decision,
      resultSummary: content,
      isError: result.isError,
    );
    return ToolExecution(
      result: block,
      attachments: attachments,
      data: result.data,
    );
  }

  String _truncate(String value) {
    if (value.length <= maxOutputChars) return value;
    const suffix = '\n[tool output truncated]';
    var end = maxOutputChars - suffix.length;
    // Preserve a UTF-16 surrogate pair when truncating emoji/non-BMP text.
    if (end > 0) {
      final unit = value.codeUnitAt(end - 1);
      if (unit >= 0xd800 && unit <= 0xdbff) end--;
    }
    return '${value.substring(0, end)}$suffix';
  }

  static ToolResult _error(String code) =>
      ToolResult(content: jsonEncode({'error': code}), isError: true);

  /// Small, deterministic validator for the compact tool schemas. Unknown
  /// schemas fail closed; every registered tool uses this supported subset.
  static _ArgumentIssue? _validate(
    Object? value,
    JsonMap schema, [
    int depth = 0,
    String path = r'$',
  ]) {
    _ArgumentIssue issue(String expected) =>
        _ArgumentIssue(path: path, expected: expected);
    if (depth > 12) return issue('nesting depth at most 12');
    final type = schema['type'];
    final validType = switch (type) {
      'object' => value is Map<String, Object?>,
      'array' => value is List<Object?>,
      'string' => value is String,
      'integer' => value is int,
      'number' => value is num && value.isFinite,
      'boolean' => value is bool,
      'null' => value == null,
      null => true,
      _ => false,
    };
    if (!validType) return issue(type is String ? type : 'supported schema');
    final values = asList(schema['enum']);
    if (values != null && !values.contains(value)) {
      return issue('one of ${jsonEncode(values)}');
    }
    if (value is String) {
      final min = asInt(schema['minLength']);
      final max = asInt(schema['maxLength']);
      if ((min != null && value.length < min) ||
          (max != null && value.length > max)) {
        return issue('string length ${min ?? 0}..${max ?? 'unbounded'}');
      }
    }
    if (value is num) {
      final min = schema['minimum'];
      final max = schema['maximum'];
      if ((min is num && value < min) || (max is num && value > max)) {
        return issue('number ${min ?? 'unbounded'}..${max ?? 'unbounded'}');
      }
    }
    if (value is Map<String, Object?>) {
      final properties = asMap(schema['properties']) ?? {};
      final required = asList(schema['required']) ?? [];
      for (final key in required) {
        if (key is! String) return issue('supported required-property schema');
        if (!value.containsKey(key)) {
          return _ArgumentIssue(path: '$path.$key', expected: 'required field');
        }
      }
      for (final entry in value.entries) {
        final property = asMap(properties[entry.key]);
        if (property == null) {
          if (schema['additionalProperties'] == false) {
            // Do not echo model-supplied property names or values: they can
            // contain credentials. Paths below use only trusted schema keys.
            return issue('only properties declared in the tool schema');
          }
        } else {
          final error = _validate(
            entry.value,
            property,
            depth + 1,
            '$path.${entry.key}',
          );
          if (error != null) return error;
        }
      }
    }
    if (value is List<Object?>) {
      final minItems = asInt(schema['minItems']);
      final maxItems = asInt(schema['maxItems']);
      if ((minItems != null && value.length < minItems) ||
          (maxItems != null && value.length > maxItems)) {
        return issue(
          'array length ${minItems ?? 0}..${maxItems ?? 'unbounded'}',
        );
      }
      final itemSchema = asMap(schema['items']);
      if (itemSchema != null) {
        for (final (index, item) in value.indexed) {
          final error = _validate(item, itemSchema, depth + 1, '$path[$index]');
          if (error != null) return error;
        }
      }
    }
    return null;
  }
}

class _ArgumentIssue {
  const _ArgumentIssue({required this.path, required this.expected});
  final String path;
  final String expected;
}
