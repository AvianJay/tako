import 'dart:io';

import 'package:tako_den/src/api.dart';
import 'package:tako_den/src/network_guard.dart';
import 'package:test/test.dart';

const _certificate = 'test/certificates/test-only-cert.pem';
const _key = 'test/certificates/test-only-key.pem';

// Self-signed fixtures for offline tests only, valid 2020 to 2120. The certificate
// covers localhost and upstream.test, deliberately not the loopback IP.
SecurityContext _trustedContext() =>
    SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates(_certificate);

Future<HttpServer> _server({bool secure = false}) async {
  final server = secure
      ? await HttpServer.bindSecure(
          InternetAddress.loopbackIPv4,
          0,
          SecurityContext()
            ..useCertificateChain(_certificate)
            ..usePrivateKey(_key),
        )
      : await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen(
    (request) {
      request.response.write(request.headers.value(HttpHeaders.hostHeader));
      request.response.close();
    },
    onError: (Object error) {
      // Rejected client handshakes are expected in the certificate tests.
    },
  );
  return server;
}

void main() {
  test(
    'HTTP connects to the injected address when private networks are allowed',
    () async {
      final server = await _server();
      var lookups = 0;
      final client = NetworkGuard(
        resolver: (host) async {
          expect(host, 'upstream.test');
          lookups++;
          return [InternetAddress.loopbackIPv4];
        },
      ).client(() => true);
      addTearDown(client.close);
      final response = await client.get(
        Uri.parse('http://upstream.test:${server.port}/'),
      );
      expect(response.statusCode, 200);
      expect(response.body, 'upstream.test:${server.port}');
      expect(lookups, 1);
    },
  );

  for (final bareAddress in [false, true]) {
    test(
      'HTTPS verifies the URL hostname with ${bareAddress ? 'bare' : 'lookup'} addresses',
      () async {
        final server = await _server(secure: true);
        final host = bareAddress ? 'upstream.test' : 'localhost';
        var lookups = 0;
        final client = NetworkGuard(
          securityContext: _trustedContext(),
          resolver: (name) async {
            expect(name, host);
            lookups++;
            if (bareAddress) return [InternetAddress.loopbackIPv4];
            final addresses = await InternetAddress.lookup(
              name,
              type: InternetAddressType.IPv4,
            );
            expect(addresses.first.host, host);
            return addresses;
          },
        ).client(() => true);
        addTearDown(client.close);
        final response = await client.get(
          Uri.parse('https://$host:${server.port}/'),
        );
        expect(response.statusCode, 200);
        expect(response.body, '$host:${server.port}');
        expect(lookups, 1);
      },
    );
  }

  for (final trusted in [false, true]) {
    test(
      'HTTPS rejects ${trusted ? 'a wrong hostname' : 'an untrusted certificate'}',
      () async {
        final server = await _server(secure: true);
        final client = NetworkGuard(
          securityContext: trusted
              ? _trustedContext()
              : SecurityContext(withTrustedRoots: false),
          resolver: (_) async => [InternetAddress.loopbackIPv4],
        ).client(() => true);
        addTearDown(client.close);
        final host = trusted ? 'wrong.test' : 'upstream.test';
        await expectLater(
          client.get(Uri.parse('https://$host:${server.port}/')),
          throwsA(isA<HandshakeException>()),
        );
      },
    );
  }

  for (final scheme in ['http', 'https']) {
    test('$scheme refuses private DNS answers before connecting', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      var connections = 0;
      server.listen((socket) {
        connections++;
        socket.destroy();
      });
      final client = NetworkGuard(
        resolver: (_) async => [
          InternetAddress.loopbackIPv4,
          InternetAddress('8.8.8.8'),
        ],
        securityContext: _trustedContext(),
      ).client(() => false);
      addTearDown(client.close);
      await expectLater(
        client.get(Uri.parse('$scheme://upstream.test:${server.port}/')),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'private_address'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(connections, 0);
    });
  }
}
