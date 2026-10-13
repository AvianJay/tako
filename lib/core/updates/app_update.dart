import 'dart:convert';

import 'package:http/http.dart' as http;

import '../util/json.dart';

class AppUpdate {
  const AppUpdate({
    required this.name,
    required this.notes,
    required this.url,
    required this.commit,
    required this.updatedAt,
    required this.size,
    this.digest,
  });
  final String name;
  final String notes;
  final Uri url;
  final String commit;
  final DateTime updatedAt;
  final int size;
  final String? digest;

  bool isNewerThan({
    required String installedCommit,
    required DateTime installedAt,
  }) => installedCommit.isNotEmpty && commit.isNotEmpty
      ? !installedCommit.startsWith(commit)
      : updatedAt.isAfter(installedAt);
}

class AppUpdateRepository {
  AppUpdateRepository({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;
  final http.Client Function() _clientFactory;
  static const repository = 'AvianJay/tako';
  static const architectures = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];

  Future<AppUpdate> check(List<String> supportedAbis) async {
    final abi = supportedAbis.where(architectures.contains).firstOrNull;
    if (abi == null) throw const FormatException('Unsupported architecture');
    final client = _clientFactory();
    try {
      final response = await client
          .get(
            Uri.https(
              'api.github.com',
              '/repos/$repository/releases/tags/nightly',
            ),
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'Tako-Updater',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw const FormatException('Update check failed');
      }
      final release = tryDecodeObject(utf8.decode(response.bodyBytes));
      if (release == null ||
          release['draft'] == true ||
          release['tag_name'] != 'nightly') {
        throw const FormatException('Invalid release');
      }
      final fileName = 'tako-full-$abi.apk';
      final asset = (asList(release['assets']) ?? [])
          .map(asMap)
          .where((a) => a?['name'] == fileName && a?['state'] == 'uploaded')
          .firstOrNull;
      if (asset == null) throw const FormatException('APK unavailable');
      final expected = Uri.https(
        'github.com',
        '/$repository/releases/download/nightly/$fileName',
      );
      final url = Uri.tryParse(asString(asset['browser_download_url']) ?? '');
      final size = asInt(asset['size']) ?? 0;
      final updatedAt = DateTime.tryParse(asString(asset['updated_at']) ?? '');
      if (url != expected || size <= 0 || updatedAt == null) {
        throw const FormatException('Invalid APK asset');
      }
      final notes = asString(release['body']) ?? '';
      final commit =
          RegExp(
            r'Built from ([0-9a-f]{7,40})\b',
          ).firstMatch(notes)?.group(1) ??
          '';
      final digest = asString(asset['digest']);
      if (digest != null &&
          !RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(digest)) {
        throw const FormatException('Invalid APK digest');
      }
      return AppUpdate(
        name: asString(release['name']) ?? 'Nightly',
        notes: notes,
        url: expected,
        commit: commit,
        updatedAt: updatedAt,
        size: size,
        digest: digest,
      );
    } finally {
      client.close();
    }
  }
}
