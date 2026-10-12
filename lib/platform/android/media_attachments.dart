import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import '../../core/chat/content_block.dart';
import '../../core/files/workspace.dart';
import '../../core/providers/cancel_token.dart';
import '../media_attachment_capability.dart';

/// Uses the Android Photo Picker (with the system document-picker fallback on
/// older devices) and the camera app. No broad media or camera permission is
/// needed by Tako. The picker plugin supplies temporary files, not permanent
/// references to the user's photo library.
class AndroidMediaAttachments implements MediaAttachmentCapability {
  AndroidMediaAttachments(this._workspace, {ImagePicker? picker})
    : _picker = picker ?? ImagePicker() {
    final implementation = ImagePickerPlatform.instance;
    if (implementation is ImagePickerAndroid) {
      implementation.useAndroidPhotoPicker = true;
    }
  }

  final WorkspaceCapability _workspace;
  final ImagePicker _picker;
  static const _maxBytes = 20 * 1024 * 1024;
  bool _nativeOperationPending = false;

  @override
  bool get isAvailable => _workspace.isAvailable;

  @override
  Future<List<ContentBlock>> pickPhotos({
    int limit = 8,
    CancelToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    if (limit <= 0) return const [];
    final maximum = limit.clamp(1, 8);
    final files = await _native(() async {
      if (maximum == 1) {
        final file = await _pickSingle(ImageSource.gallery);
        return [?file];
      }
      return _picker.pickMultiImage(
        maxWidth: 1568,
        maxHeight: 1568,
        imageQuality: 85,
        requestFullMetadata: false,
        limit: maximum,
      );
    }, cancel);
    return _import(files, maximum, cancel);
  }

  @override
  Future<List<ContentBlock>> capturePhoto({CancelToken? cancel}) async {
    final file = await _native(() => _pickSingle(ImageSource.camera), cancel);
    return _import([?file], 1, cancel);
  }

  Future<XFile?> _pickSingle(ImageSource source) => _picker.pickImage(
    source: source,
    maxWidth: 1568,
    maxHeight: 1568,
    imageQuality: 85,
    requestFullMetadata: false,
  );

  @override
  Future<List<ContentBlock>> recoverLostPhotos({
    int limit = 8,
    CancelToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    if (limit <= 0) return const [];
    final response = await _native(_picker.retrieveLostData, cancel);
    final error = response.exception;
    if (error != null) throw MediaAttachmentException(_errorCode(error.code));
    if (response.isEmpty || response.type == RetrieveType.video) {
      return const [];
    }
    return _import(response.files ?? const [], limit.clamp(1, 8), cancel);
  }

  Future<T> _native<T>(
    Future<T> Function() operation,
    CancelToken? cancel,
  ) async {
    cancel?.throwIfCancelled();
    if (!isAvailable) throw const MediaAttachmentException('unavailable');
    if (_nativeOperationPending) {
      throw const MediaAttachmentException('already_active');
    }
    _nativeOperationPending = true;
    // Cancellation returns immediately, but a system picker cannot be closed
    // by Dart. Keep its slot occupied until Android actually returns, and
    // discard that late result instead of adding it to another conversation.
    final pending = Future<T>.sync(operation).whenComplete(() {
      _nativeOperationPending = false;
    });
    try {
      return await (cancel?.bind(pending) ?? pending);
    } on PlatformException catch (error) {
      cancel?.throwIfCancelled();
      throw MediaAttachmentException(_errorCode(error.code));
    } on MissingPluginException {
      throw const MediaAttachmentException('unavailable');
    }
  }

  Future<List<ContentBlock>> _import(
    List<XFile> files,
    int limit,
    CancelToken? cancel,
  ) async {
    final attachments = <ContentBlock>[];
    try {
      // Older system pickers can ignore the requested limit.
      for (final file in files.take(limit)) {
        cancel?.throwIfCancelled();
        final pendingLength = file.length();
        if (await (cancel?.bind(pendingLength) ?? pendingLength) > _maxBytes) {
          throw const MediaAttachmentException('image_too_large');
        }
        final bytes = await _readLimited(file, cancel);
        cancel?.throwIfCancelled();
        attachments.add(
          await _workspace.importImageBytes(file.name, bytes, cancel: cancel),
        );
      }
    } on FileSystemException {
      throw const MediaAttachmentException('media_read_failed');
    }
    cancel?.throwIfCancelled();
    return attachments;
  }

  Future<Uint8List> _readLimited(XFile file, CancelToken? cancel) async {
    final bytes = BytesBuilder(copy: false);
    final iterator = StreamIterator(file.openRead());
    try {
      while (true) {
        cancel?.throwIfCancelled();
        final next = iterator.moveNext();
        if (!await (cancel?.bind(next) ?? next)) break;
        cancel?.throwIfCancelled();
        if (bytes.length + iterator.current.length > _maxBytes) {
          throw const MediaAttachmentException('image_too_large');
        }
        bytes.add(iterator.current);
      }
      return bytes.takeBytes();
    } finally {
      await iterator.cancel();
    }
  }

  static String _errorCode(String code) => switch (code) {
    'camera_access_denied' ||
    'photo_access_denied' ||
    'camera_access_restricted' => 'access_denied',
    'already_active' => 'already_active',
    'no_available_camera' => 'camera_unavailable',
    _ => 'media_picker_failed',
  };
}
