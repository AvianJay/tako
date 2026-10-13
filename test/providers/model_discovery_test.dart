import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/providers/messages/messages_adapter.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/core/providers/responses/responses_adapter.dart';

ProviderConfig proxy({bool autoRoute = true}) => ProviderConfig(
  id: 'cpa',
  displayName: 'CPA',
  apiType: ApiType.messages,
  baseUrl: 'https://proxy.test/v1',
  model: 'claude-haiku-5-5',
  autoRouteModels: autoRoute,
  models: const [
    ModelProfile(
      id: 'claude-haiku-5-5',
      capabilities: ProviderCapabilities(tools: true, reasoning: true),
      reasoningMode: ReasoningMode.adaptive,
      reasoningEffort: 'xhigh',
      maxOutputTokens: 8192,
    ),
  ],
);

void main() {
  test(
    'friendly names preserve IDs, dates, vendor qualifiers and custom labels',
    () {
      for (final entry in {
        'claude-haiku-5-5': 'Haiku 5.5',
        'claude-haiku-5.5': 'Haiku 5.5',
        'gpt-6.1-sol': 'GPT 6.1 Sol',
        'icebrick/claude-opus-5-5': 'icebrick / Opus 5.5',
        'unknown/private_model': 'unknown/private_model',
      }.entries) {
        final profile = ModelProfile(id: entry.key);
        expect(profile.displayName, entry.value);
        expect(profile.toJson()['id'], entry.key);
        expect(ModelInfo(id: entry.key).displayName, entry.value);
      }
      expect(
        const ModelInfo(id: 'custom', displayName: 'My model').displayName,
        'My model',
      );
    },
  );

  test(
    'discovery preserves overrides, handles duplicates and routes proxy models',
    () {
      final original = proxy();
      final merged = mergeDiscoveredModels(original, const [
        ModelInfo(id: 'gpt-6.1-sol'),
        ModelInfo(id: 'claude-haiku-5-5'),
        ModelInfo(id: 'gpt-6.1-sol'),
        ModelInfo(id: ''),
        ModelInfo(id: 'deepseek-v4.1-flash'),
        ModelInfo(id: 'unknown'),
      ]);
      final restored = ProviderConfig.fromJson(merged.toJson());
      expect(restored.models, hasLength(4));
      expect(restored.models.first.toJson(), original.models.first.toJson());
      expect(restored.model, original.model);
      expect(restored.forModel('gpt-6.1-sol').apiType, ApiType.responses);
      expect(
        restored.forModel('deepseek-v4.1-flash').apiType,
        ApiType.chatCompletions,
      );
      expect(restored.forModel('unknown').apiType, ApiType.messages);
      expect(restored.forModel('unknown').capabilities.tools, false);
      expect(
        ProviderAdapter.create(restored.forModel('gpt-6.1-sol')),
        isA<ResponsesAdapter>(),
      );
      final fixed = mergeDiscoveredModels(proxy(autoRoute: false), const [
        ModelInfo(id: 'gpt-6.1-sol'),
      ]);
      expect(fixed.forModel('gpt-6.1-sol').apiType, ApiType.messages);
    },
  );

  test(
    'worker Off explicitly disables thinking and Low overrides adaptive effort',
    () {
      final haiku = proxy().forModel('claude-haiku-5-5');
      final off = withWorkerReasoning(haiku, 'off');
      final low = withWorkerReasoning(haiku, 'low');
      const request = ChatRequest(systemPrompt: 'Worker', messages: []);
      expect(MessagesAdapter(off).buildBody(request)['thinking'], {
        'type': 'disabled',
      });
      expect(
        MessagesAdapter(off).buildBody(request).containsKey('output_config'),
        false,
      );
      expect(MessagesAdapter(low).buildBody(request)['output_config'], {
        'effort': 'low',
      });
      expect(low.reasoningMode, ReasoningMode.adaptive);
      final gpt = mergeDiscoveredModels(proxy(), const [
        ModelInfo(id: 'gpt-6.1-sol'),
      ]).forModel('gpt-6.1-sol');
      expect(workerReasoningOptions(gpt), isNot(contains('off')));
      expect(withWorkerReasoning(gpt, 'off').reasoningEffort, 'low');
      expect(
        ResponsesAdapter(
          withWorkerReasoning(gpt, 'high'),
        ).buildBody(request)['reasoning'],
        {'effort': 'high', 'summary': 'auto'},
      );
    },
  );
}
