import 'provider_config.dart';

/// Offline presets verified against publisher documentation on 2026-10-13.
/// Sources and conservative output defaults: docs/model-catalog.md.
class ModelSpec {
  const ModelSpec(
    this.contextWindow,
    this.maxOutputTokens, {
    this.vision = false,
    this.reasoning = false,
    this.tools = true,
    this.imageGeneration = ImageGenerationMode.none,
    this.imageReferenceInput = false,
    this.maxReferenceImages,
    this.officialId,
  });
  final int contextWindow;
  final int maxOutputTokens;
  final bool vision;
  final bool reasoning;
  final bool tools;
  final ImageGenerationMode imageGeneration;
  final bool imageReferenceInput;
  final int? maxReferenceImages;
  final String? officialId;
  ProviderCapabilities get capabilities => ProviderCapabilities(
    contextWindow: contextWindow,
    tools: tools,
    vision: vision,
    reasoning: reasoning,
    imageGeneration: imageGeneration,
    imageReferenceInput: imageReferenceInput,
    maxReferenceImages: maxReferenceImages,
  );
}

abstract final class ModelCatalog {
  static ModelSpec? detect(String model) {
    var id = model.trim().toLowerCase().split('/').last;
    // OpenRouter's routing variants do not change model capabilities.
    id = id.replaceFirst(RegExp(r':(?:free|nitro|online)$'), '');
    // Snapshot suffixes and standard vendor prefixes retain the base model's
    // documented defaults. Arbitrary future family members remain unknown.
    id = id.replaceFirst(RegExp(r'-(?:20\d{2}-\d{2}-\d{2}|20\d{6})$'), '');
    if (id.startsWith('claude-')) id = id.replaceAll('.', '-');
    return switch (id) {
      // https://developers.openai.com/api/reference/python/resources/images/methods/edit
      // Image endpoints do not use token budgets; these are fallback editor
      // values only, not advertised limits for these image models.
      'gpt-image-1' ||
      'gpt-image-1-mini' ||
      'gpt-image-1.5' ||
      'gpt-image-2' ||
      'gpt-image-2.5-sunburst' ||
      'gpt-image-2.5-flare' ||
      'chatgpt-image-latest' => const ModelSpec(
        32768,
        4096,
        tools: false,
        imageGeneration: ImageGenerationMode.imagesApi,
        imageReferenceInput: true,
        maxReferenceImages: 16,
      ),
      // https://api-docs.deepseek.com/quick_start/pricing (1M / 384K)
      'deepseek-flash' ||
      'deepseek-v4.1-flash' ||
      'deepseek-v4-flash' ||
      'deepseek-v4-flash-vision-exp' => const ModelSpec(
        1048576,
        393216,
        vision: true,
        reasoning: true,
        officialId: 'deepseek-flash',
      ),
      'deepseek-v4-pro' || 'deepseek-v4-pro-0813' => const ModelSpec(
        1048576,
        393216,
        reasoning: true,
      ),
      // https://developers.openai.com/api/docs/models/{model}
      'gpt-5.4' ||
      'gpt-5.5' ||
      'gpt-6-astra' ||
      'gpt-6-sol' ||
      'gpt-6.1-sol' ||
      'gpt-6-luna' => const ModelSpec(
        1050000,
        128000,
        vision: true,
        reasoning: true,
      ),
      'gpt-5.4-mini' ||
      'gpt-5.4-nano' ||
      'gpt-5.2' ||
      'gpt-5.1' ||
      'gpt-5' ||
      'gpt-5-mini' ||
      'gpt-5-nano' => const ModelSpec(
        400000,
        128000,
        vision: true,
        reasoning: true,
      ),
      'gpt-4.1' ||
      'gpt-4.1-mini' ||
      'gpt-4.1-nano' => const ModelSpec(1047576, 32768, vision: true),
      'gpt-4o' || 'gpt-4o-mini' => const ModelSpec(128000, 16384, vision: true),
      'o3' || 'o4-mini' => const ModelSpec(
        200000,
        100000,
        vision: true,
        reasoning: true,
      ),
      // https://platform.claude.com/docs/en/models/overview and model pages
      'claude-fable-5-1' ||
      'claude-opus-5-5' ||
      'claude-sonnet-5-5' ||
      'claude-haiku-5-5' ||
      'claude-opus-4-6' ||
      'claude-sonnet-4-6' => const ModelSpec(
        1000000,
        128000,
        vision: true,
        reasoning: true,
      ),
      'claude-haiku-4-5' || 'claude-sonnet-4-5' || 'claude-opus-4-5' =>
        const ModelSpec(200000, 64000, vision: true, reasoning: true),
      // https://docs.z.ai/guides/llm/{model}
      'glm-5.3' ||
      'glm-5.2' => const ModelSpec(1000000, 128000, reasoning: true),
      'glm-5.3-flash' || 'glm-5.3-flashx' => const ModelSpec(
        1000000,
        128000,
        vision: true,
        reasoning: true,
      ),
      'glm-5' ||
      'glm-5.1' ||
      'glm-4.7' ||
      'glm-4.7-flash' ||
      'glm-4.7-flashx' ||
      'glm-4.6' => const ModelSpec(200000, 128000, reasoning: true),
      'glm-4.5' ||
      'glm-4.5-air' ||
      'glm-4.5-x' ||
      'glm-4.5-airx' ||
      'glm-4.5-flash' => const ModelSpec(128000, 96000, reasoning: true),
      // Kimi's documented default output budgets, leaving room for input.
      // https://platform.kimi.ai/docs/guide/kimi-k3-quickstart
      'kimi-k3' => const ModelSpec(
        1048576,
        131072,
        vision: true,
        reasoning: true,
      ),
      'kimi-k2.5' ||
      'kimi-k2.6' ||
      'kimi-k2.7-code' ||
      'kimi-k2.7-code-highspeed' => const ModelSpec(
        262144,
        32768,
        vision: true,
        reasoning: true,
      ),
      'kimi-k2-thinking' || 'kimi-k2-thinking-turbo' => const ModelSpec(
        262144,
        32768,
        reasoning: true,
      ),
      // https://ai.google.dev/gemini-api/docs/models/{model}
      'gemini-2.5-pro' ||
      'gemini-2.5-flash' ||
      'gemini-2.5-flash-lite' ||
      'gemini-3.1-pro-preview' ||
      'gemini-3-flash-preview' ||
      'gemini-3.1-flash-lite' ||
      'gemini-3.5-flash-lite' ||
      'gemini-3.8-flash' => const ModelSpec(
        1048576,
        65536,
        vision: true,
        reasoning: true,
      ),
      // Gemini image output through a compatible chat gateway. Google's
      // native generateContent image endpoint is a different protocol.
      'gemini-2.5-flash-image' ||
      'gemini-2.5-flash-image-preview' => const ModelSpec(
        65536,
        32768,
        vision: true,
        tools: false,
        imageGeneration: ImageGenerationMode.chatOutput,
        imageReferenceInput: true,
        // Google's recommended input count, used as a conservative default.
        maxReferenceImages: 3,
      ),
      'gemini-3-pro-image' || 'gemini-3-pro-image-preview' => const ModelSpec(
        65536,
        32768,
        vision: true,
        reasoning: true,
        tools: false,
        imageGeneration: ImageGenerationMode.chatOutput,
        imageReferenceInput: true,
        maxReferenceImages: 14,
      ),
      'gemini-3.1-flash-image' ||
      'gemini-3.1-flash-image-preview' ||
      'gemini-nano-banana-2.1' => const ModelSpec(
        131072,
        32768,
        vision: true,
        reasoning: true,
        tools: false,
        imageGeneration: ImageGenerationMode.chatOutput,
        imageReferenceInput: true,
        maxReferenceImages: 14,
      ),
      'gemini-3.1-flash-lite-image' => const ModelSpec(
        65536,
        4096,
        vision: true,
        reasoning: true,
        tools: false,
        imageGeneration: ImageGenerationMode.chatOutput,
        imageReferenceInput: true,
        maxReferenceImages: 14,
      ),
      // https://www.alibabacloud.com/help/en/model-studio/qwen3-6-plus
      // https://www.alibabacloud.com/help/en/model-studio/qwen3-5-plus
      // https://www.alibabacloud.com/help/en/model-studio/qwen3-5-flash
      'qwen3.5-plus' || 'qwen3.5-flash' || 'qwen3.6-plus' => const ModelSpec(
        1000000,
        65536,
        vision: true,
        reasoning: true,
      ),
      // https://help.aliyun.com/en/model-studio/qwen3-8-max
      'qwen3.8-max' => const ModelSpec(
        1000000,
        131072,
        vision: true,
        reasoning: true,
      ),
      // https://docs.x.ai/developers/models/grok-4.7
      // No separate output cap is published; use an 8K default.
      'grok-4.7' || 'grok-4.7-latest' => const ModelSpec(
        500000,
        8192,
        vision: true,
        reasoning: true,
      ),
      // https://docs.x.ai/developers/models/grok-imagine-image-2.0
      'grok-imagine-image-2.0' => const ModelSpec(
        32768,
        4096,
        tools: false,
        imageGeneration: ImageGenerationMode.imagesApi,
        imageReferenceInput: true,
        maxReferenceImages: 5,
      ),
      // https://docs.mistral.ai/models/mistral-large-4-0
      // These models publish context limits but no separate output cap.
      'mistral-large-4' || 'mistral-large-4-0' => const ModelSpec(
        1000000,
        8192,
        vision: true,
        reasoning: true,
      ),
      // https://docs.mistral.ai/models/mistral-medium-3-5-26-04
      // https://docs.mistral.ai/models/mistral-small-4-0-26-03
      'mistral-medium-3-5' ||
      'mistral-medium-2604' ||
      'mistral-small-2603' ||
      'mistral-small-latest' => const ModelSpec(
        256000,
        8192,
        vision: true,
        reasoning: true,
      ),
      // https://docs.cohere.com/v2/docs/models
      'command-a-plus-05-2026' => const ModelSpec(
        128000,
        64000,
        vision: true,
        reasoning: true,
      ),
      'command-a-03-2025' => const ModelSpec(256000, 8000),
      'command-a-reasoning-08-2025' => const ModelSpec(
        256000,
        32000,
        reasoning: true,
      ),
      'command-a-vision-07-2025' => const ModelSpec(
        128000,
        8000,
        vision: true,
        tools: false,
      ),
      'command-r7b-12-2024' ||
      'command-r-08-2024' ||
      'command-r-plus-08-2024' => const ModelSpec(128000, 4000),
      _ => null,
    };
  }
}
