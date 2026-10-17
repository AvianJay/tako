import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/core/tools/image_generation_tool.dart';
import 'package:tako/core/tools/tool.dart';
import 'package:tako/platform/workspace/local_workspace.dart';

final _png = base64Encode(img.encodePng(img.Image(width: 23, height: 11)));

Map<String, Object?> _receipt(ToolResult result) =>
    jsonDecode(result.content) as Map<String, Object?>;

class _Adapter implements ProviderAdapter {
  final requests = <ChatRequest>[];

  @override
  Future<List<ModelInfo>> listModels({CancelToken? cancel}) async => [];

  @override
  Stream<ProviderEvent> send(
    ChatRequest request, {
    required CancelToken cancel,
  }) async* {
    requests.add(request);
    yield GeneratedImage(base64: _png, mimeType: 'image/png');
    yield const Done('stop');
  }
}

ProviderConfig _model(String id, {int? limit, bool references = true}) =>
    ProviderConfig(
      id: id,
      displayName: id,
      apiType: ApiType.chatCompletions,
      baseUrl: 'https://provider.example/v1',
      model: id,
      capabilities: ProviderCapabilities(
        imageGeneration: ImageGenerationMode.imagesApi,
        imageReferenceInput: references,
        maxReferenceImages: limit,
      ),
    );

void main() {
  late Directory root;
  late LocalWorkspace workspace;
  late _Adapter adapter;
  late List<ProviderConfig> models;
  late List<ImageBlock> attached;
  late List<String> selected;
  late ToolContext context;
  late ImageGenerationTool tool;
  late String referencePath;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tako_reference_images_');
    workspace = LocalWorkspace(rootDirectory: root);
    adapter = _Adapter();
    models = [_model('single', limit: 1), _model('multiple', limit: 16)];
    attached = [];
    selected = [];
    context = ToolContext(
      conversationId: 'chat',
      messageId: 'user',
      cancel: CancelToken(),
    );
    final image = await workspace.importBytes(
      'reference.png',
      base64Decode(_png),
    );
    referencePath = (image as ImageBlock).path;
    tool = ImageGenerationTool(
      workspace: workspace,
      models: () => models,
      adapterFor: (provider) async {
        selected.add(provider.id);
        return adapter;
      },
      attachedImages: (_) => attached,
    );
  });

  tearDown(() async => root.delete(recursive: true));

  test(
    'combines attached and workspace references and selects a fitting model',
    () async {
      attached = [
        await workspace.importBytes('attached-one.png', base64Decode(_png))
            as ImageBlock,
        await workspace.importBytes('attached-two.png', base64Decode(_png))
            as ImageBlock,
      ];
      final result = await tool.run({
        'prompt': 'Combine all three images',
        'use_attached_images': true,
        'reference_images': [referencePath],
      }, context);
      expect(result.isError, isFalse);
      expect(selected, ['multiple']);
      final references = adapter.requests.single.messages.single.content
          .whereType<ImageBlock>()
          .toList();
      expect(references.map((image) => image.path), [
        ...attached.map((image) => image.path),
        referencePath,
      ]);
      expect(references.every((image) => image.data != null), isTrue);
      expect(result.attachments.whereType<ImageBlock>(), hasLength(1));
    },
  );

  test(
    'explicit single-image model rejects all references before reading paths',
    () async {
      final result = await tool.run({
        'prompt': 'Combine these',
        'provider_id': 'single',
        'reference_images': ['missing-one.png', 'missing-two.png'],
      }, context);
      final receipt = _receipt(result);
      expect(result.isError, isTrue);
      expect(receipt['error'], 'too_many_reference_images');
      expect(receipt['reference_image_count'], 2);
      final candidates = receipt['models'] as List<Object?>;
      expect(
        (candidates.single as Map<String, Object?>)['max_reference_images'],
        1,
      );
      expect(selected, isEmpty);
      expect(adapter.requests, isEmpty);
    },
  );

  test(
    'all sixteen workspace references reach a compatible image model',
    () async {
      final result = await tool.run({
        'prompt': 'Use all references',
        'reference_images': List.filled(16, referencePath),
      }, context);
      expect(result.isError, isFalse);
      expect(selected, ['multiple']);
      expect(
        adapter.requests.single.messages.single.content.whereType<ImageBlock>(),
        hasLength(16),
      );
    },
  );

  test('unknown reference-capable models default to a single input', () async {
    models = [_model('custom-image-model')];
    final result = await tool.run({
      'prompt': 'Use both references',
      'reference_images': [referencePath, referencePath],
    }, context);
    expect(_receipt(result)['error'], 'too_many_reference_images');
    expect(selected, isEmpty);
  });

  test('attachment and path counts share the overall request limit', () async {
    attached = [ImageBlock(path: referencePath, mimeType: 'image/png')];
    final result = await tool.run({
      'prompt': 'Use all references',
      'use_attached_images': true,
      'reference_images': List.filled(16, referencePath),
    }, context);
    expect(_receipt(result)['error'], 'too_many_reference_images');
    expect(selected, isEmpty);
  });

  test('generation-only models report unsupported references', () async {
    models = [_model('text-only', references: false)];
    final result = await tool.run({
      'prompt': 'Edit this',
      'reference_images': [referencePath],
    }, context);
    expect(_receipt(result)['error'], 'image_references_unsupported');
    expect(tool.description, contains('"max_reference_images":0'));
    expect(selected, isEmpty);
  });
}
