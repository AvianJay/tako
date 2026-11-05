import 'dart:io';

import 'package:yaml/yaml.dart';

enum Registration { closed, invite, open }

/// A model service the gateway forwards to. Clients address its models as
/// `<name>/<model>`.
final class Upstream {
  const Upstream({
    required this.name,
    required this.baseUrl,
    this.apiKey,
    this.models = const [],
  });

  final String name;

  /// An OpenAI-compatible base URL that ends before `/chat/completions`.
  final String baseUrl;
  final String? apiKey;

  /// Models to offer. When empty, the upstream's own `/models` list is used.
  final List<String> models;
}

final class DenConfig {
  const DenConfig({
    this.host = '0.0.0.0',
    this.port = 8787,
    this.dataDir = 'data',
    this.publicUrl,
    this.registration = Registration.closed,
    this.upstreams = const [],
    this.adminUsername,
    this.adminPassword,
    this.trustProxy = false,
    this.publicUrlLocked = false,
    this.webDir,
    this.secretKey,
    this.oauth = const [],
  });

  final String host;
  final int port;
  final String dataDir;

  /// The address phones use, put into pairing links. Defaults to the address
  /// of the request that created the code.
  final String? publicUrl;
  final Registration registration;
  final List<Upstream> upstreams;

  /// Creates this administrator at start-up when no user exists yet.
  final String? adminUsername;
  final String? adminPassword;

  /// Take the client address from the last `X-Forwarded-For` entry, for the
  /// sign-in limits. Turn on only when every request comes through one
  /// reverse proxy you run (Caddy, nginx, Cloudflare Tunnel).
  final bool trustProxy;
  final bool publicUrlLocked;
  final String? webDir;
  final String? secretKey;
  final List<Map<String, Object?>> oauth;

  /// Reads [file] when it exists, then lets `TAKO_*` variables override it.
  /// Common provider keys (OPENAI_API_KEY, OPENROUTER_API_KEY, OLLAMA_URL) add
  /// upstreams, so a single `docker run` line needs no configuration file.
  static DenConfig load({String? file, Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final path = file ?? env['TAKO_CONFIG'] ?? 'tako-den.yaml';
    final yaml = File(path).existsSync()
        ? loadYaml(File(path).readAsStringSync())
        : null;
    final map = yaml is YamlMap ? yaml : YamlMap();

    final upstreams = <Upstream>[
      for (final item in (map['upstreams'] as YamlList?) ?? YamlList())
        if (item is YamlMap)
          Upstream(
            name: '${item['name']}',
            baseUrl: '${item['base_url']}',
            apiKey: _secret(item, env),
            models: [
              for (final m in (item['models'] as YamlList?) ?? YamlList()) '$m',
            ],
          ),
    ];
    void addFromEnv(String name, String url, String? key) {
      if (upstreams.any((u) => u.name == name)) return;
      upstreams.add(Upstream(name: name, baseUrl: url, apiKey: key));
    }

    if (env['OPENAI_API_KEY'] case final key? when key.isNotEmpty) {
      addFromEnv('openai', 'https://api.openai.com/v1', key);
    }
    if (env['OPENROUTER_API_KEY'] case final key? when key.isNotEmpty) {
      addFromEnv('openrouter', 'https://openrouter.ai/api/v1', key);
    }
    if (env['OLLAMA_URL'] case final url? when url.isNotEmpty) {
      addFromEnv('ollama', '${_trimSlash(url)}/v1', null);
    }

    return DenConfig(
      host: env['TAKO_HOST'] ?? '${map['host'] ?? '0.0.0.0'}',
      port: int.parse(env['TAKO_PORT'] ?? '${map['port'] ?? 8787}'),
      dataDir: env['TAKO_DATA'] ?? '${map['data_dir'] ?? 'data'}',
      publicUrl: env['TAKO_PUBLIC_URL'] ?? map['public_url'] as String?,
      registration: Registration.values.byName(
        env['TAKO_REGISTRATION'] ?? '${map['registration'] ?? 'closed'}',
      ),
      upstreams: upstreams,
      publicUrlLocked: env['TAKO_PUBLIC_URL'] != null,
      webDir: env['TAKO_WEB_DIR'],
      secretKey: env['TAKO_SECRET_KEY'],
      oauth: [
        for (final type in ['google', 'discord', 'github', 'oidc'])
          if (env['TAKO_OAUTH_${type.toUpperCase()}_CLIENT_ID'] case final id?
              when id.isNotEmpty)
            {
              'id': type,
              'type': type,
              'name':
                  env['TAKO_OAUTH_${type.toUpperCase()}_NAME'] ??
                  {
                    'google': 'Google',
                    'discord': 'Discord',
                    'github': 'GitHub',
                    'oidc': 'OpenID Connect',
                  }[type],
              'clientId': id,
              'clientSecret':
                  env['TAKO_OAUTH_${type.toUpperCase()}_CLIENT_SECRET'] ?? '',
              'issuer': env['TAKO_OAUTH_${type.toUpperCase()}_ISSUER'],
            },
      ],
      adminUsername: env['TAKO_ADMIN_USERNAME'] ?? 'admin',
      adminPassword: env['TAKO_ADMIN_PASSWORD'],
      trustProxy: switch (env['TAKO_TRUST_PROXY']?.toLowerCase()) {
        null => map['trust_proxy'] == true,
        final value => const {'1', 'true', 'yes'}.contains(value),
      },
    );
  }

  static String? _secret(YamlMap item, Map<String, String> env) {
    if (item['api_key_env'] case final String name) return env[name];
    return item['api_key'] as String?;
  }
}

String _trimSlash(String url) =>
    url.endsWith('/') ? url.substring(0, url.length - 1) : url;
