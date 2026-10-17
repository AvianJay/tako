import '../util/json.dart';
import 'model_names.dart' as names;

/// [onDevice] runs a local model through llama.cpp, AICore or Apple
/// Intelligence, without a URL.
enum ApiType { chatCompletions, responses, messages, onDevice }

/// Conventional routes for a multi-API proxy. Fixed connections keep their API.
ApiType modelApiType(String id, {required ApiType fallback}) {
  final model = id.trim().toLowerCase().split('/').last;
  if (model.startsWith('claude-')) return ApiType.messages;
  if (model.startsWith('gpt-') || RegExp(r'^o[134](?:-|$)').hasMatch(model)) {
    return ApiType.responses;
  }
  if (RegExp(r'^(deepseek|gemini|grok|glm|kimi|qwen)[-]').hasMatch(model)) {
    return ApiType.chatCompletions;
  }
  return fallback;
}

enum ReasoningMode { off, enabled, adaptive }

/// The wire format used to request image output from an individual model.
/// [onDevice] is an image generator of the system, such as Image Playground.
enum ImageGenerationMode {
  none,
  imagesApi,
  chatOutput,
  responsesTool,
  onDevice,
}

class ProviderCapabilities {
  const ProviderCapabilities({
    this.tools = false,
    this.vision = false,
    this.reasoning = false,
    this.contextWindow,
    this.builtInWebSearch = false,
    this.allowCustomSearchEndpoint = false,
    this.imageGeneration = ImageGenerationMode.none,
    this.imageReferenceInput = false,
    this.maxReferenceImages,
  });

  factory ProviderCapabilities.fromJson(JsonMap json) => ProviderCapabilities(
    tools: asBool(json['tools']) ?? false,
    vision: asBool(json['vision']) ?? false,
    reasoning: asBool(json['reasoning']) ?? false,
    contextWindow: asInt(json['contextWindow']),
    builtInWebSearch: asBool(json['builtInWebSearch']) ?? false,
    allowCustomSearchEndpoint:
        asBool(json['allowCustomSearchEndpoint']) ?? false,
    imageGeneration: ImageGenerationMode.values.firstWhere(
      (mode) => mode.name == json['imageGeneration'],
      orElse: () => ImageGenerationMode.none,
    ),
    imageReferenceInput: asBool(json['imageReferenceInput']) ?? false,
    maxReferenceImages: asInt(json['maxReferenceImages']),
  );

  final bool tools;
  final bool vision;
  final bool reasoning;
  final int? contextWindow;
  final bool builtInWebSearch;

  /// Explicit per-model opt-in for compatible proxy-hosted search formats.
  /// This does not grant permission to execute a search by itself.
  final bool allowCustomSearchEndpoint;

  final ImageGenerationMode imageGeneration;
  final bool imageReferenceInput;

  /// Null uses the model preset, or one image for an unknown model.
  final int? maxReferenceImages;

  bool get acceptsImageInput => imageGeneration == ImageGenerationMode.none
      ? vision
      : imageReferenceInput;

  /// A dedicated image model: it turns the newest prompt into images, without
  /// tools or the rest of the conversation.
  bool get imagesOnly =>
      imageGeneration == ImageGenerationMode.imagesApi ||
      imageGeneration == ImageGenerationMode.onDevice;

  ProviderCapabilities copyWith({
    bool? tools,
    bool? vision,
    bool? reasoning,
    int? contextWindow,
    bool? builtInWebSearch,
    bool? allowCustomSearchEndpoint,
    ImageGenerationMode? imageGeneration,
    bool? imageReferenceInput,
    int? maxReferenceImages,
  }) => ProviderCapabilities(
    tools: tools ?? this.tools,
    vision: vision ?? this.vision,
    reasoning: reasoning ?? this.reasoning,
    contextWindow: contextWindow ?? this.contextWindow,
    builtInWebSearch: builtInWebSearch ?? this.builtInWebSearch,
    allowCustomSearchEndpoint:
        allowCustomSearchEndpoint ?? this.allowCustomSearchEndpoint,
    imageGeneration: imageGeneration ?? this.imageGeneration,
    imageReferenceInput: imageReferenceInput ?? this.imageReferenceInput,
    maxReferenceImages: maxReferenceImages ?? this.maxReferenceImages,
  );

  JsonMap toJson() => {
    'tools': tools,
    'vision': vision,
    'reasoning': reasoning,
    'contextWindow': contextWindow,
    'builtInWebSearch': builtInWebSearch,
    'allowCustomSearchEndpoint': allowCustomSearchEndpoint,
    'imageGeneration': imageGeneration.name,
    'imageReferenceInput': imageReferenceInput,
    if (maxReferenceImages != null) 'maxReferenceImages': maxReferenceImages,
  };
}

class ModelProfile {
  const ModelProfile({
    required this.id,
    this.label,
    this.apiType,
    this.capabilities = const ProviderCapabilities(),
    this.maxOutputTokens = 4096,
    this.reasoningMode = ReasoningMode.off,
    this.thinkingBudgetTokens = 1024,
    this.reasoningEffort = 'medium',
    this.autoDetect = false,
  });
  final String id;
  final String? label;
  final ApiType? apiType;
  String get displayName => names.modelDisplayName(id, suppliedName: label);
  final ProviderCapabilities capabilities;
  final int maxOutputTokens;
  final ReasoningMode reasoningMode;
  final int thinkingBudgetTokens;
  final String reasoningEffort;
  final bool autoDetect;
  factory ModelProfile.fromJson(JsonMap json) => ModelProfile(
    id: asString(json['id']) ?? '',
    label: asString(json['label']),
    apiType: ApiType.values.where((v) => v.name == json['apiType']).firstOrNull,
    capabilities: ProviderCapabilities.fromJson(
      asMap(json['capabilities']) ?? {},
    ),
    maxOutputTokens: asInt(json['maxOutputTokens']) ?? 4096,
    reasoningMode: ReasoningMode.values.firstWhere(
      (v) => v.name == json['reasoningMode'],
      orElse: () => ReasoningMode.off,
    ),
    thinkingBudgetTokens: asInt(json['thinkingBudgetTokens']) ?? 1024,
    reasoningEffort: asString(json['reasoningEffort']) ?? 'medium',
    autoDetect: asBool(json['autoDetect']) ?? false,
  );
  JsonMap toJson() => {
    'id': id,
    if (label != null) 'label': label,
    if (apiType != null) 'apiType': apiType!.name,
    'capabilities': capabilities.toJson(),
    'maxOutputTokens': maxOutputTokens,
    'reasoningMode': reasoningMode.name,
    'thinkingBudgetTokens': thinkingBudgetTokens,
    'reasoningEffort': reasoningEffort,
    'autoDetect': autoDetect,
  };
}

/// Contains references to secrets, never the API key itself. Extra headers are
/// runtime-only: callers hydrate them from secure storage before making requests.
class ProviderConfig {
  ProviderConfig({
    required this.id,
    required this.displayName,
    required this.apiType,
    required this.baseUrl,
    required this.model,
    this.autoFetchModels = true,
    this.autoRouteModels = false,
    this.disableReasoning = false,
    this.apiKeyRef,
    this.extraHeadersRef,
    this.extraHeaders = const {},
    bool? isLocal,
    this.capabilities = const ProviderCapabilities(),
    this.maxOutputTokens = 4096,
    this.reasoningMode = ReasoningMode.off,
    this.thinkingBudgetTokens = 1024,
    this.reasoningEffort = 'medium',
    List<ModelProfile>? models,
  }) : _models = models == null || models.isEmpty
           ? null
           : List.unmodifiable(models),
       isLocal = apiType == ApiType.onDevice
           ? true
           : isLocal ?? isLocalHost(Uri.tryParse(baseUrl)?.host ?? '');

  factory ProviderConfig.fromJson(JsonMap json) => ProviderConfig(
    id: asString(json['id']) ?? '',
    displayName: asString(json['displayName']) ?? '',
    apiType: ApiType.values.firstWhere(
      (v) => v.name == json['apiType'],
      orElse: () => ApiType.chatCompletions,
    ),
    baseUrl: asString(json['baseUrl']) ?? '',
    model: asString(json['model']) ?? '',
    autoFetchModels: asBool(json['autoFetchModels']) ?? true,
    autoRouteModels: asBool(json['autoRouteModels']) ?? false,
    apiKeyRef: asString(json['apiKeyRef']),
    extraHeadersRef: asString(json['extraHeadersRef']),
    isLocal: asBool(json['isLocal']),
    capabilities: ProviderCapabilities.fromJson(
      asMap(json['capabilities']) ?? {},
    ),
    maxOutputTokens: asInt(json['maxOutputTokens']) ?? 4096,
    reasoningMode: ReasoningMode.values.firstWhere(
      (v) => v.name == json['reasoningMode'],
      orElse: () => ReasoningMode.off,
    ),
    thinkingBudgetTokens: asInt(json['thinkingBudgetTokens']) ?? 1024,
    reasoningEffort: asString(json['reasoningEffort']) ?? 'medium',
    models: [
      for (final value in asList(json['models']) ?? <Object?>[])
        if (asMap(value) case final item?) ModelProfile.fromJson(item),
    ],
  );

  final String id;
  final String displayName;
  final ApiType apiType;
  final String baseUrl;
  final String model;
  final bool autoFetchModels;
  final bool autoRouteModels;

  /// Runtime override used by a worker's explicit Off choice.
  final bool disableReasoning;
  ApiType get requestApiType => !autoRouteModels || apiType == ApiType.onDevice
      ? apiType
      : models.where((m) => m.id == model).firstOrNull?.apiType ??
            modelApiType(model, fallback: apiType);
  String get modelDisplayName =>
      models.where((m) => m.id == model).firstOrNull?.displayName ??
      names.modelDisplayName(model);
  final List<ModelProfile>? _models;
  bool get generatesImages => switch (capabilities.imageGeneration) {
    ImageGenerationMode.none => false,
    ImageGenerationMode.imagesApi =>
      apiType == ApiType.chatCompletions || apiType == ApiType.responses,
    ImageGenerationMode.chatOutput => apiType == ApiType.chatCompletions,
    ImageGenerationMode.responsesTool => apiType == ApiType.responses,
    ImageGenerationMode.onDevice => apiType == ApiType.onDevice,
  };

  List<ModelProfile> get models =>
      _models ??
      [
        ModelProfile(
          id: model,
          capabilities: capabilities,
          maxOutputTokens: maxOutputTokens,
          reasoningMode: reasoningMode,
          thinkingBudgetTokens: thinkingBudgetTokens,
          reasoningEffort: reasoningEffort,
        ),
      ];

  ProviderConfig forModel(String? modelId) {
    final profile =
        models.where((m) => m.id == modelId).firstOrNull ?? models.first;
    return copyWith(
      model: profile.id,
      apiType: autoRouteModels && apiType != ApiType.onDevice
          ? profile.apiType ?? modelApiType(profile.id, fallback: apiType)
          : apiType,
      capabilities: profile.capabilities,
      maxOutputTokens: profile.maxOutputTokens,
      reasoningMode: profile.reasoningMode,
      thinkingBudgetTokens: profile.thinkingBudgetTokens,
      reasoningEffort: profile.reasoningEffort,
    );
  }

  final String? apiKeyRef;
  final String? extraHeadersRef;
  final Map<String, String> extraHeaders;
  final bool isLocal;
  final ProviderCapabilities capabilities;
  final int maxOutputTokens;
  final ReasoningMode reasoningMode;
  final int thinkingBudgetTokens;
  final String reasoningEffort;

  JsonMap toJson() => {
    'id': id,
    'models': models.map((m) => m.toJson()).toList(),
    'displayName': displayName,
    'apiType': apiType.name,
    'baseUrl': baseUrl,
    'model': model,
    'autoFetchModels': autoFetchModels,
    'autoRouteModels': autoRouteModels,
    'apiKeyRef': apiKeyRef,
    'extraHeadersRef': extraHeadersRef,
    'isLocal': isLocal,
    'capabilities': capabilities.toJson(),
    'maxOutputTokens': maxOutputTokens,
    'reasoningMode': reasoningMode.name,
    'thinkingBudgetTokens': thinkingBudgetTokens,
    'reasoningEffort': reasoningEffort,
  };

  ProviderConfig copyWith({
    String? id,
    String? displayName,
    ApiType? apiType,
    String? baseUrl,
    String? model,
    bool? autoFetchModels,
    bool? autoRouteModels,
    bool? disableReasoning,
    String? apiKeyRef,
    String? extraHeadersRef,
    Map<String, String>? extraHeaders,
    bool? isLocal,
    ProviderCapabilities? capabilities,
    int? maxOutputTokens,
    ReasoningMode? reasoningMode,
    int? thinkingBudgetTokens,
    String? reasoningEffort,
    List<ModelProfile>? models,
  }) => ProviderConfig(
    id: id ?? this.id,
    displayName: displayName ?? this.displayName,
    apiType: apiType ?? this.apiType,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    autoFetchModels: autoFetchModels ?? this.autoFetchModels,
    autoRouteModels: autoRouteModels ?? this.autoRouteModels,
    disableReasoning: disableReasoning ?? this.disableReasoning,
    apiKeyRef: apiKeyRef ?? this.apiKeyRef,
    extraHeadersRef: extraHeadersRef ?? this.extraHeadersRef,
    extraHeaders: extraHeaders ?? this.extraHeaders,
    isLocal: isLocal ?? this.isLocal,
    capabilities: capabilities ?? this.capabilities,
    maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
    reasoningMode: reasoningMode ?? this.reasoningMode,
    thinkingBudgetTokens: thinkingBudgetTokens ?? this.thinkingBudgetTokens,
    reasoningEffort: reasoningEffort ?? this.reasoningEffort,
    models: models ?? _models,
  );
}

bool isLocalHost(String host) {
  final normalized = host.toLowerCase().replaceAll(RegExp(r'^\[|\]$'), '');
  if (normalized == 'localhost' ||
      normalized.endsWith('.localhost') ||
      normalized.endsWith('.local') ||
      normalized == '::1' ||
      normalized.startsWith('fc') && normalized.contains(':') ||
      normalized.startsWith('fd') && normalized.contains(':') ||
      normalized.startsWith('fe80:')) {
    return true;
  }
  final parts = normalized.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null || p < 0 || p > 255)) {
    return false;
  }
  return parts[0] == 127 ||
      parts[0] == 10 ||
      parts[0] == 192 && parts[1] == 168 ||
      parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31 ||
      parts[0] == 169 && parts[1] == 254;
}

/// Accepts an API root with or without /v1 (and endpoint URLs pasted by users).
/// Arbitrary versioned proxy prefixes are kept intact.
Uri providerEndpoint(String baseUrl, String endpoint) {
  final uri = Uri.tryParse(baseUrl.trim());
  if (uri == null ||
      !const ['https', 'http'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException('Invalid provider URL');
  }
  var path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  path = path.replaceFirst(
    RegExp(
      r'/(chat/completions|responses|messages|models|images/generations|images/edits)$',
    ),
    '',
  );
  if (path.isEmpty) path = '/v1';
  return uri.replace(
    path: '$path/${endpoint.replaceFirst(RegExp(r'^/+'), '')}',
  );
}
