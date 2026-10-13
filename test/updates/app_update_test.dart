import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tako/core/updates/app_update.dart';

Map<String, Object?> _release({
  String abi = 'arm64-v8a',
  String? url,
  String? digest,
  String state = 'uploaded',
}) => {
  'tag_name': 'nightly',
  'name': 'Nightly (0.5.0+12)',
  'body': 'Built from abc1234 on 2026-10-13, version 0.5.0+12.',
  'assets': [
    {
      'name': 'tako-full-$abi.apk',
      'state': state,
      'size': 1234,
      'updated_at': '2026-10-13T00:00:00Z',
      'browser_download_url':
          url ??
          'https://github.com/AvianJay/tako/releases/download/nightly/tako-full-$abi.apk',
      'digest': ?digest,
    },
  ],
};

AppUpdateRepository _repository(Map<String, Object?> release) =>
    AppUpdateRepository(
      clientFactory: () => MockClient((request) async {
        expect(
          request.url.toString(),
          'https://api.github.com/repos/AvianJay/tako/releases/tags/nightly',
        );
        return http.Response(jsonEncode(release), 200);
      }),
    );

void main() {
  for (final abi in AppUpdateRepository.architectures) {
    test('selects the full APK for $abi', () async {
      final update = await _repository(_release(abi: abi)).check([abi]);
      expect(update.url.path, endsWith('/tako-full-$abi.apk'));
      expect(update.commit, 'abc1234');
      expect(update.size, 1234);
    });
  }
  test(
    'same version nightlies compare embedded commit, not install time',
    () async {
      final update = await _repository(_release()).check(['arm64-v8a']);
      expect(
        update.isNewerThan(
          installedCommit: 'abc1234${'0' * 33}',
          installedAt: DateTime.utc(2020),
        ),
        isFalse,
      );
      expect(
        update.isNewerThan(
          installedCommit: 'def1234${'0' * 33}',
          installedAt: DateTime.utc(2030),
        ),
        isTrue,
      );
      expect(
        update.isNewerThan(
          installedCommit: '',
          installedAt: DateTime.utc(2030),
        ),
        isFalse,
      );
    },
  );
  test(
    'rejects missing architecture, unfinished upload and untrusted URLs',
    () async {
      for (final release in [
        _release(abi: 'x86_64'),
        _release(state: 'new'),
        _release(url: 'https://evil.invalid/tako-full-arm64-v8a.apk'),
        _release(
          url:
              'https://github.com/AvianJay/tako/releases/download/nightly/tako-play-arm64-v8a.apk',
        ),
        _release(digest: 'sha256:invalid'),
      ]) {
        await expectLater(
          _repository(release).check(['arm64-v8a']),
          throwsFormatException,
        );
      }
    },
  );
  test('accepts GitHub sha256 asset digest', () async {
    final digest = 'sha256:${'a' * 64}';
    expect(
      (await _repository(_release(digest: digest)).check(['arm64-v8a'])).digest,
      digest,
    );
  });
}
