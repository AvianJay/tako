import '../core/chat/content_block.dart';
import '../core/providers/cancel_token.dart';
import 'capabilities.dart';

/// User-initiated image selection. Selected content is copied into the
/// workspace before it is returned; temporary picker paths never reach chat.
abstract interface class MediaAttachmentCapability implements Capability {
  Future<List<ContentBlock>> pickPhotos({int limit = 8, CancelToken? cancel});
  Future<List<ContentBlock>> capturePhoto({CancelToken? cancel});
  Future<List<ContentBlock>> recoverLostPhotos({
    int limit = 8,
    CancelToken? cancel,
  });
}

class MediaAttachmentException implements Exception {
  const MediaAttachmentException(this.code);
  final String code;

  @override
  String toString() => code;
}

class UnavailableMediaAttachments implements MediaAttachmentCapability {
  const UnavailableMediaAttachments();

  @override
  bool get isAvailable => false;

  @override
  Future<List<ContentBlock>> pickPhotos({
    int limit = 8,
    CancelToken? cancel,
  }) async => throw const MediaAttachmentException('unavailable');

  @override
  Future<List<ContentBlock>> capturePhoto({CancelToken? cancel}) async =>
      throw const MediaAttachmentException('unavailable');

  @override
  Future<List<ContentBlock>> recoverLostPhotos({
    int limit = 8,
    CancelToken? cancel,
  }) async => const [];
}
