import 'dart:convert';

import '../../platform/capabilities.dart';
import '../chat/content_block.dart';
import '../screen/screen_capability.dart';
import '../util/json.dart';
import 'action_title.dart';
import 'screen_tools.dart';
import 'tool.dart';
import 'tool_executor.dart';

/// One provider turn for a bounded sequence on a known stable screen. Each
/// constituent action still resolves, authorizes and audits through the executor.
class ScreenSequenceTool extends Tool {
  ScreenSequenceTool({
    required this.screen,
    required this.readings,
    required this.executor,
    this.remaining,
    this.onStep,
  });
  final ScreenCapability screen;
  final ScreenReadings readings;
  final ToolExecutor Function() executor;
  final int Function()? remaining;
  final void Function(ToolResultBlock)? onStep;
  @override
  String get name => 'screen_sequence';
  @override
  String get description =>
      'Perform 1–12 actions by current element ids on one stable screen, '
      'such as entering Calculator keys. Every action is checked individually. '
      'Returns one final observation. Never batch navigation, scrolling, '
      'changing apps, or coordinates. Stop on any error or warning.';
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
      'tap_ids': {
        'type': 'array',
        'maxItems': 12,
        'items': {'type': 'integer', 'minimum': 1, 'maximum': 100000},
        'description':
            'A JSON array of integer ids, e.g. [4,7,8,9,12]. Never a quoted string or ellipsis. Includes repeated keys; prefer this for keypads.',
      },
      'actions': {
        'type': 'array',
        'maxItems': 12,
        'items': {
          'type': 'object',
          'properties': {
            'tool': {
              'type': 'string',
              'enum': ['tap', 'type_text'],
            },
            'id': {'type': 'integer', 'minimum': 1, 'maximum': 100000},
            'text': {'type': 'string', 'maxLength': 5000},
            'submit': {'type': 'boolean'},
          },
          'required': ['tool', 'id'],
          'additionalProperties': false,
        },
      },
      'screenshot': {'type': 'boolean'},
    },
    'required': ['title'],
    'additionalProperties': false,
  };

  @override
  Future<ToolResult> run(Map<String, Object?> args, ToolContext ctx) async {
    final title = actionTitle(args);
    final taps = asList(args['tap_ids']);
    final actions = taps == null
        ? asList(args['actions'])
        : [
            for (final id in taps) {'tool': 'tap', 'id': id},
          ];
    if (args.containsKey('tap_ids') == args.containsKey('actions')) {
      return const ToolResult(
        content: '{"error":"use_tap_ids_or_actions"}',
        isError: true,
      );
    }
    if (title == null || actions == null || actions.isEmpty) {
      return const ToolResult(
        content: '{"error":"invalid_arguments"}',
        isError: true,
      );
    }
    // Reject a submission before committing any of its preceding steps.
    if (actions
        .take(actions.length - 1)
        .any((a) => asMap(a)?['submit'] == true)) {
      return const ToolResult(
        content: '{"error":"submission_must_be_last"}',
        isError: true,
      );
    }
    if (actions.length > (remaining?.call() ?? 12)) {
      return const ToolResult(content: '{"error":"step_limit"}', isError: true);
    }
    final initial = readings.latest(ctx.conversationId);
    if (initial == null) {
      return const ToolResult(
        content: '{"error":"read_screen_first"}',
        isError: true,
      );
    }
    final runner = executor();
    final receipts = <Map<String, Object?>>[];
    final effects = <SideEffect>[];
    var attachments = <ContentBlock>[];
    var failed = false;
    for (final (index, value) in actions.indexed) {
      if (ctx.cancel.isCancelled) {
        failed = true;
        receipts.add({'error': 'cancelled'});
        break;
      }
      if (readings.latest(ctx.conversationId)?.tree.token !=
          initial.tree.token) {
        failed = true;
        receipts.add({'error': 'screen_changed_read_again'});
        break;
      }
      final action = asMap(value)!;
      final finalStep = index == actions.length - 1;
      final result = (await runner.execute(
        ToolCallBlock(
          id: '${ctx.messageId}-sequence-$index',
          name: action['tool'] as String,
          arguments: jsonEncode({
            'title': title,
            for (final item in action.entries)
              if (item.key != 'tool') item.key: item.value,
            if (screen.supportsFastActions) 'observe': finalStep,
            if (screen.supportsFastActions &&
                args['screenshot'] == true &&
                finalStep)
              'screenshot': true,
          }),
        ),
        ToolContext(
          conversationId: ctx.conversationId,
          messageId: ctx.messageId,
          cancel: ctx.cancel,
          lastCall: finalStep,
        ),
      )).result;
      onStep?.call(result);
      effects.addAll(result.sideEffects);
      attachments = result.attachments;
      receipts.add({
        'step': index + 1,
        'receipt': result.content,
        'error': result.isError,
      });
      if (result.isError || _needsNewObservation(result.content)) {
        failed = true;
        break;
      }
    }
    return ToolResult(
      content: jsonEncode({
        'completed': !failed,
        'attempted': receipts.where((r) => r.containsKey('step')).length,
        'receipts': receipts,
        if (failed)
          'hint':
              'Read the current screen before planning another sequence; do not repeat committed steps.',
      }),
      isError: failed,
      sideEffects: effects,
      attachments: attachments,
    );
  }

  bool _needsNewObservation(String content) {
    final status = tryDecodeObject(
      content.split('\nscreen after the action:').first,
    );
    if (status == null) return true;
    final receipt = asMap(status['untrusted_receipt']) ?? status;
    return receipt['blocked_by'] != null ||
        receipt['warning'] != null ||
        receipt['hit_warning'] != null ||
        receipt['append_warning'] != null ||
        asMap(receipt['page_check'])?['same_page'] == false;
  }
}
