import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/chat/content_block.dart';
import '../../core/permissions/permission_gate.dart';
import '../../l10n/gen/app_localizations.dart';

String toolLabel(String name, AppLocalizations l) => switch (name) {
  'get_device_status' => l.deviceStatusTool,
  'get_location' => l.locationTool,
  'clipboard_read' => l.clipboardReadTool,
  'clipboard_write' => l.clipboardWriteTool,
  'calendar_list' => l.calendarListTool,
  'calendar_add' => l.calendarAddTool,
  'set_alarm' => l.alarmTool,
  'set_timer' => l.timerTool,
  'open_url' => l.openUrlTool,
  'open_app' => l.openAppTool,
  'web_search' => l.searchTool,
  'fetch_page' => l.fetchTool,
  'file_list' => l.fileListTool,
  'file_read' => l.fileReadTool,
  'file_write' => l.fileWriteTool,
  'file_delete' => l.fileDeleteTool,
  'memory_search' => l.memorySearchTool,
  'memory_save' => l.memorySaveTool,
  'memory_update' => l.memoryUpdateTool,
  'memory_delete' => l.memoryDeleteTool,
  'browser_open' => l.browserOpenTool,
  'browser_read' => l.browserReadTool,
  'browser_click' => l.browserClickTool,
  'browser_type' => l.browserTypeTool,
  'browser_scroll' => l.browserScrollTool,
  'browser_back' => l.browserBackTool,
  'notifications_list' => l.notificationsListTool,
  'read_screen' => l.readScreenTool,
  'tap' => l.tapTool,
  'long_press' => l.longPressTool,
  'swipe' => l.swipeTool,
  'scroll' => l.scrollTool,
  'type_text' => l.typeTextTool,
  'press_key' => l.pressKeyTool,
  'run_shell' => l.runShellTool,
  'list_shortcuts' => l.listShortcutsTool,
  'run_shortcut' => l.runShortcutTool,
  _ => name,
};

/// Labels for [PermissionRequest.details] keys.
String approvalDetailLabel(String key, AppLocalizations l) => switch (key) {
  'element' => l.approvalElement,
  'page' => l.approvalPage,
  'submit' => l.approvalSubmit,
  'app' => l.approvalApp,
  'point' => l.approvalPoint,
  _ => key,
};

String choiceLabel(PermissionChoice choice, AppLocalizations l) =>
    switch (choice) {
      PermissionChoice.allowOnce => l.allowOnce,
      PermissionChoice.allowInChat => l.allowChat,
      PermissionChoice.alwaysAllow => l.alwaysAllow,
      PermissionChoice.deny => l.deny,
    };

String riskLabel(RiskLevel risk, AppLocalizations l) => switch (risk) {
  RiskLevel.safe => l.riskSafe,
  RiskLevel.sensitive => l.riskSensitive,
  RiskLevel.action => l.riskAction,
  RiskLevel.high => l.riskHigh,
};

class ToolCallCard extends StatelessWidget {
  const ToolCallCard({
    required this.call,
    this.result,
    this.running = false,
    this.onAttachment,
    super.key,
  });
  final ToolCallBlock call;
  final ToolResultBlock? result;
  final bool running;
  final ValueChanged<ContentBlock>? onAttachment;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        dense: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Icon(
          result?.isError == true
              ? Icons.error_outline
              : result != null
              ? Icons.check_circle_outline
              : Icons.build_outlined,
          size: 18,
          color: result?.isError == true ? color.error : color.primary,
        ),
        title: Text(
          toolLabel(call.name, l),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        subtitle: Text(
          running
              ? l.toolRunning
              : result == null
              ? l.toolWaiting
              : result!.isError
              ? l.toolFailed
              : l.toolCompleted,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(call.name, style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 8),
                Text(l.arguments),
                SelectableText(
                  call.arguments,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (result case final value?) ...[
                  const Divider(),
                  Text(l.result),
                  SelectableText(
                    value.content,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  for (final attachment in value.attachments)
                    ActionChip(
                      label: Text(attachment is ImageBlock ? l.image : l.file),
                      onPressed: () => onAttachment?.call(attachment),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ToolApprovalSheet extends StatelessWidget {
  const ToolApprovalSheet({required this.app, super.key});
  final AppController app;
  @override
  Widget build(BuildContext context) {
    final request = app.pendingApproval;
    if (request == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: color.surfaceContainer,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              (MediaQuery.sizeOf(context).height -
                  MediaQuery.viewInsetsOf(context).bottom) *
              .55,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.shield_outlined,
                    color: request.risk == RiskLevel.high
                        ? color.error
                        : color.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.approvalTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${toolLabel(request.toolName, l)} · ${riskLabel(request.risk, l)}',
              ),
              // Resolved from the live page, not from the model's arguments.
              for (final MapEntry(:key, :value) in request.details.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${approvalDetailLabel(key, l)}: ',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: value),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                l.approvalBody,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Flexible(
                child: Scrollbar(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      const JsonEncoder.withIndent(
                        '  ',
                      ).convert(request.arguments),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
              const Divider(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final choice in request.choices)
                    choice == PermissionChoice.deny
                        ? OutlinedButton(
                            onPressed: () => app.permissionGate.decide(choice),
                            child: Text(l.deny),
                          )
                        : FilledButton.tonal(
                            onPressed: () => app.permissionGate.decide(choice),
                            child: Text(choiceLabel(choice, l)),
                          ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
