import 'provider_config.dart';

/// Only documented choices for the selected model/API are offered to workers.
List<String> workerReasoningOptions(ProviderConfig provider) {
  if (!provider.capabilities.reasoning) return const [];
  final id = provider.model.toLowerCase().split('/').last;
  if (provider.apiType == ApiType.messages) {
    if (RegExp(r'^claude-.*5[.-]5(?:-|$)').hasMatch(id)) {
      return const ['off', 'low', 'medium', 'high', 'xhigh', 'max'];
    }
    // Older Claude models use a token budget or adaptive effort, not xhigh.
    return const ['off', 'low', 'medium', 'high'];
  }
  if (provider.apiType == ApiType.responses) {
    if (id.startsWith('gpt-6') || id.startsWith('gpt-5.6')) {
      return const ['low', 'medium', 'high', 'xhigh', 'max'];
    }
    return const ['low', 'medium', 'high'];
  }
  return [if (id.startsWith('deepseek-')) 'off', 'low', 'medium', 'high'];
}

ProviderConfig withWorkerReasoning(ProviderConfig worker, String? effort) {
  if (effort == null ||
      effort.isEmpty ||
      !workerReasoningOptions(worker).contains(effort)) {
    return worker;
  }
  return worker.copyWith(
    reasoningMode: effort == 'off'
        ? ReasoningMode.off
        : worker.apiType == ApiType.messages &&
              worker.reasoningMode == ReasoningMode.adaptive
        ? ReasoningMode.adaptive
        : ReasoningMode.enabled,
    reasoningEffort: effort == 'off' ? worker.reasoningEffort : effort,
    disableReasoning: effort == 'off',
    thinkingBudgetTokens:
        worker.apiType == ApiType.messages &&
            worker.reasoningMode != ReasoningMode.adaptive &&
            effort != 'off'
        ? (switch (effort) {
            'low' => 1024,
            'medium' => 4096,
            _ => 8192,
          }).clamp(1024, worker.maxOutputTokens - 1)
        : worker.thinkingBudgetTokens,
  );
}
