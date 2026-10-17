import '../chat/content_block.dart';
import '../chat/message.dart';
import 'model_catalog.dart';
import 'provider_adapter.dart';
import 'provider_config.dart';
import 'provider_event.dart';

/// Bounds workspace reference inputs independently of the message attachment cap.
const maxImageReferenceInputs = 16;

extension ImageReferenceSupport on ProviderConfig {
  /// Saved overrides take precedence over presets, including for older profiles
  /// whose reference-image setting was only a boolean. Unknown models use one
  /// reference until the user configures their supported count.
  int get maxReferenceImages {
    if (!generatesImages || !capabilities.imageReferenceInput) return 0;
    if (capabilities.imageGeneration == ImageGenerationMode.onDevice) return 1;
    final limit =
        capabilities.maxReferenceImages ??
        ModelCatalog.detect(model)?.maxReferenceImages ??
        1;
    final transportLimit =
        capabilities.imageGeneration == ImageGenerationMode.imagesApi &&
            Uri.tryParse(baseUrl)?.host == 'api.x.ai'
        ? 5
        : maxImageReferenceInputs;
    return limit.clamp(1, transportLimit);
  }
}

/// Enforce the same input policy for direct generation and tool calls, before
/// opening a network request. Normal vision-only chat is unaffected.
void validateImageReferences(ProviderConfig config, ChatRequest request) {
  if (!config.generatesImages) return;
  final int count;
  if (config.capabilities.imagesOnly) {
    final message = request.messages.reversed
        .where((message) => message.role == MessageRole.user)
        .firstOrNull;
    count = message?.content.whereType<ImageBlock>().length ?? 0;
  } else {
    // Chat image output and Responses replay earlier images as inputs, too.
    int imagesIn(List<ContentBlock> blocks) => blocks.fold(
      0,
      (total, block) =>
          total +
          switch (block) {
            ImageBlock() => imageUrl(block) == null ? 0 : 1,
            ToolResultBlock() => imagesIn(block.attachments),
            _ => 0,
          },
    );
    count = request.messages.fold(
      0,
      (total, message) => total + imagesIn(message.content),
    );
  }
  if (count == 0) return;
  final limit = config.maxReferenceImages;
  if (limit == 0) {
    throw const ProviderError(
      'This image model does not support reference images',
      code: 'unsupported_image_input',
    );
  }
  if (count > limit) {
    throw ProviderError(
      'Use at most $limit reference images for this model (received $count)',
      code: 'too_many_reference_images',
    );
  }
}
