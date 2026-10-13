import 'dart:convert';

import '../files/workspace.dart';
import '../providers/cancel_token.dart';
import '../providers/provider_event.dart';
import 'content_block.dart';

/// Store the original output bytes, rather than a resized vision thumbnail.
/// Only the workspace path is subsequently serialized into chat history.
Future<ImageBlock> storeGeneratedImage(
  WorkspaceCapability workspace,
  GeneratedImage image, {
  required CancelToken cancel,
}) async {
  cancel.throwIfCancelled();
  final extension = switch (image.mimeType) {
    'image/png' => 'png',
    'image/jpeg' => 'jpg',
    'image/webp' => 'webp',
    _ => throw const FormatException('Unsupported generated image format'),
  };
  if (image.base64.length > 28 * 1024 * 1024) {
    throw const FormatException('Generated image exceeds size limit');
  }
  final bytes = base64Decode(image.base64);
  if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
    throw const FormatException('Invalid generated image size');
  }
  final block = await workspace.importBytes(
    'generated.$extension',
    bytes,
    cancel: cancel,
  );
  if (block is! ImageBlock) {
    throw const FormatException('Could not store generated image');
  }
  return ImageBlock(
    path: block.path,
    mimeType: block.mimeType,
    alt: image.alt ?? 'Generated image',
  );
}
