import 'dart:convert';

import '../../platform/capabilities.dart';
import '../chat/content_block.dart';
import '../chat/generated_image_store.dart';
import '../chat/message.dart';
import '../files/workspace.dart';
import '../providers/providers.dart';
import '../util/ids.dart';
import 'tool.dart';

/// Makes configured image models callable from a tool-capable chat model.
class ImageGenerationTool implements Tool, Capability {
  ImageGenerationTool({
    required this.workspace,
    required this.models,
    required this.adapterFor,
    required this.attachedImages,
  });

  final WorkspaceCapability workspace;
  final List<ProviderConfig> Function() models;
  final Future<ProviderAdapter> Function(ProviderConfig) adapterFor;
  final List<ImageBlock> Function(ToolContext) attachedImages;

  @override
  String get name => 'generate_image';

  @override
  String get description =>
      'Generate an image, or edit reference images, using a configured image '
      'model. Images are saved to the workspace; show each one in your reply '
      'by writing <image src="PATH"/> where it belongs, with PATH from images. '
      'Use use_attached_images for images in the latest user message, or '
      'reference_images for workspace paths (including earlier generated images). '
      'Both sources can be combined, in attachment-then-path order. '
      'Each model has a max_reference_images limit; do not omit references to '
      'fit a smaller limit. Omit provider_id/model to select the first model '
      'that accepts the full reference count. '
      'Available models: ${models().map((p) => jsonEncode(_modelInfo(p))).join(', ')}';

  Map<String, Object?> _modelInfo(ProviderConfig provider) => {
    'provider_id': provider.id,
    'provider': provider.displayName,
    'model': provider.model,
    'reference_images': provider.maxReferenceImages > 0,
    'max_reference_images': provider.maxReferenceImages,
  };

  @override
  Map<String, Object?> get schema => {
    'type': 'object',
    'properties': {
      'prompt': {
        'type': 'string',
        'description': 'Describe the desired image or edit.',
      },
      'provider_id': {'type': 'string'},
      'model': {'type': 'string'},
      'use_attached_images': {'type': 'boolean'},
      'reference_images': {
        'type': 'array',
        'items': {'type': 'string'},
        'maxItems': maxImageReferenceInputs,
        'description':
            'Ordered relative workspace image paths. Combined with attached '
            'images, must fit the selected model\'s max_reference_images.',
      },
    },
    'required': ['prompt'],
    'additionalProperties': false,
  };

  @override
  bool get isAvailable => workspace.isAvailable && models().isNotEmpty;
  @override
  Capability get requires => this;
  @override
  RiskLevel riskFor(Map<String, Object?> args, ToolContext ctx) =>
      RiskLevel.action;

  @override
  Future<ToolResult> run(Map<String, Object?> args, ToolContext ctx) async {
    ctx.cancel.throwIfCancelled();
    final prompt = args['prompt'];
    final paths = args['reference_images'];
    if (prompt is! String ||
        prompt.trim().isEmpty ||
        paths != null && (paths is! List || paths.any((p) => p is! String))) {
      return _error('invalid_arguments');
    }
    if (paths is List && paths.length > maxImageReferenceInputs) {
      return _error('too_many_reference_images');
    }
    final references = <ImageBlock>[
      if (args['use_attached_images'] == true) ...attachedImages(ctx),
    ];
    if (args['use_attached_images'] == true && references.isEmpty) {
      return _error('no_reference_images');
    }
    final referenceCount =
        references.length + (paths is List ? paths.length : 0);
    if (referenceCount > maxImageReferenceInputs) {
      return _error('too_many_reference_images');
    }
    final wantsReferences = referenceCount > 0;
    final candidates = models().where(
      (p) =>
          (args['provider_id'] == null || p.id == args['provider_id']) &&
          (args['model'] == null || p.model == args['model']),
    );
    final provider = candidates
        .where((p) => referenceCount <= p.maxReferenceImages)
        .firstOrNull;
    if (provider == null) {
      if (wantsReferences && candidates.any((p) => p.maxReferenceImages > 0)) {
        return ToolResult(
          content: jsonEncode({
            'error': 'too_many_reference_images',
            'reference_image_count': referenceCount,
            'models': [
              for (final candidate in candidates) _modelInfo(candidate),
            ],
          }),
          isError: true,
        );
      }
      return _error(
        wantsReferences && candidates.isNotEmpty
            ? 'image_references_unsupported'
            : 'image_model_unavailable',
      );
    }
    if (paths is List) {
      for (final path in paths.cast<String>()) {
        final image = (await workspace.read(path, cancel: ctx.cancel)).image;
        if (image == null) return _error('invalid_reference_image');
        references.add(image);
      }
    }
    final hydrated = await workspace.hydrateBlocks(
      references,
      vision: true,
      cancel: ctx.cancel,
    );
    final adapter = await ctx.cancel.bind(adapterFor(provider));
    final images = <ImageBlock>[];
    var completed = false;
    String? failure;
    try {
      await for (final event in adapter.send(
        ChatRequest(
          systemPrompt:
              'Generate the requested image. Use any attached images as references.',
          messages: [
            ChatMessage(
              id: newId(),
              conversationId: ctx.conversationId,
              role: MessageRole.user,
              content: [TextBlock(prompt.trim()), ...hydrated],
              createdAt: DateTime.now(),
              timezoneOffsetMinutes: 0,
            ),
          ],
        ),
        cancel: ctx.cancel,
      )) {
        ctx.cancel.throwIfCancelled();
        if (event is GeneratedImage) {
          if (images.length >= 8) {
            failure = 'too_many_generated_images';
            break;
          }
          images.add(
            await storeGeneratedImage(workspace, event, cancel: ctx.cancel),
          );
        } else if (event is ProviderError) {
          // Stable codes only: never expose another provider's raw response.
          failure = 'image_generation_failed';
          break;
        } else if (event is Done) {
          completed = true;
          break;
        }
      }
      ctx.cancel.throwIfCancelled();
    } on RequestCancelled {
      if (images.isEmpty) rethrow;
      failure = 'cancelled';
    } catch (_) {
      if (images.isEmpty) rethrow;
      failure = 'image_generation_failed';
    }
    return ToolResult(
      content: jsonEncode({
        if (failure != null || !completed || images.isEmpty)
          'error':
              failure ??
              (completed ? 'no_image_generated' : 'incomplete_image_response'),
        'provider_id': provider.id,
        'model': provider.model,
        'images': [for (final image in images) image.path],
      }),
      isError: failure != null || !completed || images.isEmpty,
      attachments: images,
    );
  }

  ToolResult _error(String code) =>
      ToolResult(content: jsonEncode({'error': code}), isError: true);
}
