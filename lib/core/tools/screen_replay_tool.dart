import 'dart:convert';

import '../../data/audit_repository.dart';
import '../../platform/capabilities.dart';
import '../chat/content_block.dart';
import '../providers/cancel_token.dart';
import '../screen/screen_capability.dart';
import '../screen/screen_reading.dart';
import '../util/ids.dart';
import '../util/json.dart';
import 'action_title.dart';
import 'screen_tools.dart';
import 'tool.dart';

/// A bounded explicit game-input plan, never a per-frame LLM loop. Permission
/// is high-risk for the complete coordinate schedule. Each sent gesture gets a
/// native receipt and audit record; Stop cancels waits and future gestures.
class ScreenReplayTool extends Tool implements TargetResolvingTool {
  ScreenReplayTool({
    required this.screen,
    required this.readings,
    required this.audit,
    required this.remaining,
    required this.onStep,
  });
  final ScreenCapability screen;
  final ScreenReadings readings;
  final AuditRepository audit;
  final int Function() remaining;
  final void Function(ToolResultBlock) onStep;
  @override
  String get name => 'screen_replay';
  @override
  String get description =>
      'Replay an explicit timed game-input schedule locally, without model turns between notes. '
      'High-risk batch approval; foreground app and geometry are checked before every gesture. '
      'Times are milliseconds after replay starts (after approval). Coordinates use the latest screenshot pixels or listing points. '
      'Use only calibrated game input; up to 30 seconds / 120 gestures, no overlapping holds. '
      'Stops on late inputs, app/orientation change, errors, warnings or Stop. Never blindly replay after timeout.';
  @override
  Capability get requires => _ReplayAvailability(screen);
  @override
  RiskLevel riskFor(Map<String, Object?> args, ToolContext ctx) =>
      RiskLevel.high;
  @override
  Map<String, Object?> get schema => const {
    'type': 'object',
    'properties': {
      'title': actionTitleSchema,
      'app': {'type': 'string', 'minLength': 1, 'maxLength': 255},
      'max_late_ms': {'type': 'integer', 'minimum': 50, 'maximum': 2000},
      'gestures': {
        'type': 'array',
        'minItems': 1,
        'maxItems': 120,
        'items': {
          'type': 'object',
          'properties': {
            'at_ms': {'type': 'integer', 'minimum': 0, 'maximum': 30000},
            'action': {
              'type': 'string',
              'enum': ['tap', 'long_press', 'drag'],
            },
            'x': {'type': 'number', 'minimum': 0, 'maximum': 100000},
            'y': {'type': 'number', 'minimum': 0, 'maximum': 100000},
            'to_x': {'type': 'number', 'minimum': 0, 'maximum': 100000},
            'to_y': {'type': 'number', 'minimum': 0, 'maximum': 100000},
            'duration_ms': {'type': 'integer', 'minimum': 100, 'maximum': 3000},
          },
          'required': ['at_ms', 'action', 'x', 'y'],
          'additionalProperties': false,
        },
      },
    },
    'required': ['title', 'app', 'gestures'],
    'additionalProperties': false,
  };
  @override
  Future<ToolContext> resolveTarget(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final current = readings.latest(ctx.conversationId);
    if (current == null ||
        current.tree.ownAppInFront ||
        current.tree.packageName != args['app']) {
      throw const ToolTargetException('game_app_changed_read_again');
    }
    final plan = (asList(args['gestures']) ?? [])
        .map((v) => asMap(v)!)
        .toList();
    if (plan.isEmpty || plan.length > remaining()) {
      throw const ToolTargetException('step_limit');
    }
    var until = -1;
    for (final g in plan) {
      final at = g['at_ms'] as int;
      final hold = g['duration_ms'] as int? ?? 0;
      if (at < until ||
          at + hold > 30000 ||
          g['action'] != 'tap' && hold == 0 ||
          g['action'] == 'drag' && (g['to_x'] == null || g['to_y'] == null)) {
        throw const ToolTargetException('invalid_game_schedule');
      }
      until = at + hold;
      for (final pair in [
        (g['x'], g['y']),
        if (g['action'] == 'drag') (g['to_x'], g['to_y']),
      ]) {
        final (x, y) = current.toScreen(
          (pair.$1 as num).toDouble(),
          (pair.$2 as num).toDouble(),
        );
        if (x < 0 ||
            y < 0 ||
            x >= current.tree.width ||
            y >= current.tree.height) {
          throw const ToolTargetException('point_out_of_bounds');
        }
      }
    }
    final first = plan.first;
    final (x, y) = current.toScreen(
      (first['x'] as num).toDouble(),
      (first['y'] as num).toDouble(),
    );
    final info = await screen.resolvePoint(x, y, ctx.cancel);
    if (info.window.packageName != args['app'] ||
        info.window.own ||
        info.window.type != 1) {
      throw const ToolTargetException('game_app_changed_read_again');
    }
    final target = ScreenTarget.resolve(info, x: x, y: y);
    return ctx.withTarget(
      target: current,
      label: target.riskLabel,
      isPassword: target.password,
      details: {
        'app': current.tree.appLabel,
        'gestures': '${plan.length}',
        'duration': '${until / 1000} s',
      },
    );
  }

  @override
  Future<ToolResult> run(Map<String, Object?> args, ToolContext ctx) async {
    final current = ctx.target! as ScreenReading;
    final plan = asList(args['gestures'])!;
    final timer = Stopwatch()..start();
    final receipts = <Map<String, Object?>>[];
    final effects = <SideEffect>[];
    String? error;
    for (final (index, value) in plan.indexed) {
      final g = asMap(value)!;
      try {
        ctx.cancel.throwIfCancelled();
        if (remaining() <= 0) {
          error = 'step_limit';
          break;
        }
        final wait = (g['at_ms'] as int) - timer.elapsedMilliseconds;
        if (wait > 0) {
          await ctx.cancel.bind(
            Future<void>.delayed(Duration(milliseconds: wait)),
          );
        }
        final late = timer.elapsedMilliseconds - (g['at_ms'] as int);
        if (late > (args['max_late_ms'] as int? ?? 500)) {
          error = 'game_input_too_late';
          break;
        }
        final (x, y) = current.toScreen(
          (g['x'] as num).toDouble(),
          (g['y'] as num).toDouble(),
        );
        final end = g['action'] == 'drag'
            ? current.toScreen(
                (g['to_x'] as num).toDouble(),
                (g['to_y'] as num).toDouble(),
              )
            : null;
        final callId = newId();
        final id = await audit.start(
          conversationId: ctx.conversationId,
          messageId: ctx.messageId,
          toolCallId: callId,
          toolName: 'game_${g['action']}',
          arguments: jsonEncode(g),
          risk: RiskLevel.high,
        );
        ToolResultBlock receipt;
        try {
          final outcome = await screen.timedGesture(
            ScreenAction(
              action: g['action'] as String,
              x: x,
              y: y,
              toX: end?.$1,
              toY: end?.$2,
              duration: ((g['duration_ms'] as int? ?? 100) / 1000),
            ),
            app: args['app'] as String,
            width: current.tree.width,
            height: current.tree.height,
            cancel: ctx.cancel,
          );
          receipt = ToolResultBlock(
            toolCallId: callId,
            toolName: 'game_${g['action']}',
            content: jsonEncode(outcome.details),
            sideEffects: [
              const SideEffect(
                kind: 'screen_action',
                summary: 'Timed game gesture',
              ),
            ],
          );
        } on ScreenException catch (e) {
          receipt = ToolResultBlock(
            toolCallId: callId,
            toolName: 'game_${g['action']}',
            content: jsonEncode({'error': e.code}),
            isError: true,
          );
        } on RequestCancelled {
          receipt = ToolResultBlock(
            toolCallId: callId,
            toolName: 'game_${g['action']}',
            content: '{"error":"cancelled"}',
            isError: true,
          );
        } catch (_) {
          receipt = ToolResultBlock(
            toolCallId: callId,
            toolName: 'game_${g['action']}',
            content: '{"error":"game_transport_failed_check_screen"}',
            isError: true,
          );
        }
        await audit.finish(
          id,
          decision: 'approved_timed_batch',
          resultSummary: receipt.content,
          isError: receipt.isError,
        );
        onStep(receipt);
        effects.addAll(receipt.sideEffects);
        receipts.add({
          'gesture': index + 1,
          'late_ms': late,
          'receipt': receipt.content,
          'error': receipt.isError,
        });
        final data = tryDecodeObject(receipt.content);
        final native = asMap(data?['untrusted_receipt']) ?? data;
        if (receipt.isError ||
            native?['blocked_by'] != null ||
            native?['hit_warning'] != null ||
            native?['warning'] != null) {
          error = 'game_gesture_failed_check_screen';
          break;
        }
      } on RequestCancelled {
        error = 'cancelled';
        break;
      }
    }
    return ToolResult(
      content: jsonEncode({
        'completed': error == null,
        'attempted': receipts.length,
        'elapsed_ms': timer.elapsedMilliseconds,
        'error': ?error,
        'receipts': receipts,
        'hint':
            'Read the current screen before planning another segment. Native receipts do not prove a game score.',
      }),
      isError: error != null,
      sideEffects: effects,
    );
  }
}

class _ReplayAvailability implements Capability {
  _ReplayAvailability(this.screen);
  final ScreenCapability screen;
  @override
  bool get isAvailable => screen.isAvailable && screen.supportsTimedGestures;
}
