import 'package:flutter/services.dart';

import '../../core/on_device/on_device_capability.dart';
import '../../core/providers/providers.dart';
import '../../core/util/json.dart';
import '../on_device/system_on_device.dart';
import 'aicore_mapping.dart';

export 'aicore_mapping.dart';

/// ML Kit Prompt API over Android AICore. Model files stay in the service.
class AicoreOnDevice extends SystemOnDevice {
  AicoreOnDevice({MethodChannel? methods, EventChannel? events})
    : super(
        methods: methods ?? const MethodChannel('tw.avianjay.tako/aicore'),
        events: events ?? const EventChannel('tw.avianjay.tako/aicore/events'),
        models: const [aicoreModel, aicorePreviewModel],
      );

  @override
  String get service => 'aicore';

  @override
  Set<String> get setupFailures => const {
    'aicore_unavailable',
    'aicore_update',
    'aicore_failed',
  };

  @override
  LocalModel describe(String id, Map<Object?, Object?> details) {
    final preview = id == aicorePreviewModel.id;
    final context = (asInt(details['contextWindow']) ?? 4096).clamp(1, 1 << 20);
    final baseName = asString(details['baseModelName']) ?? 'Gemini Nano';
    return LocalModel.system(
      id: id,
      name: '$baseName (AICore${preview ? ' Preview' : ''})',
      profile: ModelProfile(
        id: id,
        autoDetect: true,
        capabilities: ProviderCapabilities(
          tools: details['tools'] == true,
          contextWindow: context,
        ),
        maxOutputTokens: 1024,
      ),
    );
  }

  @override
  Map<String, Object?> requestFields(
    ProviderConfig config,
    ChatRequest request,
  ) => {
    'prompt': aicorePrompt(request),
    'useTools': request.tools.isNotEmpty,
    'maxOutputTokens': request.maxTokens ?? config.maxOutputTokens,
  };
}
