import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/updates/app_update.dart';

class AndroidAppUpdater {
  static bool get isAvailable => Platform.isAndroid && appFlavor == 'full';
  static const _channel = MethodChannel('tw.avianjay.tako/updater');

  Future<Map<Object?, Object?>> installedInfo() async {
    if (!isAvailable) throw UnsupportedError('Updater requires Android full');
    return await _channel.invokeMapMethod<Object?, Object?>('info') ?? {};
  }

  /// Returns false after opening Android's install-source permission screen.
  Future<bool> prepareInstall() async =>
      await _channel.invokeMethod<bool>('prepareInstall') ?? false;

  Future<void> downloadAndInstall(
    AppUpdate update, {
    required void Function(int received, int total) onProgress,
  }) async {
    if (!isAvailable) throw UnsupportedError('Updater requires Android full');
    final directory = Directory(
      p.join((await getTemporaryDirectory()).path, 'updates'),
    );
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, 'tako-update.apk'));
    final partial = File('${file.path}.part');
    final client = http.Client();
    IOSink? output;
    try {
      final response = await client
          .send(http.Request('GET', update.url))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw const HttpException('Download failed');
      }
      output = partial.openWrite();
      var received = 0;
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        received += chunk.length;
        if (received > update.size) {
          throw const FormatException('APK size mismatch');
        }
        output.add(chunk);
        onProgress(received, update.size);
      }
      await output.flush();
      await output.close();
      output = null;
      if (received != update.size) {
        throw const FormatException('Incomplete APK');
      }
      if (update.digest != null) {
        final digest = await sha256.bind(partial.openRead()).first;
        if ('sha256:$digest' != update.digest) {
          throw const FormatException('APK checksum mismatch');
        }
      }
      if (await file.exists()) await file.delete();
      await partial.rename(file.path);
      await _channel.invokeMethod<void>('install', {'path': file.path});
    } finally {
      client.close();
      await output?.close();
      if (await partial.exists()) await partial.delete();
    }
  }
}
