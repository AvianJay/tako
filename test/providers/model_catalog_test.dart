import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/providers/model_catalog.dart';
import 'package:tako/core/providers/provider_config.dart';

void main() {
  test('documented image models auto-select Images API and references', () {
    for (final id in [
      'gpt-image-1',
      'gpt-image-1-mini',
      'gpt-image-1.5',
      'openai/gpt-image-1',
    ]) {
      final spec = ModelCatalog.detect(id)!;
      expect(spec.capabilities.imageGeneration, ImageGenerationMode.imagesApi);
      expect(spec.capabilities.imageReferenceInput, isTrue);
      expect(spec.tools, isFalse);
    }
    expect(ModelCatalog.detect('gpt-image-99'), isNull);
  });

  test(
    'common vendor models, versioned IDs and aliases are recognized explicitly',
    () {
      for (final id in [
        'openai/gpt-5.2',
        'gpt-4.1-mini-2025-04-14',
        'gpt-6.1-sol',
        'anthropic/claude-sonnet-4.6',
        'claude-haiku-4-5-20251001',
        'claude-opus-5-5',
        'z-ai/GLM-4.7-Flash',
        'glm-5.3',
        'glm-5.3-flash',
        'glm-5.1',
        'moonshotai/kimi-k2.5',
        'kimi-k2.6',
        'kimi-k2.7-code-highspeed',
        'kimi-k3',
      ]) {
        expect(ModelCatalog.detect(id), isNotNull, reason: id);
      }
      expect(ModelCatalog.detect('glm-5.3')!.vision, isFalse);
      expect(ModelCatalog.detect('glm-5.3-flash')!.vision, isTrue);
      expect(ModelCatalog.detect('kimi-k3')!.contextWindow, 1048576);
      expect(ModelCatalog.detect('claude-haiku-4-5')!.contextWindow, 200000);
      expect(ModelCatalog.detect('claude-new-future-model'), isNull);
      expect(ModelCatalog.detect('gpt-99-mini'), isNull);
    },
  );
  test(
    'DeepSeek Flash aliases get verified context, output and capabilities',
    () {
      for (final id in [
        'deepseek-flash',
        'deepseek-v4.1-flash',
        'deepseek/DeepSeek-V4.1-Flash',
      ]) {
        final spec = ModelCatalog.detect(id)!;
        expect(spec.contextWindow, 1048576);
        expect(spec.maxOutputTokens, 393216);
        expect(spec.vision && spec.tools && spec.reasoning, isTrue);
        expect(spec.officialId, 'deepseek-flash');
      }
      expect(ModelCatalog.detect('deepseek-v4-pro')!.vision, isFalse);
      expect(ModelCatalog.detect('deepseek-v9.9-flash'), isNull);
      expect(ModelCatalog.detect('some-private-finetune'), isNull);
    },
  );

  test('legacy single model becomes one profile with all overrides intact', () {
    final provider = ProviderConfig.fromJson({
      'id': 'provider',
      'displayName': 'Server',
      'apiType': 'messages',
      'baseUrl': 'https://provider.test',
      'model': 'custom-model',
      'apiKeyRef': 'secret-ref',
      'capabilities': {'contextWindow': 64000, 'vision': true},
      'maxOutputTokens': 2000,
      'reasoningMode': 'enabled',
      'thinkingBudgetTokens': 1024,
    });
    expect(provider.models, hasLength(1));
    final resolved = ProviderConfig.fromJson(
      provider.toJson(),
    ).forModel('custom-model');
    expect(resolved.capabilities.contextWindow, 64000);
    expect(resolved.capabilities.vision, isTrue);
    expect(resolved.capabilities.allowCustomSearchEndpoint, isFalse);
    expect(resolved.maxOutputTokens, 2000);
    expect(resolved.apiKeyRef, 'secret-ref');
    expect(resolved.reasoningMode, ReasoningMode.enabled);
  });

  test('custom search opt-in is persisted separately for each model', () {
    final provider = ProviderConfig(
      id: 'provider',
      displayName: 'CPA',
      apiType: ApiType.responses,
      baseUrl: 'http://127.0.0.1:8317/v1',
      model: 'enabled',
      models: const [
        ModelProfile(
          id: 'enabled',
          capabilities: ProviderCapabilities(
            builtInWebSearch: true,
            allowCustomSearchEndpoint: true,
          ),
        ),
        ModelProfile(id: 'default'),
      ],
    );
    final restored = ProviderConfig.fromJson(provider.toJson());
    expect(
      restored.forModel('enabled').capabilities.allowCustomSearchEndpoint,
      isTrue,
    );
    expect(restored.forModel('enabled').capabilities.builtInWebSearch, isTrue);
    expect(
      restored.forModel('default').capabilities.allowCustomSearchEndpoint,
      isFalse,
    );
  });

  test(
    'model selection uses profile limits and shared provider credentials',
    () {
      final provider = ProviderConfig(
        id: 'provider',
        displayName: 'Server',
        apiType: ApiType.chatCompletions,
        baseUrl: 'https://provider.test',
        model: 'small',
        apiKeyRef: 'shared-ref',
        models: const [
          ModelProfile(id: 'small', maxOutputTokens: 1234),
          ModelProfile(
            id: 'large',
            maxOutputTokens: 8192,
            capabilities: ProviderCapabilities(
              contextWindow: 1048576,
              vision: true,
            ),
          ),
        ],
      );
      final selected = ProviderConfig.fromJson(
        provider.toJson(),
      ).forModel('large');
      expect(selected.model, 'large');
      expect(selected.maxOutputTokens, 8192);
      expect(selected.capabilities.contextWindow, 1048576);
      expect(selected.apiKeyRef, 'shared-ref');
      expect(selected.models, hasLength(2));
      expect(selected.forModel('removed').model, 'small');
    },
  );
}
