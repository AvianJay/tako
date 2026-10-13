import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// iCTRL envelope v1, as specified by upstream SecureEnvelope.swift.
/// This is its wire protocol, not a general purpose encryption API.
abstract final class IctrlCrypto {
  static Uint8List hmac(List<int> key, List<int> data) =>
      Uint8List.fromList(Hmac(sha256, key).convert(data).bytes);
  static String hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  static Uint8List unhex(String value, int length) {
    if (value.length != length * 2 ||
        !RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
      throw const FormatException('Invalid iCTRL key or envelope');
    }
    return Uint8List.fromList([
      for (var i = 0; i < value.length; i += 2)
        int.parse(value.substring(i, i + 2), radix: 16),
    ]);
  }

  static String tokenId(List<int> key) =>
      hex(sha256.convert(key).bytes.take(4).toList());
  static Uint8List randomNonce() {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
  }

  static Uint8List _derive(List<int> key, String label, List<int> nonce) =>
      hmac(key, [...utf8.encode('ictrl-v1|$label'), ...nonce]);
  static Uint8List _xor(List<int> key, List<int> nonce, List<int> data) {
    final out = Uint8List(data.length);
    for (
      var offset = 0, counter = 0;
      offset < data.length;
      offset += 32, counter++
    ) {
      final be = ByteData(4)..setUint32(0, counter);
      final block = hmac(key, [...nonce, ...be.buffer.asUint8List()]);
      for (var j = 0; j < 32 && offset + j < data.length; j++) {
        out[offset + j] = data[offset + j] ^ block[j];
      }
    }
    return out;
  }

  static Map<String, Object?> seal(
    List<int> key,
    Map<String, Object?> body, {
    required List<int> nonce,
    required int timestamp,
  }) {
    final tok = tokenId(key);
    final ct = _xor(
      _derive(key, 'enc-req', nonce),
      nonce,
      utf8.encode(jsonEncode(body)),
    );
    final ts = ByteData(8)..setUint64(0, timestamp);
    final tag = hmac(_derive(key, 'mac', nonce), [
      ...utf8.encode('v1'),
      ...unhex(tok, 4),
      ...ts.buffer.asUint8List(),
      ...nonce,
      ...ct,
    ]);
    return {
      'v': 1,
      'tok': tok,
      'ts': timestamp,
      'nonce': hex(nonce),
      'ct': base64Encode(ct),
      'tag': hex(tag),
    };
  }

  static Map<String, Object?> open(
    List<int> key,
    Map<String, Object?> envelope,
    List<int> nonce,
  ) {
    if (envelope['v'] != 1 || envelope['nonce'] != hex(nonce)) {
      throw const FormatException('Mismatched iCTRL envelope');
    }
    final ct = base64Decode(envelope['ct'] as String);
    final tag = unhex(envelope['tag'] as String, 32);
    final expected = hmac(_derive(key, 'mac', nonce), [
      ...utf8.encode('resp'),
      ...nonce,
      ...ct,
    ]);
    var difference = 0;
    for (var i = 0; i < 32; i++) {
      difference |= tag[i] ^ expected[i];
    }
    if (difference != 0) {
      throw const FormatException('Invalid iCTRL response tag');
    }
    return Map<String, Object?>.from(
      jsonDecode(utf8.decode(_xor(_derive(key, 'enc-resp', nonce), nonce, ct)))
          as Map,
    );
  }
}

/// Large screenshot envelopes are verified/decrypted off the Flutter UI isolate.
Map<String, Object?> openIctrlResponse(Map<String, Object?> input) =>
    IctrlCrypto.open(
      input['key'] as Uint8List,
      input['envelope'] as Map<String, Object?>,
      input['nonce'] as Uint8List,
    );
