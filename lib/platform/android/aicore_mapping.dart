import 'dart:convert';

import '../../core/providers/providers.dart';
import '../on_device/system_model_mapping.dart';

/// AICore receives the system prompt, transcript, tools and reply format
/// together as one JSON prompt.
String aicorePrompt(ChatRequest request) => jsonEncode({
  'system': request.systemPrompt,
  'conversation': systemModelConversation(request),
  if (request.tools.isNotEmpty) 'tools': systemModelTools(request),
  'instruction': systemModelInstruction(request),
});
