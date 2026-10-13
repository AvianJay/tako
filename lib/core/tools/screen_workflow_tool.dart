import 'dart:convert';

import '../../platform/capabilities.dart';
import '../chat/content_block.dart';
import '../screen/screen_capability.dart';
import '../util/json.dart';
import 'action_title.dart';
import 'screen_tools.dart';
import 'tool.dart';
import 'tool_executor.dart';

/// Navigation can be planned together without reusing ids across screens.
/// The executor resolves semantic selectors from each new observation and
/// still classifies, authorizes and audits every underlying action.
const screenWorkflowStepsSchema = {
  'type': 'array',
  'minItems': 1,
  'maxItems': 12,
  'items': {
    'type': 'object',
    'properties': {
      'tool': {
        'type': 'string',
        'enum': ['open_app', 'open_url', 'tap', 'type_text', 'read_screen'],
      },
      'package': {'type': 'string', 'minLength': 1, 'maxLength': 255},
      'url': {'type': 'string', 'minLength': 1, 'maxLength': 3000},
      'label': {'type': 'string', 'minLength': 1, 'maxLength': 200},
      'view_id': {'type': 'string', 'minLength': 1, 'maxLength': 255},
      'text': {'type': 'string', 'maxLength': 5000},
      'submit': {'type': 'boolean'},
      'expect_app': {'type': 'string', 'minLength': 1, 'maxLength': 255},
      'expect_text': {'type': 'string', 'minLength': 1, 'maxLength': 200},
    },
    'required': ['tool'],
    'additionalProperties': false,
  },
};

class ScreenWorkflowTool extends Tool {
  ScreenWorkflowTool({
    required this.screen,
    required this.readings,
    required this.executor,
    required this.remaining,
    required this.onStep,
  });
  final ScreenCapability screen;
  final ScreenReadings readings;
  final ToolExecutor Function() executor;
  final int Function() remaining;
  final void Function(ToolResultBlock) onStep;
  @override
  String get name => 'screen_workflow';
  @override
  String get description =>
      'Run up to 12 planned navigation steps locally. '
      'Select controls by exact label or view_id from each fresh screen; never reuse ids or coordinates. '
      'For tap/type_text require expect_app. Each action is independently checked, permitted and audited. '
      'Stops on ambiguity, warnings, changed app or failed text checks. Use known links to skip navigation. '
      'expect_text matches a complete label/value exactly, not a substring. '
      'Returns completed steps and the final screen; never replay completed steps.';
  @override
  Capability get requires => screen;
  @override
  RiskLevel riskFor(Map<String, Object?> args, ToolContext ctx) =>
      RiskLevel.safe;
  @override
  Map<String, Object?> get schema => const {
    'type': 'object',
    'properties': {
      'title': actionTitleSchema,
      'steps': screenWorkflowStepsSchema,
    },
    'required': ['title', 'steps'],
    'additionalProperties': false,
  };

  @override
  Future<ToolResult> run(Map<String, Object?> args, ToolContext ctx) async {
    final steps = asList(args['steps']) ?? [];
    final title = actionTitle(args);
    if (title == null || steps.isEmpty || steps.length > 12) {
      return _error('invalid_arguments');
    }
    // Validate the whole plan before any side effect.
    for (final value in steps) {
      final step = asMap(value);
      if (step == null) return _error('invalid_arguments');
      final tool = step['tool'];
      if (!{
            'open_app',
            'open_url',
            'tap',
            'type_text',
            'read_screen',
          }.contains(tool) ||
          tool == 'open_app' && step['package'] is! String ||
          tool == 'open_url' && step['url'] is! String ||
          {'tap', 'type_text'}.contains(tool) &&
              (step['expect_app'] is! String ||
                  step.containsKey('label') == step.containsKey('view_id')) ||
          tool == 'type_text' && step['text'] is! String) {
        return _error('invalid_workflow_step');
      }
    }
    if (steps.length > remaining()) return _error('step_limit');
    final receipts = <Map<String, Object?>>[];
    final effects = <SideEffect>[];
    var attachments = <ContentBlock>[];
    String? error;
    var completed = 0;
    for (final (index, value) in steps.indexed) {
      if (ctx.cancel.isCancelled) {
        error = 'cancelled';
        break;
      }
      if (remaining() <= 0) {
        error = 'step_limit';
        break;
      }
      final step = asMap(value)!;
      final tool = step['tool'] as String;
      final current = readings.latest(ctx.conversationId);
      final app = step['expect_app'] as String?;
      if ({'tap', 'type_text'}.contains(tool) &&
          (current == null ||
              current.tree.ownAppInFront ||
              current.tree.packageName != app)) {
        error = 'workflow_app_changed';
        break;
      }
      int? id;
      if ({'tap', 'type_text'}.contains(tool)) {
        var matches = current!.elements.where((e) {
          final n = current.tree.nodes[e.node];
          if (n.password ||
              !n.enabled ||
              (tool == 'type_text' && !n.editable)) {
            return false;
          }
          if (step['view_id'] case final String view) return n.viewId == view;
          final wanted = _normalize(step['label'] as String);
          return [
            n.text,
            n.description,
            n.hint,
            e.label,
          ].whereType<String>().any((s) => _normalize(s) == wanted);
        }).toList();
        if (tool == 'tap') {
          final controls = matches
              .where((e) => current.tree.nodes[e.node].actionable)
              .toList();
          if (controls.isNotEmpty) matches = controls;
        }
        if (matches.length != 1) {
          error = 'workflow_target_missing_or_ambiguous';
          break;
        }
        id = matches.single.id;
      }
      final result = (await executor().execute(
        ToolCallBlock(
          id: '${ctx.messageId}-workflow-$index',
          name: tool,
          arguments: jsonEncode({
            'title': title,
            if (tool == 'open_app') 'package': step['package'],
            if (tool == 'open_url') 'url': step['url'],
            'id': ?id,
            if (tool == 'type_text') ...{
              'text': step['text'],
              'submit': step['submit'] ?? false,
            },
          }),
        ),
        ToolContext(
          conversationId: ctx.conversationId,
          messageId: '${ctx.messageId}-workflow-$index',
          cancel: ctx.cancel,
        ),
      )).result;
      onStep(result);
      effects.addAll(result.sideEffects);
      attachments = result.attachments;
      receipts.add({
        'step': index + 1,
        'tool': tool,
        'receipt': result.content.split('\nscreen after the action:').first,
        'error': result.isError,
      });
      if (result.isError) {
        error = 'workflow_step_failed';
        break;
      }
      completed++;
      final receipt = tryDecodeObject(
        result.content.split('\nscreen after the action:').first,
      );
      final diagnostics = asMap(receipt?['untrusted_receipt']) ?? receipt;
      if (diagnostics?['warning'] != null ||
          diagnostics?['hit_warning'] != null ||
          diagnostics?['blocked_by'] != null ||
          diagnostics?['append_warning'] != null ||
          asMap(diagnostics?['page_check'])?['same_page'] == false) {
        error = 'workflow_warning_read_before_replanning';
        break;
      }
      var seen = readings.latest(ctx.conversationId);
      if (seen == null || seen.tree.token == current?.tree.token) {
        error = 'workflow_observation_unavailable';
        break;
      }
      if (app != null && seen.tree.packageName != app) {
        error = 'workflow_app_changed';
        break;
      }
      if (step['expect_text'] case final String wanted) {
        // Navigation can reply during the transition. Wait only by fresh reads;
        // never replay the action when its postcondition arrives late.
        for (var retry = 0; retry < 2 && remaining() > 0; retry++) {
          if (seen!.tree.nodes
              .where((n) => !n.password)
              .expand((n) => [n.text, n.description])
              .whereType<String>()
              .any((s) => _normalize(s) == _normalize(wanted))) {
            break;
          }
          final refreshed = (await executor().execute(
            ToolCallBlock(
              id: '${ctx.messageId}-workflow-$index-read-$retry',
              name: 'read_screen',
              arguments: jsonEncode({'title': title}),
            ),
            ToolContext(
              conversationId: ctx.conversationId,
              messageId: '${ctx.messageId}-workflow-$index-read-$retry',
              cancel: ctx.cancel,
            ),
          )).result;
          onStep(refreshed);
          if (refreshed.isError) break;
          seen = readings.latest(ctx.conversationId);
          attachments = refreshed.attachments;
          if (seen == null || app != null && seen.tree.packageName != app) {
            break;
          }
        }
        if (seen == null ||
            (app != null && seen.tree.packageName != app) ||
            !seen.tree.nodes
                .where((n) => !n.password)
                .expand((n) => [n.text, n.description])
                .whereType<String>()
                .any((s) => _normalize(s) == _normalize(wanted))) {
          error = 'workflow_postcondition_failed';
          break;
        }
      }
    }
    // The outer response has now consumed a new observation. Sibling calls
    // must not reuse its earlier IDs, and exact verification can finish here.
    final latest = readings.latest(ctx.conversationId);
    if (latest != null) readings.remember(ctx, latest);
    return ToolResult(
      content: jsonEncode({
        'completed': error == null,
        'completed_steps': completed,
        'attempted': receipts.length,
        'error': ?error,
        'receipts': receipts,
        'final_screen': ?readings
            .latest(ctx.conversationId)
            ?.toToolText(maxChars: 4500),
        if (error != null)
          'hint':
              'Replan from the current screen; do not replay completed steps.',
      }),
      isError: error != null,
      sideEffects: effects,
      attachments: attachments,
    );
  }
}

String _normalize(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();
ToolResult _error(String code) =>
    ToolResult(content: jsonEncode({'error': code}), isError: true);
