import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/on_device/gguf.dart';

import 'gguf_fixture.dart';

Future<GgufInfo> read(Uint8List bytes, {List<int>? reads}) =>
    readGgufInfo((offset, length) async {
      reads?.add(offset);
      return Uint8List.sublistView(
        bytes,
        min(offset, bytes.length),
        min(offset + length, bytes.length),
      );
    });

void main() {
  test('reads what a chat needs and skips the vocabulary', () async {
    final info = await read(ggufBytes());
    expect(info.architecture, 'qwen35');
    expect(info.name, 'Fixture Model');
    expect(info.contextLength, 262144);
    expect(info.isProjector, isFalse);
    expect(info.supportsTools, isTrue);
    expect(info.supportsThinking, isTrue);
  });

  test('reads metadata in blocks, not the whole file', () async {
    final reads = <int>[];
    final bytes = ggufBytes(vocabulary: 20000);
    await read(bytes, reads: reads);
    expect(reads.length, lessThan(bytes.length ~/ 1024));
  });

  test('a template without tools or thinking says so', () async {
    final info = await read(ggufBytes(template: '{{ messages }}'));
    expect(info.supportsTools, isFalse);
    expect(info.supportsThinking, isFalse);
    final bare = await read(ggufBytes(template: null, context: null));
    expect(bare.supportsTools, isFalse);
    expect(bare.contextLength, isNull);
  });

  test('a vision projector is recognised', () async {
    expect((await read(projectorBytes())).isProjector, isTrue);
  });

  test('v2 files read like v3', () async {
    expect((await read(ggufBytes(version: 2))).architecture, 'qwen35');
  });

  test('anything else is refused', () async {
    for (final bytes in [
      Uint8List.fromList(utf8.encode('<!doctype html><html>')),
      Uint8List(0),
      ggufBytes(version: 1),
      Uint8List.sublistView(ggufBytes(), 0, 40),
      ggufBytes(architecture: ''),
    ]) {
      await expectLater(read(bytes), throwsFormatException);
    }
  });

  test('absurd lengths are refused before reading them', () async {
    final bytes = ggufBytes(vocabulary: 0);
    // The first key's length: make it claim 2^40 bytes.
    ByteData.sublistView(bytes).setUint64(24, 1 << 40, Endian.little);
    await expectLater(read(bytes), throwsFormatException);
  });
}
