import 'dart:convert';

import '../../platform/capabilities.dart';
import '../chat/content_block.dart';
import '../screen/screen_capability.dart';
import '../screen/screen_reading.dart';
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
        'enum': [
          'open_app',
          'open_url',
          'tap',
          'type_text',
          'read_screen',
          'back',
          'search',
        ],
      },
      'package': {'type': 'string', 'minLength': 1, 'maxLength': 255},
      'name': {'type': 'string', 'minLength': 1, 'maxLength': 100},
      'url': {'type': 'string', 'minLength': 1, 'maxLength': 3000},
      'label': {'type': 'string', 'minLength': 1, 'maxLength': 200},
      'view_id': {'type': 'string', 'minLength': 1, 'maxLength': 255},
      'text': {'type': 'string', 'maxLength': 5000},
      'submit': {'type': 'boolean'},
      'expect_app': {'type': 'string', 'minLength': 1, 'maxLength': 255},
      'expect_text': {'type': 'string', 'minLength': 1, 'maxLength': 200},
      'screenshot': {'type': 'boolean'},
      'max_back': {'type': 'integer', 'minimum': 1, 'maximum': 6},
      'until_label': {'type': 'string', 'minLength': 1, 'maxLength': 200},
      'until_view_id': {'type': 'string', 'minLength': 1, 'maxLength': 255},
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
      'open_app accepts package OR name; installed app names and aliases are resolved locally. '
      'back repeats at most max_back (default 4) visible BackButton taps from fresh screens until until_label/until_view_id is visible, or no BackButton remains. Require expect_app. '
      'search requires expect_app and text: locally opens the unique search entry, finds its fresh editable field, replaces text and submits. Optional label/view_id selects the search entry. Never chooses among ambiguous fields. '
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
            'back',
            'search',
          }.contains(tool) ||
          tool == 'open_app' &&
              (step.containsKey('package') == step.containsKey('name') ||
                  (step['package'] ?? step['name']) is! String) ||
          tool == 'open_url' && step['url'] is! String ||
          {'tap', 'type_text'}.contains(tool) &&
              (step['expect_app'] is! String ||
                  step.containsKey('label') == step.containsKey('view_id')) ||
          tool == 'type_text' && step['text'] is! String) {
        return _error('invalid_workflow_step');
      }
      if (tool == 'back' && step['expect_app'] is! String) {
        return _error('invalid_workflow_step');
      }
      if (tool == 'search' &&
          (step['expect_app'] is! String ||
              step['text'] is! String ||
              step.containsKey('label') && step.containsKey('view_id'))) {
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
      if (tool == 'search') {
        for (var action = 0; action < 3; action++) {
          ctx.cancel.throwIfCancelled();
          final current = readings.latest(ctx.conversationId);
          if (current == null ||
              current.tree.ownAppInFront ||
              current.tree.packageName != step['expect_app']) {
            error = 'workflow_app_changed';
            break;
          }
          if (remaining() <= 0) {
            error = 'step_limit';
            break;
          }
          final candidates = current.elements.where((e) {
            final n = current.tree.nodes[e.node];
            return n.enabled && !n.password && _searchElement(e, n);
          }).toList();
          var fields = candidates
              .where((e) => current.tree.nodes[e.node].editable)
              .toList();
          if (fields.isEmpty && action > 0) {
            fields = current.elements.where((e) {
              final n = current.tree.nodes[e.node];
              return n.enabled && n.editable && !n.password;
            }).toList();
          }
          final explicit =
              action == 0 && (step['label'] != null || step['view_id'] != null);
          var matches = explicit
              ? current.elements.where((e) {
                  final n = current.tree.nodes[e.node];
                  return n.enabled &&
                      !n.password &&
                      (step['view_id'] != null
                          ? n.viewId == step['view_id']
                          : _normalize(e.label) ==
                                _normalize(step['label'] as String));
                }).toList()
              : fields.isNotEmpty
              ? fields
              : candidates;
          matches = _deepestTargets(matches, current);
          if (!explicit && fields.isEmpty && matches.isNotEmpty) {
            final best = matches
                .map((e) => _searchRank(e, current.tree.nodes[e.node]))
                .reduce((a, b) => a > b ? a : b);
            matches = matches
                .where(
                  (e) => _searchRank(e, current.tree.nodes[e.node]) == best,
                )
                .toList();
          }
          if (matches.length != 1 || action == 2 && fields.isEmpty) {
            error = 'workflow_search_missing_or_ambiguous';
            break;
          }
          final target = matches.single;
          final typing = current.tree.nodes[target.node].editable;
          final result = (await executor().execute(
            ToolCallBlock(
              id: '${ctx.messageId}-workflow-$index-search-$action',
              name: typing ? 'type_text' : 'tap',
              arguments: jsonEncode({
                'title': title,
                'id': target.id,
                if (typing) ...{'text': step['text'], 'submit': true},
                if (step['screenshot'] == true) 'screenshot': true,
              }),
            ),
            ToolContext(
              conversationId: ctx.conversationId,
              messageId: '${ctx.messageId}-workflow-$index-search-$action',
              cancel: ctx.cancel,
            ),
          )).result;
          onStep(result);
          effects.addAll(result.sideEffects);
          attachments = result.attachments;
          receipts.add({
            'step': index + 1,
            'tool': typing ? 'type_text' : 'tap',
            'receipt': result.content.split('\nscreen after the action:').first,
            'error': result.isError,
          });
          if (result.isError) {
            error = 'workflow_step_failed';
            break;
          }
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
          final next = readings.latest(ctx.conversationId);
          if (next == null || next.tree.packageName != step['expect_app']) {
            error = 'workflow_app_changed';
            break;
          }
          if (typing) {
            completed++;
            break;
          }
          if (next.tree.token == current.tree.token ||
              next.toToolText() == current.toToolText()) {
            error = 'workflow_search_unchanged';
            break;
          }
          if (action == 2) error = 'workflow_search_field_unavailable';
        }
        if (error != null) break;
        continue;
      }
      if (tool == 'back') {
        var reached = false;
        for (var back = 0; back < (step['max_back'] as int? ?? 4); back++) {
          ctx.cancel.throwIfCancelled();
          final current = readings.latest(ctx.conversationId);
          if (current == null ||
              current.tree.packageName != step['expect_app'] ||
              current.tree.ownAppInFront) {
            error = 'workflow_app_changed';
            break;
          }
          final untilLabel = step['until_label'] as String?;
          final untilView = step['until_view_id'] as String?;
          if (untilLabel != null &&
                  current.elements.any(
                    (e) =>
                        e.viewId != 'BackButton' &&
                        _normalize(e.label) == _normalize(untilLabel),
                  ) ||
              untilView != null &&
                  current.elements.any((e) => e.viewId == untilView)) {
            reached = true;
            break;
          }
          final buttons = current.elements
              .where(
                (e) =>
                    e.viewId == 'BackButton' &&
                    current.tree.nodes[e.node].actionable &&
                    current.tree.nodes[e.node].enabled,
              )
              .toList();
          if (buttons.isEmpty && untilLabel == null && untilView == null) {
            reached = true;
            break;
          }
          if (buttons.length != 1 || remaining() <= 0) {
            error = buttons.length != 1
                ? 'workflow_back_unavailable'
                : 'step_limit';
            break;
          }
          final result = (await executor().execute(
            ToolCallBlock(
              id: '${ctx.messageId}-workflow-$index-back-$back',
              name: 'tap',
              arguments: jsonEncode({'title': title, 'id': buttons.single.id}),
            ),
            ToolContext(
              conversationId: ctx.conversationId,
              messageId: '${ctx.messageId}-workflow-$index-back-$back',
              cancel: ctx.cancel,
            ),
          )).result;
          onStep(result);
          effects.addAll(result.sideEffects);
          attachments = result.attachments;
          receipts.add({
            'step': index + 1,
            'tool': 'back',
            'receipt': result.content.split('\nscreen after the action:').first,
            'error': result.isError,
          });
          if (result.isError) {
            error = 'workflow_step_failed';
            break;
          }
          final next = readings.latest(ctx.conversationId);
          if (next == null || next.tree.token == current.tree.token) {
            error = 'workflow_observation_unavailable';
            break;
          }
          if (next.toToolText() == current.toToolText()) {
            error = 'workflow_back_unchanged';
            break;
          }
        }
        if (!reached && error == null) {
          final current = readings.latest(ctx.conversationId);
          reached =
              current != null &&
              current.tree.packageName == step['expect_app'] &&
              (step['until_label'] != null &&
                      current.elements.any(
                        (e) =>
                            e.viewId != 'BackButton' &&
                            _normalize(e.label) ==
                                _normalize(step['until_label'] as String),
                      ) ||
                  step['until_view_id'] != null &&
                      current.elements.any(
                        (e) => e.viewId == step['until_view_id'],
                      ) ||
                  step['until_label'] == null &&
                      step['until_view_id'] == null &&
                      !current.elements.any((e) => e.viewId == 'BackButton'));
        }
        if (!reached) {
          error ??= 'workflow_back_limit';
          break;
        }
        completed++;
        continue;
      }
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
          // iOS exposes a row Cell and its nested Button with the same label.
          // They are one control, not two choices. Prefer the deepest matching
          // actionable node; identical sibling controls remain ambiguous.
          matches = matches
              .where(
                (candidate) => !matches.any((other) {
                  if (other.node == candidate.node) return false;
                  var parent = current.tree.nodes[other.node].parent;
                  while (parent >= 0) {
                    if (parent == candidate.node) return true;
                    parent = current.tree.nodes[parent].parent;
                  }
                  return false;
                }),
              )
              .toList();
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
            if (tool == 'open_app' && step['package'] != null)
              'package': step['package'],
            if (tool == 'open_app' && step['name'] != null)
              'name': step['name'],
            if (tool == 'open_url') 'url': step['url'],
            'id': ?id,
            if (step['screenshot'] == true) 'screenshot': true,
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

int _searchRank(ScreenElement e, ScreenNode n) {
  final identity = '${n.viewId ?? ''} ${e.label}'.toLowerCase();
  if (RegExp(
    r'search[_ ]?(?:bar|field|input)|pre[_ ]?search|搜尋欄|搜索框',
  ).hasMatch(identity)) {
    return 3;
  }
  if (n.actionable) return 2;
  return 1;
}

bool _searchElement(ScreenElement e, ScreenNode n) {
  final identity = '${n.className} ${n.viewId ?? ''} ${e.label} ${n.hint ?? ''}'
      .toLowerCase();
  if (RegExp(
    r'camera|cart|chat|cancel|history|suggest|相機|購物車|取消',
  ).hasMatch(identity)) {
    return false;
  }
  return RegExp(r'search|搜尋|搜索|搜尋欄|搜索框|查詢').hasMatch(identity) &&
      (n.editable || n.actionable || n.viewId != null);
}

List<ScreenElement> _deepestTargets(
  List<ScreenElement> matches,
  ScreenReading current,
) => matches
    .where(
      (candidate) => !matches.any((other) {
        if (other.node == candidate.node) return false;
        var parent = current.tree.nodes[other.node].parent;
        while (parent >= 0) {
          if (parent == candidate.node) return true;
          parent = current.tree.nodes[parent].parent;
        }
        return false;
      }),
    )
    .toList();
ToolResult _error(String code) =>
    ToolResult(content: jsonEncode({'error': code}), isError: true);
