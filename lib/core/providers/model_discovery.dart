import 'model_catalog.dart';
import 'provider_adapter.dart';
import 'provider_config.dart';

/// Add discoveries without replacing edited limits, capabilities or selections.
ProviderConfig mergeDiscoveredModels(
  ProviderConfig provider,
  List<ModelInfo> discovered,
) {
  final models = List<ModelProfile>.of(provider.models);
  final ids = models.map((m) => m.id).toSet();
  for (final info in discovered) {
    if (info.id.trim().isEmpty || !ids.add(info.id)) continue;
    final spec = ModelCatalog.detect(info.id);
    final api = provider.autoRouteModels
        ? modelApiType(info.id, fallback: provider.apiType)
        : provider.apiType;
    final capable =
        spec?.capabilities ?? const ProviderCapabilities(contextWindow: 32768);
    final reasoning = capable.reasoning
        ? api == ApiType.messages &&
                  RegExp(
                    r'^claude-.*(?:5[.-]5|4[.-]6)(?:-|$)',
                  ).hasMatch(info.id.split('/').last)
              ? ReasoningMode.adaptive
              : ReasoningMode.enabled
        : ReasoningMode.off;
    models.add(
      ModelProfile(
        id: info.id,
        label: info.displayName == info.id ? null : info.displayName,
        autoDetect: true,
        capabilities: capable,
        // Keep plenty of context and avoid using a publisher's entire output limit.
        maxOutputTokens: 8192,
        reasoningMode: reasoning,
        reasoningEffort: 'low',
      ),
    );
  }
  return provider.copyWith(models: models);
}
