import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tako/app/app_controller.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/data/database.dart';
import 'package:tako/platform/media_attachment_capability.dart';
import 'package:tako/platform/services.dart';
import 'package:tako/platform/workspace/local_workspace.dart';

class _Media implements MediaAttachmentCapability {
  @override
  bool isAvailable = true;
  List<ContentBlock> selected = const [];
  List<ContentBlock> recovered = const [];
  Completer<List<ContentBlock>>? pending;
  Object? failure;
  int selections = 0;
  int captures = 0;
  int recoveries = 0;
  int? requestedLimit;
  CancelToken? token;

  Future<List<ContentBlock>> _result(CancelToken? cancel) async {
    token = cancel;
    if (failure != null) throw failure!;
    if (pending case final delayed?) {
      return await (cancel?.bind(delayed.future) ?? delayed.future);
    }
    return selected;
  }

  @override
  Future<List<ContentBlock>> pickPhotos({int limit = 8, CancelToken? cancel}) {
    selections++;
    requestedLimit = limit;
    return _result(cancel);
  }

  @override
  Future<List<ContentBlock>> capturePhoto({CancelToken? cancel}) {
    captures++;
    return _result(cancel);
  }

  @override
  Future<List<ContentBlock>> recoverLostPhotos({
    int limit = 8,
    CancelToken? cancel,
  }) async {
    recoveries++;
    requestedLimit = limit;
    if (failure != null) throw failure!;
    return recovered;
  }
}

class _Services extends PlatformServices {
  _Services(this._workspace, this._mediaAttachments);
  final LocalWorkspace _workspace;
  final _Media _mediaAttachments;
  @override
  LocalWorkspace get workspace => _workspace;
  @override
  _Media get mediaAttachments => _mediaAttachments;

  @override
  Future<DeviceContext> deviceContext() async => const DeviceContext();
  @override
  Future<String?> readSecret(String reference) async => null;
  @override
  Future<void> writeSecret(String reference, String? value) async {}
}

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
    yield const TextDelta('Image received');
    yield const Done('stop');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LocalWorkspace workspace;
  late AppDatabase database;
  late _Media media;
  late _Adapter adapter;
  late AppController app;
  final png = Uint8List.fromList(
    img.encodePng(img.Image(width: 23, height: 11)),
  );
  const existing = FileBlock(
    path: 'attachments/existing.txt',
    name: 'existing.txt',
    mimeType: 'text/plain',
    sizeBytes: 5,
    extractedText: 'draft',
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tako_attachment_test_');
    workspace = LocalWorkspace(rootDirectory: root);
    database = AppDatabase(NativeDatabase.memory());
    media = _Media();
    adapter = _Adapter();
    app = AppController(
      database: database,
      services: _Services(workspace, media),
      promptTemplate: '{{app_name}}',
      adapterFactory: (_, _, _) => adapter,
    );
    await app.initialize();
  });
  tearDown(() async {
    app.dispose();
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'keyboard image is copied and sent without retaining the IME URI',
    () async {
      const uri = 'content://keyboard/temporary/image/123';
      await app.insertKeyboardImage(
        mimeType: 'image/png',
        uri: uri,
        bytes: png,
      );
      final imported = app.draftAttachments.single as ImageBlock;
      expect(imported.path, startsWith('attachments/'));
      expect(imported.mimeType, 'image/jpeg');
      expect(imported.data, isNull);
      expect(jsonEncode(imported.toJson()), isNot(contains(uri)));
      await app.saveProvider(
        ProviderConfig(
          id: 'vision',
          displayName: 'Vision',
          apiType: ApiType.chatCompletions,
          baseUrl: 'http://127.0.0.1:8080',
          model: 'test-vision',
          capabilities: const ProviderCapabilities(vision: true),
        ),
      );
      await app.send('');
      expect(app.draftAttachments, isEmpty);
      final sent = adapter.requests.single.messages.first.content
          .whereType<ImageBlock>()
          .single;
      expect(img.decodeJpg(base64Decode(sent.data!))!.width, 23);
      final persisted = (await app.chats.getMessages(
        app.conversation!.id,
      )).first.content.whereType<ImageBlock>().single;
      expect(persisted.path, imported.path);
      expect(persisted.data, isNull);
      expect(jsonEncode(persisted.toJson()), isNot(contains(uri)));
    },
  );

  test(
    'unsupported and absent IME payloads preserve existing drafts',
    () async {
      app.draftAttachments = [existing];
      await app.insertKeyboardImage(
        mimeType: 'text/html',
        uri: 'https://example.invalid/untrusted',
        bytes: png,
      );
      expect(app.errorCode, 'unsupportedImage');
      expect(app.draftAttachments, [existing]);
      for (final bytes in [null, Uint8List(0)]) {
        await app.insertKeyboardImage(
          mimeType: 'image/png',
          uri: 'content://not-readable',
          bytes: bytes,
        );
        expect(app.errorCode, 'imageUnavailable');
        expect(app.draftAttachments, [existing]);
        expect(app.busy, isFalse);
      }
      expect(await root.list().isEmpty, isTrue);
    },
  );

  test(
    'invalid image bytes preserve drafts and release the mutation guard',
    () async {
      app.draftAttachments = [existing];
      await expectLater(
        app.insertKeyboardImage(
          mimeType: 'image/png',
          uri: 'content://keyboard/not-an-image',
          bytes: Uint8List.fromList(utf8.encode('not a PNG')),
        ),
        throwsFormatException,
      );
      expect(app.draftAttachments, [existing]);
      expect(app.busy, isFalse);
      expect(await root.list().isEmpty, isTrue);
      await app.insertKeyboardImage(
        mimeType: 'image/jpeg',
        uri: 'content://keyboard/valid',
        bytes: png,
      );
      expect(app.draftAttachments, hasLength(2));
      expect(app.draftAttachments.last, isA<ImageBlock>());
    },
  );

  test(
    'photo selection honors remaining capacity even if picker ignores it',
    () async {
      final first = await workspace.importImageBytes('first.png', png);
      final second = await workspace.importImageBytes('second.png', png);
      app.draftAttachments = List.filled(7, existing);
      media.selected = [first, second];
      await app.importPhotos();
      expect(media.requestedLimit, 1);
      expect(app.draftAttachments, hasLength(8));
      expect(app.draftAttachments.last, same(first));
      expect(app.errorCode, 'attachmentLimit');
      await app.capturePhoto();
      await app.importPhotos();
      await app.insertKeyboardImage(
        mimeType: 'image/png',
        uri: 'content://keyboard/image',
        bytes: png,
      );
      expect(media.captures, 0);
      expect(media.selections, 1);
      expect(app.draftAttachments, hasLength(8));
    },
  );

  test(
    'camera capture appends an image and dismissal keeps the draft',
    () async {
      app.draftAttachments = [existing];
      media.selected = [await workspace.importImageBytes('camera.jpg', png)];
      await app.capturePhoto();
      expect(media.captures, 1);
      expect(app.draftAttachments, [existing, media.selected.single]);
      media.selected = [];
      await app.capturePhoto();
      expect(app.draftAttachments, hasLength(2));
      expect(app.errorCode, isNull);
      expect(app.busy, isFalse);
    },
  );

  test('picker failure keeps attachments available for retry', () async {
    app.draftAttachments = [existing];
    media.failure = const MediaAttachmentException('access_denied');
    await expectLater(
      app.importPhotos(),
      throwsA(isA<MediaAttachmentException>()),
    );
    expect(app.draftAttachments, [existing]);
    expect(app.busy, isFalse);
    media.failure = null;
    await app.importPhotos();
    expect(media.selections, 2);
  });

  test(
    'Stop discards late picker results and preserves the prior draft',
    () async {
      app.draftAttachments = [existing];
      final lateImage = await workspace.importImageBytes('late.png', png);
      final pending = media.pending = Completer<List<ContentBlock>>();
      final importing = app.importPhotos();
      expect(app.busy, isTrue);
      app.stop();
      await importing;
      expect(media.token!.isCancelled, isTrue);
      expect(app.busy, isFalse);
      expect(app.draftAttachments, [existing]);
      expect(app.errorCode, isNull);
      pending.complete([lateImage]);
      await Future<void>.delayed(Duration.zero);
      expect(app.draftAttachments, [existing]);
    },
  );

  test(
    'lost camera results restore within capacity and failures stay recoverable',
    () async {
      app.draftAttachments = [existing];
      media.recovered = [
        await workspace.importImageBytes('recovered.png', png),
      ];
      await app.recoverLostAttachments();
      expect(media.recoveries, 1);
      expect(media.requestedLimit, 7);
      expect(app.draftAttachments, [existing, media.recovered.single]);
      media.failure = const MediaAttachmentException('media_read_failed');
      await app.recoverLostAttachments();
      expect(app.errorCode, 'imageUnavailable');
      expect(app.draftAttachments, hasLength(2));
      expect(app.busy, isFalse);
      media.isAvailable = false;
      await app.recoverLostAttachments();
      expect(media.recoveries, 2);
    },
  );
}
