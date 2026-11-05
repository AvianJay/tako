import 'dart:io';

import 'package:http/io_client.dart';

import 'api.dart';

typedef HostResolver = Future<List<InternetAddress>> Function(String host);

bool privateAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (b.length == 4) {
    return b[0] == 0 ||
        b[0] == 10 ||
        b[0] == 127 ||
        b[0] >= 224 ||
        (b[0] == 169 && b[1] == 254) ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168) ||
        (b[0] == 100 && b[1] >= 64 && b[1] <= 127);
  }
  if (b.take(10).every((v) => v == 0) && b[10] == 255 && b[11] == 255) {
    return privateAddress(InternetAddress.fromRawAddress(b.sublist(12)));
  }
  // IPv4-compatible, NAT64, 6to4 and Teredo can tunnel to forbidden IPv4 networks.
  return b.take(12).every((v) => v == 0) ||
      (b[0] & 0xfe) == 0xfc ||
      (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) ||
      b[0] == 0xff ||
      (b[0] == 0 && b[1] == 0x64) ||
      (b[0] == 0x20 && b[1] == 0x02) ||
      (b[0] == 0x20 && b[1] == 0x01 && b[2] == 0 && b[3] == 0) ||
      (b[0] == 0xfe && (b[1] & 0xc0) == 0xc0);
}

final class NetworkGuard {
  NetworkGuard({HostResolver? resolver, this.securityContext})
    : resolver = resolver ?? InternetAddress.lookup;
  final HostResolver resolver;
  final SecurityContext? securityContext;

  void literal(Uri uri) {
    final address = InternetAddress.tryParse(
      uri.host.replaceAll(RegExp(r'[\[\]]'), ''),
    );
    if (address != null && privateAddress(address)) {
      fail(400, 'private_address');
    }
  }

  Future<List<InternetAddress>> resolve(Uri uri) async {
    final addresses = await _lookup(uri);
    if (addresses.isEmpty || addresses.any(privateAddress)) {
      fail(400, 'private_address');
    }
    return addresses;
  }

  Future<List<InternetAddress>> _lookup(Uri uri) async {
    final host = uri.host.replaceAll(RegExp(r'[\[\]]'), '');
    final literal = InternetAddress.tryParse(host);
    return literal == null ? await resolver(host) : [literal];
  }

  /// Connect to the validated IP, retaining the original host for TLS and HTTP.
  IOClient client(bool Function() allowPrivate) {
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      final addresses = allowPrivate()
          ? await _lookup(uri)
          : await resolve(uri);
      final address = addresses.first;
      final host = uri.host.replaceAll(RegExp(r'[\[\]]'), '');
      if (uri.scheme == 'https') {
        // lookup retains the hostname, which TLS uses for SNI and verification.
        if (address.host == host) {
          return SecureSocket.startConnect(
            address,
            uri.port,
            context: securityContext,
          );
        }
        // Injected resolvers may return bare addresses. Supply the URL host
        // explicitly without resolving again or changing the checked address.
        final task = await Socket.startConnect(address, uri.port);
        return ConnectionTask.fromSocket(
          task.socket.then(
            (socket) => SecureSocket.secure(
              socket,
              host: host,
              context: securityContext,
            ),
          ),
          task.cancel,
        );
      }
      return Socket.startConnect(address, uri.port);
    };
    return IOClient(client);
  }
}
