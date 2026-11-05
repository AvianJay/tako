import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:test/test.dart';

import '../tool/embed_web.dart';

void main() {
  test('embedded web assets match every file in web/', () {
    expect(
      sha256
          .convert(File('lib/src/web_assets.g.dart').readAsBytesSync())
          .toString(),
      sha256.convert(utf8.encode(generateWebAssets())).toString(),
      reason: 'Run dart run tool/embed_web.dart after web/ changes.',
    );
  });
}
