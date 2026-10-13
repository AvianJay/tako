import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../core/providers/providers.dart';

class RemoteAgentSettings extends ConsumerWidget {
  const RemoteAgentSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appControllerProvider);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String tr(String en, String tw) => zh ? tw : en;
    final preferences = app.controlSettings;
    final connections = app.providers
        .where((p) => p.models.any((m) => m.capabilities.tools))
        .toList();
    final selected = preferences.remoteAgentProviderId;
    final worker = app.remoteAgentProvider;
    final connection =
        connections.where((p) => p.id == selected).firstOrNull ??
        connections.where((p) => p.id == worker?.id).firstOrNull;
    final models =
        connection?.models.where((m) => m.capabilities.tools).toList() ??
        <ModelProfile>[];
    final efforts = ['', if (worker != null) ...workerReasoningOptions(worker)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        SwitchListTile(
          key: const ValueKey('remote-agent-enabled'),
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Delegate phone tasks', '委派手機操作')),
          subtitle: Text(
            tr(
              'Choose a separate worker model. Your main model plans and checks compact evidence.',
              '選擇獨立的操作模型，主模型負責規劃與檢查精簡證據。',
            ),
          ),
          value: app.controlSettings.remoteAgent,
          onChanged: app.busy
              ? null
              : (value) => app.saveControlSettings(
                  app.controlSettings.copyWith(remoteAgent: value),
                ),
        ),
        if (app.controlSettings.remoteAgent) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey('remote-agent-provider-$selected'),
            initialValue: connections.any((p) => p.id == selected)
                ? selected
                : '',
            isExpanded: true,
            decoration: InputDecoration(
              labelText: tr('Worker provider', '操作模型供應商'),
            ),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(tr('Automatic: Haiku connection', '自動：Haiku 連線')),
              ),
              for (final provider in connections)
                DropdownMenuItem(
                  value: provider.id,
                  child: Text(
                    provider.displayName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: app.busy
                ? null
                : (value) => app.saveControlSettings(
                    preferences.copyWith(
                      remoteAgentProviderId: value,
                      remoteAgentModelId: '',
                      remoteAgentEffort: '',
                    ),
                  ),
          ),
          if (models.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(
                'remote-agent-model-${connection?.id}-${preferences.remoteAgentModelId}',
              ),
              initialValue:
                  models.any((m) => m.id == preferences.remoteAgentModelId)
                  ? preferences.remoteAgentModelId
                  : '',
              isExpanded: true,
              decoration: InputDecoration(
                labelText: tr('Worker model', '操作模型'),
              ),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(tr('Automatic model', '自動選擇模型')),
                ),
                for (final model in models)
                  DropdownMenuItem(
                    value: model.id,
                    child: Text(
                      model.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: app.busy
                  ? null
                  : (value) => app.saveControlSettings(
                      preferences.copyWith(
                        remoteAgentModelId: value,
                        remoteAgentEffort: '',
                      ),
                    ),
            ),
          ],
          if (worker?.capabilities.reasoning == true) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(
                'remote-agent-effort-${preferences.remoteAgentEffort}',
              ),
              initialValue: efforts.contains(preferences.remoteAgentEffort)
                  ? preferences.remoteAgentEffort
                  : '',
              isExpanded: true,
              decoration: InputDecoration(
                labelText: tr('Worker reasoning effort', '操作模型推理強度'),
              ),
              items: [
                for (final effort in efforts)
                  DropdownMenuItem(
                    value: effort,
                    child: Text(
                      effort.isEmpty
                          ? tr(
                              'Model default (${worker?.reasoningEffort})',
                              '模型預設（${worker?.reasoningEffort}）',
                            )
                          : effort == 'off'
                          ? tr('Off (no thinking)', '關閉（不推理）')
                          : effort == 'xhigh'
                          ? tr('Extra', '額外')
                          : switch (effort) {
                              'low' => tr('Low (faster)', '低（較快）'),
                              'medium' => tr('Medium', '中'),
                              'high' => tr('High', '高'),
                              'max' => tr('Maximum', '最高'),
                              _ => effort,
                            },
                    ),
                  ),
              ],
              onChanged: app.busy
                  ? null
                  : (value) => app.saveControlSettings(
                      preferences.copyWith(remoteAgentEffort: value),
                    ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            worker != null
                ? '${tr('Ready', '已就緒')} · ${worker.modelDisplayName} · ${worker.apiType.name} · ${worker.disableReasoning
                      ? 'off'
                      : worker.reasoningMode == ReasoningMode.off
                      ? 'default'
                      : worker.reasoningEffort}'
                : tr(
                    'Add a provider with tool support in Providers, then select it here.',
                    '請在供應商設定新增支援工具的模型，再於此選擇。',
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              'Known workflows run locally first; the worker handles changed screens. Uses the selected connection’s credentials. Only the task and approved screen observations go to it. Enable screenshots for visual controls. Approvals and Stop still apply.',
              '已知流程會先在本機執行，畫面有變時交給操作模型。使用所選連線的憑證，只傳送任務與已允許的螢幕觀察。操作圖示時請啟用截圖；權限確認與停止仍生效。',
            ),
          ),
        ],
      ],
    );
  }
}
