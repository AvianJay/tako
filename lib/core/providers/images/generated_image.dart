import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../cancel_token.dart';
import '../provider_config.dart';
import '../provider_event.dart';

/// Matches the workspace attachment limit, including downloaded provider output.
const maxGeneratedImageBytes = 20 * 1024 * 1024;
const supportedGeneratedImageTypes = {'image/png', 'image/jpeg', 'image/webp'};

GeneratedImage generatedImageFromBase64(
  String base64, {
  String? mimeType,
  String? alt,
}) {
  if (base64.isEmpty ||
      base64.length > ((maxGeneratedImageBytes + 2) ~/ 3) * 4) {
    throw const ProviderError(
      'Generated image is empty or exceeds the 20 MB limit',
      code: 'invalid_image',
    );
  }
  try {
    return generatedImageFromBytes(
      base64Decode(base64),
      mimeType: mimeType,
      alt: alt,
    );
  } on FormatException {
    throw const ProviderError(
      'Provider returned invalid image data',
      code: 'invalid_image',
    );
  }
}

GeneratedImage generatedImageFromDataUrl(String url, {String? alt}) {
  final comma = url.indexOf(',');
  if (comma < 0 || comma > 64 || !url.startsWith('data:')) {
    throw const ProviderError('Invalid image data URL', code: 'invalid_image');
  }
  final header = url.substring(5, comma).toLowerCase();
  if (!header.endsWith(';base64')) {
    throw const ProviderError('Invalid image data URL', code: 'invalid_image');
  }
  return generatedImageFromBase64(
    url.substring(comma + 1),
    mimeType: header.substring(0, header.length - 7),
    alt: alt,
  );
}

GeneratedImage generatedImageFromBytes(
  List<int> bytes, {
  String? mimeType,
  String? alt,
}) {
  if (bytes.isEmpty || bytes.length > maxGeneratedImageBytes) {
    throw const ProviderError(
      'Generated image is empty or exceeds the 20 MB limit',
      code: 'invalid_image',
    );
  }
  final detected = imageMimeType(bytes);
  final declared = mimeType?.split(';').first.trim().toLowerCase();
  if (detected == null ||
      (declared != null &&
          (!supportedGeneratedImageTypes.contains(declared) ||
              declared != detected))) {
    throw const ProviderError(
      'Provider returned an unsupported or mismatched image format',
      code: 'invalid_image',
    );
  }
  return GeneratedImage(
    base64: base64Encode(bytes),
    mimeType: detected,
    alt: alt?.substring(0, alt.length > 2000 ? 2000 : alt.length),
  );
}

String? imageMimeType(List<int> bytes) {
  bool starts(List<int> signature, [int offset = 0]) =>
      bytes.length >= offset + signature.length &&
      List.generate(
        signature.length,
        (i) => i,
      ).every((i) => bytes[offset + i] == signature[i]);
  if (bytes.length >= 24 && starts([137, 80, 78, 71, 13, 10, 26, 10])) {
    return 'image/png';
  }
  if (bytes.length >= 4 && starts([255, 216, 255])) return 'image/jpeg';
  if (bytes.length >= 16 &&
      starts([82, 73, 70, 70]) &&
      starts([87, 69, 66, 80], 8)) {
    return 'image/webp';
  }
  return null;
}

/// Never follows redirects or attaches provider headers to an output image URL.
/// [client] must be a fresh client, without provider authentication middleware.
Future<GeneratedImage> downloadGeneratedImage(
  String url, {
  required http.Client client,
  required CancelToken cancel,
  String? alt,
}) async {
  final uri = generatedImageDownloadUri(url);
  final request = http.AbortableRequest(
    'GET',
    uri,
    abortTrigger: cancel.whenCancelled,
  )..followRedirects = false;
  request.headers['accept'] = 'image/png, image/jpeg, image/webp';
  final response = await cancel.bind(
    client.send(request).timeout(const Duration(seconds: 60)),
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw ProviderError(
      'Could not download the generated image',
      statusCode: response.statusCode,
      code: 'image_download',
    );
  }
  final bytes = await readImageResponseBytes(
    response,
    cancel: cancel,
    maxBytes: maxGeneratedImageBytes,
  );
  final contentType = response.headers['content-type']
      ?.split(';')
      .first
      .trim()
      .toLowerCase();
  return generatedImageFromBytes(
    bytes,
    mimeType: contentType == 'application/octet-stream' ? null : contentType,
    alt: alt,
  );
}

Uri generatedImageDownloadUri(String url) {
  final uri = Uri.tryParse(url);
  final host = uri?.host.toLowerCase() ?? '';
  final ipv4 = host.split('.').map(int.tryParse).toList();
  final nonPublicIpv4 =
      ipv4.length == 4 &&
      ipv4.every((n) => n != null) &&
      (ipv4[0] == 0 ||
          ipv4[0]! >= 224 ||
          ipv4[0] == 100 && ipv4[1]! >= 64 && ipv4[1]! <= 127 ||
          ipv4[0] == 192 && ipv4[1] == 0 ||
          ipv4[0] == 198 && (ipv4[1] == 18 || ipv4[1] == 19));
  if (uri == null ||
      url.length > 8192 ||
      url.codeUnits.any((unit) => unit <= 32 || unit == 127) ||
      uri.scheme != 'https' ||
      uri.port != 443 ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      !host.contains('.') ||
      host.contains(':') ||
      host.endsWith('.') ||
      isLocalHost(host) ||
      nonPublicIpv4) {
    throw const ProviderError(
      'Provider returned an unsafe image download URL',
      code: 'invalid_image_url',
    );
  }
  return uri;
}

/// Bounded and cancellation-aware for both JSON image responses and raw images.
Future<Uint8List> readImageResponseBytes(
  http.StreamedResponse response, {
  required CancelToken cancel,
  required int maxBytes,
  Duration idleTimeout = const Duration(seconds: 60),
}) async {
  if ((response.contentLength ?? 0) > maxBytes) {
    throw const ProviderError(
      'Image response is too large',
      code: 'invalid_image',
    );
  }
  final bytes = BytesBuilder(copy: false);
  final iterator = StreamIterator(response.stream);
  void cancelled() => unawaited(iterator.cancel());
  cancel.addListener(cancelled);
  try {
    while (await cancel.bind(iterator.moveNext().timeout(idleTimeout))) {
      if (bytes.length + iterator.current.length > maxBytes) {
        throw const ProviderError(
          'Image response is too large',
          code: 'invalid_image',
        );
      }
      bytes.add(iterator.current);
    }
    cancel.throwIfCancelled();
    return bytes.takeBytes();
  } finally {
    cancel.removeListener(cancelled);
    await iterator.cancel();
  }
}
