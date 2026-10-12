import 'provider_config.dart';

/// Offline presets verified against publisher documentation on 2026-10-11.
class ModelSpec {
  const ModelSpec(
    this.contextWindow,
    this.maxOutputTokens, {
    this.vision = false,
    this.reasoning = false,
    this.tools = true,
    this.officialId,
  });
  final int contextWindow;
  final int maxOutputTokens;
  final bool vision;
  final bool reasoning;
  final bool tools;
  final String? officialId;
  ProviderCapabilities get capabilities => ProviderCapabilities(
    contextWindow: contextWindow,
    tools: tools,
    vision: vision,
    reasoning: reasoning,
  );
}

abstract final class ModelCatalog {
  static ModelSpec? detect(String model) {
    var id = model.trim().toLowerCase().split('/').last;
    // Snapshot suffixes and standard vendor prefixes retain the base model's
    // documented defaults. Arbitrary future family members remain unknown.
    id = id.replaceFirst(RegExp(r'-(?:20\d{2}-\d{2}-\d{2}|20\d{6})$'), '');
    if (id.startsWith('claude-')) id = id.replaceAll('.', '-');
    return switch (id) {
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
      _ => null,
    };
  }
}
