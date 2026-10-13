import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/providers/cancel_token.dart';
import '../../core/screen/screen_capability.dart';
import 'ictrl_crypto.dart';

typedef IctrlSecretReader = Future<String?> Function(String key);
typedef IctrlSecretWriter = Future<void> Function(String key, String? value);

class IctrlClient {
  IctrlClient({
    required this.readSecret,
    required this.writeSecret,
    http.Client? client,
    String endpoint = 'http://127.0.0.1:8200',
  }) : _client = client ?? http.Client(),
       _endpoint = validateEndpoint(endpoint);
  final IctrlSecretReader readSecret;
  final IctrlSecretWriter writeSecret;
  final http.Client _client;
  Uri _endpoint;
  Uint8List? _key;
  int _sequence = 0;
  String get endpoint => _endpoint.toString();
  String get _secretKey => 'ictrl.key.$endpoint';
  bool get hasKey => _key != null;
  static Uri validateEndpoint(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException('Use an iCTRL origin URL');
    }
    // Plain HTTP is limited to loopback, LAN and Tailscale addresses.
    final host = uri.host;
    final parts = host.split('.').map(int.tryParse).toList();
    final private =
        host == 'localhost' ||
        host == '::1' ||
        host.endsWith('.ts.net') ||
        host.endsWith('.local') ||
        parts.length == 4 &&
            parts.every((p) => p != null && p >= 0 && p <= 255) &&
            (parts[0] == 127 ||
                parts[0] == 10 ||
                parts[0] == 192 && parts[1] == 168 ||
                parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31 ||
                parts[0] == 100 && parts[1]! >= 64 && parts[1]! <= 127);
    if (uri.scheme == 'http' && !private) {
      throw const FormatException('Use HTTPS outside the local network');
    }
    return uri.replace(path: '');
  }

  Future<void> setEndpoint(String value) async {
    _endpoint = validateEndpoint(value);
    _key = null;
    await loadKey();
  }

  Future<void> loadKey() async {
    final stored = await readSecret(_secretKey);
    if (stored == null) return;
    try {
      _key = IctrlCrypto.unhex(stored, 32);
    } on FormatException {
      await forgetKey();
    }
  }

  Future<void> forgetKey() async {
    _key = null;
    await writeSecret(_secretKey, null);
  }

  Future<Map<String, Object?>> discover() async {
    final result = await _request(
      'GET',
      '/schema',
      timeout: const Duration(milliseconds: 1200),
    );
    final schema = result.body;
    if (result.status != 200 ||
        schema['protocol_version'] != 1 ||
        schema['server_version'] is! String) {
      throw const ScreenException('ictrl_incompatible');
    }
    return schema;
  }

  /// Exactly one long-lived request: never retry a pending/denied pairing.
  Future<void> pair() async {
    final loopback = {'127.0.0.1', 'localhost', '::1'}.contains(_endpoint.host);
    final algorithm = X25519();
    final keyPair = loopback ? null : await algorithm.newKeyPair();
    final public = keyPair == null ? null : await keyPair.extractPublicKey();
    final result = await _request(
      'POST',
      '/pair',
      body: {
        'client_name': 'Tako',
        if (loopback) 'plain': true else 'pub': base64Encode(public!.bytes),
      },
      timeout: const Duration(minutes: 3),
    );
    if (result.status == 403) throw const ScreenException('ictrl_pair_denied');
    if (result.status != 200) throw const ScreenException('ictrl_pair_failed');
    final Uint8List key;
    if (loopback) {
      key = IctrlCrypto.unhex(result.body['token'] as String, 32);
    } else {
      final devicePublic = base64Decode(result.body['pub'] as String);
      if (devicePublic.length != 32) {
        throw const FormatException('Invalid pairing');
      }
      final shared = await (await algorithm.sharedSecretKey(
        keyPair: keyPair!,
        remotePublicKey: SimplePublicKey(
          devicePublic,
          type: KeyPairType.x25519,
        ),
      )).extractBytes();
      final wrap = IctrlCrypto.hmac(shared, [
        ...utf8.encode('ictrl-pair'),
        ...public!.bytes,
        ...devicePublic,
      ]);
      final pad = IctrlCrypto.hmac(wrap, utf8.encode('ictrl-wrap'));
      final ct = IctrlCrypto.unhex(result.body['token_ct'] as String, 32);
      key = Uint8List.fromList(List.generate(32, (i) => ct[i] ^ pad[i]));
    }
    if (result.body['tok'] != IctrlCrypto.tokenId(key)) {
      throw const FormatException('Invalid pairing key');
    }
    await writeSecret(_secretKey, IctrlCrypto.hex(key));
    _key = key;
  }

  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> params = const {},
    CancelToken? cancel,
  ]) async {
    cancel?.throwIfCancelled();
    final key = _key;
    if (key == null) throw const ScreenException('ictrl_pair_required');
    final id = ++_sequence;
    final nonce = IctrlCrypto.randomNonce();
    final envelope = IctrlCrypto.seal(
      key,
      {'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params},
      nonce: nonce,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    final response = await _request(
      'POST',
      '/rpc',
      body: envelope,
      cancel: cancel,
      // The server may wait 15 seconds for a bounded accessibility read.
      // A longer transport deadline avoids abandoning a still-queued action.
      timeout: const Duration(seconds: 30),
    );
    if (response.status != 200) {
      final code = (response.body['error'] as Map?)?['code'];
      if (response.status == 401 && code == 'auth_failed') {
        await forgetKey();
        throw const ScreenException('ictrl_pair_required');
      }
      throw ScreenException(
        code == 'ts_skew' ? 'ictrl_clock_skew' : 'ictrl_request_failed',
      );
    }
    final decoded = response.size > 65536
        ? await compute(openIctrlResponse, {
            'key': key,
            'nonce': nonce,
            'envelope': response.body,
          })
        : IctrlCrypto.open(key, response.body, nonce);
    if (decoded['jsonrpc'] != '2.0' || decoded['id'] != id) {
      throw const FormatException('Mismatched RPC');
    }
    if (decoded['error'] != null) {
      final message = (decoded['error'] as Map?)?['message'] as String?;
      throw ScreenException(
        'ictrl_rpc_failed_read_again',
        detail: message?.substring(0, message.length.clamp(0, 1200)),
      );
    }
    return Map<String, Object?>.from(decoded['result'] as Map);
  }

  Future<({int status, Map<String, Object?> body, int size})> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    required Duration timeout,
    CancelToken? cancel,
  }) async {
    final abort = Completer<void>();
    void abortRequest() {
      if (!abort.isCompleted) abort.complete();
    }

    final request =
        http.AbortableRequest(
            method,
            _endpoint.resolve(path),
            abortTrigger: abort.future,
          )
          ..followRedirects = false
          ..headers['Content-Type'] = 'application/json';
    if (body != null) request.body = jsonEncode(body);
    cancel?.addListener(abortRequest);
    try {
      final operation = () async {
        final stream = await _client.send(request);
        final bytes = BytesBuilder();
        await for (final chunk in stream.stream) {
          bytes.add(chunk);
          if (bytes.length > 12 * 1024 * 1024) {
            throw const FormatException('iCTRL response too large');
          }
        }
        final size = bytes.length;
        return (
          status: stream.statusCode,
          body: Map<String, Object?>.from(
            jsonDecode(utf8.decode(bytes.takeBytes())) as Map,
          ),
          size: size,
        );
      }();
      return await (cancel == null ? operation : cancel.bind(operation))
          .timeout(timeout);
    } on TimeoutException {
      abortRequest();
      throw const ScreenException('ictrl_timeout_check_screen_before_retry');
    } on http.ClientException {
      cancel?.throwIfCancelled();
      throw const ScreenException('ictrl_offline');
    } finally {
      cancel?.removeListener(abortRequest);
    }
  }

  void close() => _client.close();
}
