import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tako/app/app_controller.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/permissions/permission_policy.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/core/tools/tool_settings.dart';
import 'package:tako/data/database.dart';
import 'package:tako/platform/services.dart';
import 'package:tako/platform/workspace/local_workspace.dart';

class _Services extends PlatformServices {
  _Services(this.local);
  final LocalWorkspace local;
  @override
  LocalWorkspace get workspace => local;
  @override
  Future<DeviceContext> deviceContext() async => const DeviceContext();
  @override
  Future<String?> readSecret(String reference) async => null;
  @override
  Future<Map<String, String>> readHeaders(String? reference) async => {};
  @override
  Future<void> writeSecret(String reference, String? value) async {}
}

class _Adapter implements ProviderAdapter {
  _Adapter(this.reply);
  final List<ProviderEvent> Function(ChatRequest) reply;
  final requests = <ChatRequest>[];
  @override
  Future<List<ModelInfo>> listModels({CancelToken? cancel}) async => [];
  @override
  Stream<ProviderEvent> send(
    ChatRequest request, {
    required CancelToken cancel,
  }) async* {
    requests.add(request);
    for (final event in reply(request)) {
      if (cancel.isCancelled) return;
      yield event;
    }
  }
}

ProviderConfig _provider(String id, ProviderCapabilities capabilities) =>
    ProviderConfig(
      id: id,
      displayName: id,
      apiType: ApiType.chatCompletions,
      baseUrl: 'https://provider.example',
      model: id,
      capabilities: capabilities,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LocalWorkspace workspace;
  late AppDatabase db;
  late AppController app;
  late _Adapter chat;
  late _Adapter images;
  final png = Uint8List.fromList(
    img.encodePng(img.Image(width: 23, height: 11)),
  );
  final generated = GeneratedImage(
    base64: base64Encode(png),
    mimeType: 'image/png',
  );
  const imageCaps = ProviderCapabilities(
    imageGeneration: ImageGenerationMode.imagesApi,
    imageReferenceInput: true,
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tako_image_generation_');
    workspace = LocalWorkspace(rootDirectory: root);
    db = AppDatabase(NativeDatabase.memory());
    images = _Adapter((_) => [generated, const Done('stop')]);
    chat = _Adapter(
      (request) => request.messages.last.role == MessageRole.tool
          ? [const TextDelta('Here is your image.'), const Done('stop')]
          : [
              const ToolCallStart('generate', 'generate_image'),
              const ToolCallArgsDelta(
                'generate',
                '{"prompt":"A blue bird","use_attached_images":true}',
              ),
              const ToolCallEnd('generate'),
              const Done('tool_calls'),
            ],
    );
    app = AppController(
      titleGenerator: (_, _, _) async => null,
      database: db,
      services: _Services(workspace),
      promptTemplate: '{{app_name}}',
      adapterFactory: (config, _, _) => config.id == 'chat' ? chat : images,
    );
    await app.initialize();
    await app.savePermissionPolicy(
      const PermissionPolicy(fullPermissions: true),
    );
  });

  tearDown(() async {
    app.dispose();
    await db.close();
    await root.delete(recursive: true);
  });

  test(
    'direct generated image persists original bytes and reloads without base64',
    () async {
      await app.saveProvider(_provider('images', imageCaps));
      await app.send('Draw a blue bird');
      final response = app.messages.last;
      expect(response.status, MessageStatus.done);
      final image = response.content.whereType<ImageBlock>().single;
      expect(await workspace.readBytes(image.path), png);
      final stored = (await app.chats.getMessages(app.conversation!.id)).last;
      expect(stored.content.whereType<ImageBlock>().single.path, image.path);
      expect(stored.content.whereType<ImageBlock>().single.data, isNull);
      expect(jsonEncode(stored.toJson()), isNot(contains(generated.base64)));
    },
  );

  test(
    'reference-capable image model accepts attachments without vision flag',
    () async {
      await app.saveProvider(_provider('images', imageCaps));
      app.draftAttachments = [
        await workspace.importBytes('reference.png', png),
      ];
      await app.send('Make the bird blue');
      expect(app.errorCode, isNull);
      final reference = images.requests.single.messages.last.content
          .whereType<ImageBlock>()
          .single;
      expect(reference.data, isNotEmpty);
      expect(app.messages.last.status, MessageStatus.done);
    },
  );

  test(
    'image model without reference support leaves attachment draft intact',
    () async {
      await app.saveProvider(
        _provider('images', imageCaps.copyWith(imageReferenceInput: false)),
      );
      app.draftAttachments = [
        await workspace.importBytes('reference.png', png),
      ];
      await app.send('Make the bird blue');
      expect(app.errorCode, 'visionRequired');
      expect(app.draftAttachments, hasLength(1));
      expect(images.requests, isEmpty);
    },
  );

  test(
    'text chat injects image tool and routes attachments to configured image model',
    () async {
      await app.saveProvider(
        _provider('chat', const ProviderCapabilities(tools: true)),
      );
      await app.saveProvider(_provider('images', imageCaps));
      app.draftAttachments = [
        await workspace.importBytes('reference.png', png),
      ];
      await app.send('Make this bird blue');
      expect(app.errorCode, isNull);
      expect(
        chat.requests.first.tools.map((tool) => tool.name),
        contains('generate_image'),
      );
      expect(
        chat.requests.first.messages.last.content.whereType<ImageBlock>(),
        isEmpty,
      );
      expect(
        images.requests.single.messages.last.content
            .whereType<ImageBlock>()
            .single
            .data,
        isNotEmpty,
      );
      final result = app.messages
          .expand((m) => m.content)
          .whereType<ToolResultBlock>()
          .single;
      expect(result.isError, isFalse);
      final image = result.attachments.whereType<ImageBlock>().single;
      expect(await workspace.readBytes(image.path), png);
      expect(app.messages.last.status, MessageStatus.done);
      expect(app.messages.last.text, 'Here is your image.');
    },
  );

  test(
    'disabled image tool is not offered and cannot route reference images',
    () async {
      await app.saveProvider(
        _provider('chat', const ProviderCapabilities(tools: true)),
      );
      await app.saveProvider(_provider('images', imageCaps));
      await app.saveToolSettings(
        const ToolSettings(disabled: {'generate_image'}),
      );
      app.draftAttachments = [
        await workspace.importBytes('reference.png', png),
      ];
      await app.send('Use this reference');
      expect(app.errorCode, 'visionRequired');
      expect(chat.requests, isEmpty);
      expect(images.requests, isEmpty);
    },
  );

  test('leaving incognito removes generated originals', () async {
    await app.saveProvider(_provider('images', imageCaps));
    await app.newChat(incognito: true);
    await app.send('Draw a bird');
    final path = app.messages.last.content.whereType<ImageBlock>().single.path;
    expect(await File('${root.path}/$path').exists(), isTrue);
    await app.newChat();
    expect(await File('${root.path}/$path').exists(), isFalse);
  });

  test(
    'image generation bypasses chat token budgets and does not offer function tools',
    () async {
      await app.saveProvider(
        _provider('images', imageCaps.copyWith(tools: true, contextWindow: 1)),
      );
      await app.send('Draw a bird');
      expect(app.errorCode, isNull);
      expect(images.requests.single.tools, isEmpty);
      expect(app.messages.last.status, MessageStatus.done);
    },
  );

  test('generated image can be reattached for an edit', () async {
    await app.saveProvider(_provider('images', imageCaps));
    await app.send('Draw a bird');
    final path = app.messages.last.content.whereType<ImageBlock>().single.path;
    await app.attachWorkspaceImage(path);
    expect(app.draftAttachments.single, isA<ImageBlock>());
    await app.send('Make it blue');
    expect(images.requests.last.messages, hasLength(1));
    final reference = images.requests.last.messages.single.content
        .whereType<ImageBlock>()
        .single;
    expect(reference.path, path);
    expect(reference.data, isNotEmpty);
  });

  test('denied image tool never contacts the image provider', () async {
    await app.saveProvider(
      _provider('chat', const ProviderCapabilities(tools: true)),
    );
    await app.saveProvider(_provider('images', imageCaps));
    await app.savePermissionPolicy(
      const PermissionPolicy(
        overrides: {'generate_image': ToolPermission.deny},
      ),
    );
    app.draftAttachments = [await workspace.importBytes('reference.png', png)];
    await app.send('Make this bird blue');
    final receipt = app.messages
        .expand((m) => m.content)
        .whereType<ToolResultBlock>()
        .single;
    expect(receipt.isError, isTrue);
    expect(images.requests, isEmpty);
  });

  ProviderConfig onDeviceImages() => ProviderConfig(
    id: 'images',
    displayName: 'On-device models',
    apiType: ApiType.onDevice,
    baseUrl: '',
    model: 'apple:image-playground',
    capabilities: const ProviderCapabilities(
      contextWindow: 4096,
      imageGeneration: ImageGenerationMode.onDevice,
      imageReferenceInput: true,
    ),
  );

  test(
    'an on-device image model generates from the newest prompt, without tools',
    () async {
      await app.saveProvider(onDeviceImages());
      await app.send('Draw a bird');
      expect(app.errorCode, isNull);
      expect(images.requests.single.tools, isEmpty);
      expect(images.requests.single.messages, hasLength(1));
      final image = app.messages.last.content.whereType<ImageBlock>().single;
      expect(await workspace.readBytes(image.path), png);
    },
  );

  test(
    'a chat model reaches the on-device image model through generate_image',
    () async {
      await app.saveProvider(
        _provider('chat', const ProviderCapabilities(tools: true)),
      );
      await app.saveProvider(onDeviceImages());
      expect(app.imageModels.single.model, 'apple:image-playground');
      app.draftAttachments = [
        await workspace.importBytes('reference.png', png),
      ];
      await app.send('Make this bird blue');
      expect(app.errorCode, isNull);
      expect(
        chat.requests.first.tools.map((tool) => tool.name),
        contains('generate_image'),
      );
      expect(
        images.requests.single.messages.last.content
            .whereType<ImageBlock>()
            .single
            .data,
        isNotEmpty,
      );
      expect(app.messages.last.text, 'Here is your image.');
    },
  );

  test(
    'model image settings survive JSON and old settings default to disabled',
    () {
      final original = _provider('images', imageCaps);
      final restored = ProviderConfig.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>,
      );
      expect(restored.forModel('images').generatesImages, isTrue);
      expect(restored.capabilities.imageReferenceInput, isTrue);
      expect(
        ProviderCapabilities.fromJson({}).imageGeneration,
        ImageGenerationMode.none,
      );
    },
  );
}
