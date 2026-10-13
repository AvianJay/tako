import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app_controller.dart';
import '../../core/chat/content_block.dart';
import '../../core/chat/message.dart';
import '../../core/tools/action_title.dart';
import '../../l10n/gen/app_localizations.dart';
import 'chat_timeline.dart';
import 'thinking_section.dart';
import 'tool_widgets.dart';

enum _StepState { running, waiting, completed, failed, stopped, incomplete }

/// Snapshot once per build so each step does not walk the conversation tree.
class _RunActivity {
  const _RunActivity({this.ownerId, this.callId, this.awaitingToolName});

  factory _RunActivity.forApp(
    AppController app, {
    List<ChatMessage>? visibleMessages,
  }) {
    if (!app.isGenerating) return const _RunActivity();
    String? ownerId;
    for (final message in (visibleMessages ?? app.visibleMessages).reversed) {
      if (message.role == MessageRole.user) break;
      if (message.role != MessageRole.assistant) continue;
      // A newer answer or still-empty streaming node ends the old batch. Do
      // not find an older call merely because its ID was reused by the model.
      if (message.content.any((block) => block is ToolCallBlock)) {
        ownerId = message.id;
      }
      break;
    }
    final approval = app.pendingApproval;
    return _RunActivity(
      ownerId: ownerId,
      callId: app.activeToolCallId,
      awaitingToolName: approval?.conversationId == app.conversation?.id
          ? approval?.toolName
          : null,
    );
  }

  final String? ownerId;
  final String? callId;
  final String? awaitingToolName;

  bool matches(ToolRunStep step) =>
      ownerId == step.message.id && callId == step.call.id;
}

_StepState _stepState(ToolRunStep step, _RunActivity activity) {
  if (step.result case final result?) {
    try {
      final decoded = jsonDecode(result.content);
      if (decoded is Map &&
          {'remote_control', 'remote_control_check'}.contains(step.call.name)) {
        if (decoded['status'] == 'cancelled') return _StepState.stopped;
        if (decoded['status'] == 'blocked') return _StepState.failed;
        if (decoded['verified'] != true ||
            decoded['semantic_review_needed'] == true) {
          return _StepState.incomplete;
        }
      }
      if (decoded is Map &&
          const {
            'cancelled',
            'canceled',
            'stopped',
          }.contains(decoded['error'])) {
        return _StepState.stopped;
      }
    } on FormatException {
      // Tool text is not required to be JSON.
    }
    return result.isError ? _StepState.failed : _StepState.completed;
  }
  if (step.message.status == MessageStatus.stopped) return _StepState.stopped;
  if (step.message.status == MessageStatus.error) return _StepState.failed;
  if (activity.ownerId == step.message.id) {
    return activity.matches(step) && activity.awaitingToolName != step.call.name
        ? _StepState.running
        : _StepState.waiting;
  }
  return _StepState.incomplete;
}

_StepState _runState(Iterable<_StepState> stepStates) {
  final states = stepStates.toSet();
  for (final state in const [
    _StepState.running,
    _StepState.waiting,
    _StepState.failed,
    _StepState.stopped,
    _StepState.incomplete,
  ]) {
    if (states.contains(state)) return state;
  }
  return _StepState.completed;
}

String _stateLabel(_StepState state, AppLocalizations l) => switch (state) {
  _StepState.running => l.toolRunning,
  _StepState.waiting => l.toolWaiting,
  _StepState.completed => l.toolCompleted,
  _StepState.failed => l.toolFailed,
  _StepState.stopped => l.stopped,
  _StepState.incomplete => l.toolRunIncomplete,
};

String _pretty(String raw) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
  } on FormatException {
    return raw;
  }
}

/// One quiet entry for a consecutive run. Full receipts live in the drawer,
/// rather than taking over the assistant's answer in the conversation.
class ToolRunSummary extends StatelessWidget {
  const ToolRunSummary({
    required this.app,
    required this.run,
    required this.onAttachment,
    required this.onMessageActions,
    super.key,
  });

  final AppController app;
  final ToolRunSegment run;
  final ValueChanged<ContentBlock> onAttachment;
  final ValueChanged<ChatMessage> onMessageActions;

  @override
  Widget build(BuildContext context) {
    if (run.steps.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final activity = _RunActivity.forApp(app);
    final state = _runState(
      run.steps.map((step) => _stepState(step, activity)),
    );
    final current =
        run.steps.where(activity.matches).firstOrNull ?? run.steps.last;
    final label =
        '${l.toolRunSummary(phoneActionTitle(current.call) ?? toolLabel(current.call.name, l), run.steps.length)}'
        ' · ${_stateLabel(state, l)}';
    return Semantics(
      button: true,
      child: InkWell(
        key: ValueKey('tool-run-${run.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          FocusManager.instance.primaryFocus?.unfocus();
          showModalBottomSheet<void>(
            context: context,
            useSafeArea: true,
            isScrollControlled: true,
            showDragHandle: true,
            sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
                ? AnimationStyle.noAnimation
                : null,
            builder: (_) => _ToolRunDrawer(
              runId: run.id,
              conversationId: run.steps.first.message.conversationId,
              onAttachment: onAttachment,
              onMessageActions: onMessageActions,
            ),
          );
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                _StateIcon(state: state),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StateIcon extends StatelessWidget {
  const _StateIcon({required this.state});
  final _StepState state;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = state == _StepState.failed
        ? colors.error
        : colors.onSurfaceVariant;
    if (state == _StepState.running &&
        !MediaQuery.disableAnimationsOf(context)) {
      return SizedBox.square(
        dimension: 14,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
      );
    }
    return Icon(
      switch (state) {
        _StepState.running => Icons.hourglass_top_rounded,
        _StepState.waiting => Icons.more_horiz,
        _StepState.completed => Icons.check_rounded,
        _StepState.failed => Icons.error_outline_rounded,
        _StepState.stopped => Icons.stop_circle_outlined,
        _StepState.incomplete => Icons.help_outline_rounded,
      },
      size: 16,
      color: color,
    );
  }
}

class _ToolRunDrawer extends ConsumerWidget {
  const _ToolRunDrawer({
    required this.runId,
    required this.conversationId,
    required this.onAttachment,
    required this.onMessageActions,
  });
  final String runId;
  final String conversationId;
  final ValueChanged<ContentBlock> onAttachment;
  final ValueChanged<ChatMessage> onMessageActions;

  ToolRunSegment? _currentRun(AppController app, List<ChatMessage> visible) {
    if (app.conversation?.id != conversationId) return null;
    for (final entry in buildChatTimeline(visible)) {
      if (!entry.isAssistantTurn) continue;
      for (final segment in buildAssistantSegments(entry.messages)) {
        if (segment is ToolRunSegment && segment.id == runId) return segment;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appControllerProvider);
    final visible = app.visibleMessages;
    final run = _currentRun(app, visible);
    final activity = _RunActivity.forApp(app, visibleMessages: visible);
    final l = AppLocalizations.of(context);
    final seenMessages = <String>{};
    final reasoning = <String, String>{};
    for (final step in run?.steps ?? <ToolRunStep>[]) {
      if (seenMessages.add(step.message.id)) {
        final text = step.message.content
            .whereType<ReasoningBlock>()
            .map((block) => block.text)
            .where((text) => text.isNotEmpty)
            .join('\n\n');
        if (text.isNotEmpty) reasoning[step.message.id] = text;
      }
    }
    return SizedBox(
      key: const ValueKey('tool-run-drawer'),
      height: MediaQuery.sizeOf(context).height * .84,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.toolRunTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('tool-run-close'),
                    tooltip: l.close,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (run != null &&
                (app.isGenerating || app.activeToolCallId != null))
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: TextButton.icon(
                    key: const ValueKey('tool-run-stop'),
                    onPressed: app.stop,
                    icon: const Icon(Icons.stop_rounded, size: 18),
                    label: Text(l.stop),
                  ),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: run == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(l.toolRunUnavailable),
                      ),
                    )
                  : ListView.separated(
                      key: PageStorageKey('tool-run-details-$runId'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      itemCount: run.steps.length,
                      separatorBuilder: (_, _) => const Divider(height: 32),
                      itemBuilder: (context, index) {
                        final step = run.steps[index];
                        final firstForMessage =
                            index == 0 ||
                            run.steps[index - 1].message.id != step.message.id;
                        return _ToolStepDetail(
                          key: ValueKey(
                            'tool-run-step-${step.message.id}-${step.call.id}',
                          ),
                          step: step,
                          number: index + 1,
                          state: _stepState(step, activity),
                          reasoning: firstForMessage
                              ? reasoning[step.message.id]
                              : null,
                          onAttachment: onAttachment,
                          onMessageActions: onMessageActions,
                        );
                      },
                    ),
            ),
            if (app.pendingApproval != null) ToolApprovalSheet(app: app),
          ],
        ),
      ),
    );
  }
}

class _ToolStepDetail extends StatelessWidget {
  const _ToolStepDetail({
    required this.step,
    required this.number,
    required this.state,
    required this.reasoning,
    required this.onAttachment,
    required this.onMessageActions,
    super.key,
  });
  final ToolRunStep step;
  final int number;
  final _StepState state;
  final String? reasoning;
  final ValueChanged<ContentBlock> onAttachment;
  final ValueChanged<ChatMessage> onMessageActions;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final result = step.result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reasoning case final text?)
          ThinkingSection(text: text, label: l.thinking, hasAnswer: true),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 3, right: 10),
              child: Text(
                '$number',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    phoneActionTitle(step.call) ?? toolLabel(step.call.name, l),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    step.call.name,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _StateIcon(state: state),
                      Text(
                        _stateLabel(state, l),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: state == _StepState.failed
                              ? colors.error
                              : colors.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        DateFormat.Hms(
                          l.localeName,
                        ).format(step.message.wallTime),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: l.messageActions,
              onPressed: () {
                Navigator.pop(context);
                onMessageActions(step.message);
              },
              icon: const Icon(Icons.more_horiz, size: 20),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (result != null) ...[
          Text(l.result, style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          SelectableText(
            _pretty(result.content),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
        ],
        Text(l.arguments, style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        SelectableText(
          _pretty(step.call.arguments),
          style: theme.textTheme.bodySmall,
        ),
        if (result != null) ...[
          if (result.attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final attachment in result.attachments)
                    ActionChip(
                      avatar: Icon(
                        attachment is ImageBlock
                            ? Icons.image_outlined
                            : Icons.attach_file,
                        size: 18,
                      ),
                      label: Text(
                        attachment is FileBlock
                            ? attachment.name
                            : attachment is ImageBlock
                            ? l.image
                            : l.file,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: () => onAttachment(attachment),
                    ),
                ],
              ),
            ),
          if (result.sideEffects.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(l.sideEffectsTitle, style: theme.textTheme.labelLarge),
            for (final effect in result.sideEffects)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SelectableText(
                  effect.summary,
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ],
    );
  }
}
