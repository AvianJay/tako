import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/providers/image_reference_support.dart';
import 'package:tako/core/providers/model_catalog.dart';
import 'package:tako/core/providers/provider_config.dart';

void main() {
  test(
    'reference counts distinguish documented models and unknown profiles',
    () {
      final limits = {
        'openai/gpt-image-1': 16,
        'gpt-image-2.5-flare-2026-09-08': 16,
        'google/gemini-2.5-flash-image:free': 3,
        'gemini-3-pro-image-preview': 14,
        'gemini-3.1-flash-image': 14,
        'gemini-nano-banana-2.1': 14,
        'gemini-3.1-flash-lite-image': 14,
        'x-ai/grok-imagine-image-2.0': 5,
        'custom-image-model': 1,
      };
      for (final entry in limits.entries) {
        // A pre-existing saved profile only had the reference-input boolean.
        final config = ProviderConfig(
          id: 'provider',
          displayName: 'Provider',
          apiType: ApiType.chatCompletions,
          baseUrl: 'https://provider.example/v1',
          model: entry.key,
          capabilities: const ProviderCapabilities(
            imageGeneration: ImageGenerationMode.imagesApi,
            imageReferenceInput: true,
          ),
        );
        expect(config.maxReferenceImages, entry.value, reason: entry.key);
        final custom = config.copyWith(
          capabilities: config.capabilities.copyWith(maxReferenceImages: 2),
        );
        expect(custom.maxReferenceImages, 2);
        expect(ProviderConfig.fromJson(custom.toJson()).maxReferenceImages, 2);
        expect(
          config
              .copyWith(
                capabilities: config.capabilities.copyWith(
                  imageReferenceInput: false,
                ),
              )
              .maxReferenceImages,
          0,
        );
      }
    },
  );

  test('documented image models auto-select Images API and references', () {
    for (final id in [
      'gpt-image-1',
      'gpt-image-1-mini',
      'gpt-image-1.5',
      'gpt-image-2',
      'gpt-image-2-2026-04-21',
      'gpt-image-2.5-sunburst',
      'gpt-image-2.5-flare-2026-09-08',
      'openai/gpt-image-2.5-sunburst:free',
      'chatgpt-image-latest',
      'x-ai/grok-imagine-image-2.0',
      'openai/gpt-image-1',
    ]) {
      final spec = ModelCatalog.detect(id)!;
      expect(spec.capabilities.imageGeneration, ImageGenerationMode.imagesApi);
      expect(spec.capabilities.imageReferenceInput, isTrue);
      expect(spec.tools, isFalse);
    }
    expect(ModelCatalog.detect('gpt-image-99'), isNull);
  });

  test('Gemini text and image models use their separate documented limits', () {
    for (final id in [
      'gemini-2.5-pro',
      'gemini-2.5-flash',
      'gemini-2.5-flash-lite',
      'gemini-3.1-pro-preview',
      'gemini-3-flash-preview',
      'gemini-3.1-flash-lite',
      'gemini-3.5-flash-lite',
      'gemini-3.8-flash',
    ]) {
      final spec = ModelCatalog.detect('google/$id')!;
      expect(spec.contextWindow, 1048576, reason: id);
      expect(spec.maxOutputTokens, 65536, reason: id);
      expect(spec.vision && spec.tools && spec.reasoning, isTrue, reason: id);
      expect(spec.imageGeneration, ImageGenerationMode.none);
    }
    for (final id in [
      'gemini-2.5-flash-image',
      'gemini-3-pro-image',
      'gemini-3.1-flash-image',
      'gemini-nano-banana-2.1',
      'gemini-3.1-flash-lite-image',
    ]) {
      final spec = ModelCatalog.detect('google/$id')!;
      expect(spec.imageGeneration, ImageGenerationMode.chatOutput, reason: id);
      expect(spec.imageReferenceInput, isTrue);
      expect(spec.tools, isFalse);
    }
    expect(ModelCatalog.detect('gemini-2.5-flash-image')!.contextWindow, 65536);
    expect(
      ModelCatalog.detect('gemini-3.1-flash-image')!.contextWindow,
      131072,
    );
    expect(
      ModelCatalog.detect('gemini-3.1-flash-lite-image')!.maxOutputTokens,
      4096,
    );
    expect(ModelCatalog.detect('gemini-9.9-flash'), isNull);
  });

  test(
    'new vendor presets and routing variants retain explicit capabilities',
    () {
      for (final id in [
        'gpt-5.5',
        'qwen3.5-plus',
        'qwen3.5-flash',
        'qwen3.6-plus',
        'qwen3.8-max',
        'grok-4.7',
        'mistral-large-4',
        'mistral-large-4-0',
        'mistral-medium-3-5',
        'mistral-small-2603',
        'command-a-plus-05-2026',
        'command-a-reasoning-08-2025',
      ]) {
        expect(ModelCatalog.detect(id), isNotNull, reason: id);
        expect(ModelCatalog.detect('$id:nitro')!.tools, isTrue);
      }
      expect(
        ModelCatalog.detect('qwen/qwen3.6-plus-2026-04-02')!.contextWindow,
        1000000,
      );
      expect(ModelCatalog.detect('qwen3.8-max')!.maxOutputTokens, 131072);
      expect(ModelCatalog.detect('grok-4.7')!.contextWindow, 500000);
      expect(ModelCatalog.detect('command-a-03-2025')!.vision, isFalse);
      expect(ModelCatalog.detect('command-a-vision-07-2025')!.vision, isTrue);
      expect(ModelCatalog.detect('command-a-vision-07-2025')!.tools, isFalse);
      expect(ModelCatalog.detect('mistral-large-custom'), isNull);
      expect(ModelCatalog.detect('qwen3.99-max'), isNull);
      expect(ModelCatalog.detect('gpt-image-2.5-unknown'), isNull);
    },
  );

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
