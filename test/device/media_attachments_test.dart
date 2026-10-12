import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/files/workspace.dart';
import 'package:tako/core/providers/cancel_token.dart';
import 'package:tako/platform/media_attachment_capability.dart';
import 'package:tako/platform/native/media_attachments.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Picker picker;
  late _Workspace workspace;
  late NativeMediaAttachments media;

  setUp(() {
    picker = _Picker();
    workspace = _Workspace();
    media = NativeMediaAttachments(workspace, picker: picker);
  });

  test('opts into Android Photo Picker before opening a picker', () {
    final previous = ImagePickerPlatform.instance;
    final android = ImagePickerAndroid()..useAndroidPhotoPicker = false;
    ImagePickerPlatform.instance = android;
    try {
      NativeMediaAttachments(workspace, picker: picker);
      expect(android.useAndroidPhotoPicker, isTrue);
    } finally {
      ImagePickerPlatform.instance = previous;
    }
  });

  test(
    'multiple photos are copied to workspace and fallback limit enforced',
    () async {
      picker.multiple = [
        _File('a.png', [1, 2]),
        _File('b.png', [3]),
        _File('c.png', [4]),
      ];
      final result = await media.pickPhotos(limit: 2);
      expect(picker.limit, 2);
      expect(picker.maxWidth, 1568);
      expect(picker.maxHeight, 1568);
      expect(picker.quality, 85);
      expect(picker.metadata, isFalse);
      expect(workspace.names, ['a.png', 'b.png']);
      expect(workspace.bytes, [
        [1, 2],
        [3],
      ]);
      expect(result, hasLength(2));
      expect((result.first as ImageBlock).path, 'attachments/1.jpg');
      expect((result.first as ImageBlock).data, isNull);
    },
  );

  test('one available slot opens single image selection', () async {
    picker.single = _File('one.jpg', [9]);
    final result = await media.pickPhotos(limit: 1);
    expect(picker.source, ImageSource.gallery);
    expect(picker.multiCalls, 0);
    expect(result, hasLength(1));
  });

  test('camera opens capture and cancellation adds no attachment', () async {
    expect(await media.capturePhoto(), isEmpty);
    expect(picker.source, ImageSource.camera);
    expect(picker.maxWidth, 1568);
    expect(picker.metadata, isFalse);
    expect(workspace.names, isEmpty);
    picker.single = _File('capture.jpg', [7]);
    expect(await media.capturePhoto(), hasLength(1));
  });

  test(
    'activity-loss images are copied and capped; video is ignored',
    () async {
      picker.lost = LostDataResponse(
        type: RetrieveType.image,
        files: [
          _File('a.png', [1]),
          _File('b.png', [2]),
        ],
      );
      expect(await media.recoverLostPhotos(limit: 1), hasLength(1));
      expect(workspace.names, ['a.png']);
      picker.lost = LostDataResponse(
        type: RetrieveType.video,
        files: [
          _File('video.mp4', [3]),
        ],
      );
      expect(await media.recoverLostPhotos(), isEmpty);
      expect(workspace.names, ['a.png']);
    },
  );

  test(
    'cancel returns while native picker pending and ignores late result',
    () async {
      final pending = Completer<List<XFile>>();
      picker.pending = pending.future;
      final cancel = CancelToken();
      final operation = media.pickPhotos(cancel: cancel);
      cancel.cancel();
      await expectLater(operation, throwsA(isA<RequestCancelled>()));
      await expectLater(
        media.capturePhoto(),
        throwsA(
          isA<MediaAttachmentException>().having(
            (e) => e.code,
            'code',
            'already_active',
          ),
        ),
      );
      pending.complete([
        _File('late.png', [1]),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(workspace.names, isEmpty);
      expect(await media.capturePhoto(), isEmpty);
    },
  );

  test(
    'zero slots and pre-cancelled token do not open native picker',
    () async {
      expect(await media.pickPhotos(limit: 0), isEmpty);
      expect(await media.recoverLostPhotos(limit: 0), isEmpty);
      await expectLater(
        media.pickPhotos(cancel: CancelToken()..cancel()),
        throwsA(isA<RequestCancelled>()),
      );
      expect(picker.multiCalls, 0);
      expect(picker.lostCalls, 0);
    },
  );

  test('requested limit cannot exceed the composer maximum', () async {
    picker.multiple = List.generate(12, (i) => _File('$i.png', [i]));
    expect(await media.pickPhotos(limit: 100), hasLength(8));
    expect(picker.limit, 8);
    expect(workspace.names, hasLength(8));
  });

  test(
    'known oversized files are rejected before opening their stream',
    () async {
      final file = _File('huge.jpg', [1], declaredLength: 20 * 1024 * 1024 + 1);
      picker.single = file;
      await expectLater(
        media.capturePhoto(),
        throwsA(
          isA<MediaAttachmentException>().having(
            (e) => e.code,
            'code',
            'image_too_large',
          ),
        ),
      );
      expect(file.opened, isFalse);
      expect(workspace.names, isEmpty);
    },
  );

  test(
    'stream byte cap is enforced when the declared size is inaccurate',
    () async {
      picker.single = _File(
        'misreported.jpg',
        Uint8List(20 * 1024 * 1024 + 1),
        declaredLength: 1,
      );
      await expectLater(
        media.capturePhoto(),
        throwsA(
          isA<MediaAttachmentException>().having(
            (e) => e.code,
            'code',
            'image_too_large',
          ),
        ),
      );
      expect(workspace.names, isEmpty);
    },
  );

  test('cancellation interrupts a stalled file stream and closes it', () async {
    final subscribed = Completer<void>();
    var streamCancelled = false;
    final stream = StreamController<Uint8List>(
      onListen: subscribed.complete,
      onCancel: () => streamCancelled = true,
    );
    picker.single = _File('slow.jpg', [], customStream: stream.stream);
    final cancel = CancelToken();
    final operation = media.capturePhoto(cancel: cancel);
    await subscribed.future;
    cancel.cancel();
    await expectLater(operation, throwsA(isA<RequestCancelled>()));
    expect(streamCancelled, isTrue);
    expect(workspace.names, isEmpty);
    await stream.close();
  });

  test(
    'native and lost-data errors expose only stable sanitized codes',
    () async {
      picker.error = PlatformException(
        code: 'unknown',
        message: 'private path and data',
      );
      await expectLater(
        media.capturePhoto(),
        throwsA(
          isA<MediaAttachmentException>().having(
            (e) => e.toString(),
            'safe error',
            'media_picker_failed',
          ),
        ),
      );
      picker.error = null;
      picker.lost = LostDataResponse(
        exception: PlatformException(
          code: 'camera_access_denied',
          details: 'private data',
        ),
      );
      await expectLater(
        media.recoverLostPhotos(),
        throwsA(
          isA<MediaAttachmentException>().having(
            (e) => e.code,
            'code',
            'access_denied',
          ),
        ),
      );
    },
  );
}

class _Workspace implements WorkspaceCapability {
  final names = <String>[];
  final bytes = <List<int>>[];

  @override
  bool get isAvailable => true;

  @override
  Future<ImageBlock> importImageBytes(
    String name,
    Uint8List data, {
    CancelToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    names.add(name);
    bytes.add(data.toList());
    return ImageBlock(
      path: 'attachments/${names.length}.jpg',
      mimeType: 'image/jpeg',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Picker extends ImagePicker {
  XFile? single;
  List<XFile> multiple = [];
  Future<List<XFile>>? pending;
  LostDataResponse lost = LostDataResponse.empty();
  PlatformException? error;
  ImageSource? source;
  int? limit;
  double? maxWidth;
  double? maxHeight;
  int? quality;
  bool? metadata;
  int multiCalls = 0;
  int lostCalls = 0;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    this.source = source;
    this.maxWidth = maxWidth;
    this.maxHeight = maxHeight;
    quality = imageQuality;
    metadata = requestFullMetadata;
    if (error != null) throw error!;
    return single;
  }

  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    multiCalls++;
    this.limit = limit;
    this.maxWidth = maxWidth;
    this.maxHeight = maxHeight;
    quality = imageQuality;
    metadata = requestFullMetadata;
    if (error != null) throw error!;
    return await (pending ?? Future.value(multiple));
  }

  @override
  Future<LostDataResponse> retrieveLostData() async {
    lostCalls++;
    return lost;
  }
}

class _File implements XFile {
  _File(this.name, this.bytes, {this.declaredLength, this.customStream});

  @override
  final String name;
  final List<int> bytes;
  final int? declaredLength;
  final Stream<Uint8List>? customStream;
  bool opened = false;

  @override
  Future<int> length() async => declaredLength ?? bytes.length;

  @override
  Stream<Uint8List> openRead([int? start, int? end]) {
    opened = true;
    return customStream ?? Stream.value(Uint8List.fromList(bytes));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
