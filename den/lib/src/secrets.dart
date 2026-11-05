import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

String randomToken([int length = 32]) {
  final random = Random.secure();
  return base64Url
      .encode(List.generate(length, (_) => random.nextInt(256)))
      .replaceAll('=', '');
}

String digest(String value) => sha256.convert(utf8.encode(value)).toString();
String normalizeCode(String code) =>
    code.toUpperCase().replaceAll(RegExp('[- ]'), '');

/// Authenticated encryption also binds ciphertext to its purpose and row.
final class Secrets {
  Secrets(List<int> bytes) : _key = SecretKey(bytes) {
    if (bytes.length != 32) {
      throw const FormatException('A secret key must contain 32 bytes.');
    }
  }
  factory Secrets.memory() =>
      Secrets(base64Url.decode(base64Url.normalize(randomToken())));

  static Secrets load(String directory, {String? encodedKey}) {
    if (encodedKey != null) {
      try {
        return Secrets(base64.decode(encodedKey));
      } on Object {
        throw const FormatException(
          'TAKO_SECRET_KEY must be base64 encoding of 32 bytes.',
        );
      }
    }
    final file = File(p.join(directory, 'secret.key'));
    file.parent.createSync(recursive: true);
    _protect(file.parent.path, directory: true);
    final lock = File('${file.path}.lock').openSync(mode: FileMode.append);
    lock.lockSync(FileLock.blockingExclusive);
    try {
      if (!file.existsSync()) {
        file.writeAsBytesSync(
          base64Url.decode(base64Url.normalize(randomToken())),
          flush: true,
        );
      }
      _protect(file.path);
      return Secrets(file.readAsBytesSync());
    } finally {
      lock.unlockSync();
      lock.closeSync();
    }
  }

  static void _protect(String path, {bool directory = false}) {
    if (Platform.isWindows) {
      final identity = Process.runSync('whoami', [
        '/user',
        '/fo',
        'csv',
        '/nh',
      ]);
      final sid = RegExp(
        r'S-1-\d+(?:-\d+)+',
      ).firstMatch(identity.stdout.toString())?.group(0);
      if (identity.exitCode != 0 || sid == null) {
        throw StateError('Cannot determine secret key owner.');
      }
      final result = Process.runSync('icacls', [
        path,
        '/inheritance:r',
        '/grant:r',
        '*$sid:${directory ? '(OI)(CI)' : ''}(F)',
      ]);
      if (result.exitCode != 0) {
        throw StateError('Cannot protect secret key permissions.');
      }
    } else {
      final result = Process.runSync('chmod', [
        directory ? '700' : '600',
        path,
      ]);
      if (result.exitCode != 0) {
        throw StateError('Cannot protect secret key permissions.');
      }
    }
  }

  final SecretKey _key;
  final _cipher = AesGcm.with256bits();

  Future<String> encrypt(String value, String context) async {
    if (value.isEmpty) return '';
    final box = await _cipher.encrypt(
      utf8.encode(value),
      secretKey: _key,
      aad: utf8.encode(context),
    );
    return base64.encode(box.concatenation());
  }

  Future<String> decrypt(String value, String context) async {
    if (value.isEmpty) return '';
    final box = SecretBox.fromConcatenation(
      base64.decode(value),
      nonceLength: 12,
      macLength: 16,
    );
    return utf8.decode(
      await _cipher.decrypt(box, secretKey: _key, aad: utf8.encode(context)),
    );
  }
}
