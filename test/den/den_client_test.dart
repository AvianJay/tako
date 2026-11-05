import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/den/den_client.dart';

void main() {
  test('server addresses get a scheme and lose an API suffix', () {
    String? normalized(String input) => normalizeDenUrl(input)?.toString();
    expect(normalized('den.example.com'), 'https://den.example.com');
    expect(normalized('192.168.1.20:8787'), 'http://192.168.1.20:8787');
    expect(normalized('localhost:8787/'), 'http://localhost:8787');
    expect(normalized('nas:8787'), 'http://nas:8787');
    expect(
      normalized('https://example.com/den/v1/?x=1#top'),
      'https://example.com/den',
    );
    expect(normalized('ftp://example.com'), isNull);
    expect(normalized('  '), isNull);
  });

  test('OAuth sign-in starts on the origin of the confirmation page', () {
    DenDeviceLogin login(String url) => DenDeviceLogin(
      deviceCode: 'device',
      userCode: 'ABCD-EFGH',
      verificationUrl: Uri.parse(url),
      expiresIn: const Duration(minutes: 10),
      interval: const Duration(seconds: 3),
    );
    expect(
      login(
        'https://den.example.com/link?code=ABCD-EFGH',
      ).oauthStart('discord').toString(),
      'https://den.example.com/v1/auth/oauth/discord/start?device=ABCD-EFGH',
    );
    expect(
      login(
        'https://example.com/den/link?code=ABCD-EFGH',
      ).oauthStart('google').toString(),
      'https://example.com/den/v1/auth/oauth/google/start?device=ABCD-EFGH',
    );
  });
}
