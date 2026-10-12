import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import '../../platform/capabilities.dart';
import '../providers/cancel_token.dart';
import '../providers/provider_config.dart';
import '../util/json.dart';

enum SearchKind { searxng, tavily, brave, serper, ddgs }

extension SearchKindSettings on SearchKind {
  bool get requiresApiKey => switch (this) {
    SearchKind.tavily || SearchKind.brave || SearchKind.serper => true,
    _ => false,
  };

  // The upstream DDGS server is unauthenticated. A user-configured reverse
  // proxy may require a Bearer token, which remains optional here.
  bool get supportsApiKey => requiresApiKey || this == SearchKind.ddgs;

  bool get requiresBaseUrl =>
      this == SearchKind.searxng || this == SearchKind.ddgs;

  String get defaultBaseUrl => switch (this) {
    SearchKind.tavily => 'https://api.tavily.com',
    SearchKind.brave => 'https://api.search.brave.com',
    SearchKind.serper => 'https://google.serper.dev',
    SearchKind.searxng || SearchKind.ddgs => '',
  };
}

class SearchConfig {
  const SearchConfig({
    this.kind = SearchKind.searxng,
    this.baseUrl = '',
    this.apiKeyRef,
    this.resultCount = 5,
  });
  final SearchKind kind;
  final String baseUrl;
  final String? apiKeyRef;
  final int resultCount;
  factory SearchConfig.fromJson(JsonMap json) => SearchConfig(
    kind: SearchKind.values.firstWhere(
      (v) => v.name == json['kind'],
      orElse: () => SearchKind.searxng,
    ),
    baseUrl: asString(json['baseUrl']) ?? '',
    apiKeyRef: asString(json['apiKeyRef']),
    resultCount: (asInt(json['resultCount']) ?? 5).clamp(1, 10),
  );
  JsonMap toJson() => {
    'kind': kind.name,
    'baseUrl': baseUrl,
    'apiKeyRef': apiKeyRef,
    'resultCount': resultCount,
  };
}

class SearchResult {
  const SearchResult(this.title, this.url, this.snippet);
  final String title, url, snippet;
  JsonMap toJson() => {'title': title, 'url': url, 'snippet': snippet};
}

class SearchFailure implements Exception {
  const SearchFailure(this.code);
  final String code;
}

Uri webUri(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !{'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const SearchFailure('invalid_url');
  }
  return uri;
}

class SearchService implements Capability {
  SearchService(
    this.config, {
    required this.readSecret,
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;
  final SearchConfig config;
  final Future<String?> Function(String reference) readSecret;
  final http.Client Function() _clientFactory;
  @override
  bool get isAvailable =>
      (!config.kind.requiresBaseUrl || config.baseUrl.trim().isNotEmpty) &&
      (!config.kind.requiresApiKey ||
          (config.apiKeyRef?.trim().isNotEmpty ?? false));

  Future<List<SearchResult>> search(
    String query, {
    required CancelToken cancel,
  }) async {
    if (!isAvailable || query.trim().isEmpty) {
      throw const SearchFailure('search_not_configured');
    }
    final key = !config.kind.supportsApiKey || config.apiKeyRef == null
        ? null
        : await cancel.bind(readSecret(config.apiKeyRef!));
    if ((config.kind.requiresApiKey ||
            config.kind.supportsApiKey && config.apiKeyRef != null) &&
        (key == null || key.trim().isEmpty)) {
      throw const SearchFailure('search_not_configured');
    }
    final base = webUri(
      config.baseUrl.trim().isNotEmpty
          ? config.baseUrl
          : config.kind.defaultBaseUrl,
    );
    final resultCount = config.resultCount.clamp(1, 10);
    final root = base.path.replaceFirst(RegExp(r'/+$'), '');
    final uri = switch (config.kind) {
      SearchKind.searxng => base.replace(
        path: root.endsWith('/search') ? root : '$root/search',
        queryParameters: {'q': query, 'format': 'json'},
      ),
      SearchKind.tavily || SearchKind.serper => base.replace(
        path: root.endsWith('/search') ? root : '$root/search',
      ),
      SearchKind.brave => base.replace(
        path: root.endsWith('/web/search') ? root : '$root/res/v1/web/search',
        queryParameters: {'q': query, 'count': '$resultCount'},
      ),
      SearchKind.ddgs => base.replace(
        path: root.endsWith('/search/text') ? root : '$root/search/text',
      ),
    };
    final payload = switch (config.kind) {
      SearchKind.tavily => {
        'query': query,
        'max_results': resultCount,
        'include_answer': false,
      },
      SearchKind.serper => {'q': query, 'num': resultCount},
      SearchKind.ddgs => {'query': query, 'max_results': resultCount},
      _ => null,
    };
    final body = await boundedRequest(
      uri,
      cancel: cancel,
      clientFactory: _clientFactory,
      method: payload == null ? 'GET' : 'POST',
      headers: {
        if (config.kind == SearchKind.tavily ||
            config.kind == SearchKind.ddgs && key != null)
          'Authorization': 'Bearer $key',
        if (config.kind == SearchKind.brave) 'X-Subscription-Token': key!,
        if (config.kind == SearchKind.serper) 'X-API-KEY': key!,
      },
      body: payload == null ? null : jsonEncode(payload),
    );
    final data = tryDecodeObject(body.$1);
    final rows = switch (config.kind) {
      SearchKind.brave => asList(asMap(data?['web'])?['results']),
      SearchKind.serper => asList(data?['organic']),
      _ => asList(data?['results']),
    };
    if (rows == null) throw const SearchFailure('invalid_search_response');
    return [
      for (final value in rows.take(resultCount))
        if (asMap(value) case final item?)
          SearchResult(
            _plain(asString(item['title']) ?? ''),
            asString(
                  item[switch (config.kind) {
                    SearchKind.serper => 'link',
                    SearchKind.ddgs => 'href',
                    _ => 'url',
                  }],
                ) ??
                '',
            _plain(
              switch (config.kind) {
                    SearchKind.serper => asString(item['snippet']),
                    SearchKind.ddgs => asString(item['body']),
                    _ =>
                      asString(item['content']) ??
                          asString(item['description']),
                  } ??
                  '',
            ).substringSafe(1800),
          ),
    ];
  }
}

class PageFetcher implements Capability {
  PageFetcher({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;
  final http.Client Function() _clientFactory;
  @override
  bool get isAvailable => true;
  Future<JsonMap> fetch(
    String url, {
    required CancelToken cancel,
    int maxCharacters = 6000,
  }) async {
    if (maxCharacters < 1 || maxCharacters > 100000) {
      throw const SearchFailure('invalid_text_limit');
    }
    final uri = webUri(url);
    final response = await boundedRequest(
      uri,
      cancel: cancel,
      clientFactory: _clientFactory,
      maxRedirects: 5,
      allowedContentTypes: const {
        'text/html',
        'application/xhtml+xml',
        'text/plain',
        'application/json',
        'text/markdown',
      },
    );
    final type = response.$2.split(';').first.trim().toLowerCase();
    if (!{
      'text/html',
      'application/xhtml+xml',
      'text/plain',
      'application/json',
      'text/markdown',
    }.contains(type)) {
      throw const SearchFailure('downloads_not_supported');
    }
    var text = response.$1;
    var title = '';
    if (type.contains('html')) {
      final document = html.parse(text);
      title = document.querySelector('title')?.text ?? '';
      for (final node in document.querySelectorAll(
        'script,style,noscript,nav,header,footer,aside,form,svg',
      )) {
        node.remove();
      }
      final root =
          document.querySelector('main') ??
          document.querySelector('article') ??
          document.body;
      for (final node
          in root?.querySelectorAll(
                'p,div,br,li,h1,h2,h3,h4,h5,h6,section,article,tr,td,th,pre,blockquote',
              ) ??
              <dom.Element>[]) {
        node.append(dom.Text(' '));
      }
      text = root?.text ?? '';
    }
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return {
      'url': uri.toString(),
      'title': title.substringSafe(300),
      'text': text.substringSafe(maxCharacters),
      'truncated': text.length > maxCharacters,
    };
  }
}

String _plain(String value) => html.parseFragment(value).text ?? '';

extension _BoundedString on String {
  String substringSafe(int length) =>
      this.length <= length ? this : substring(0, length);
}

/// Redirects are never handled by the HTTP client. With [maxRedirects] == 0
/// (search APIs) a 3xx is a failure, so a search key is never forwarded. Page
/// fetches pass a positive limit: each hop is re-validated here and may not
/// move from a public host to a private-network one.
Future<(String, String)> boundedRequest(
  Uri uri, {
  required CancelToken cancel,
  required http.Client Function() clientFactory,
  String method = 'GET',
  Map<String, String> headers = const {},
  String? body,
  Set<String>? allowedContentTypes,
  int maxRedirects = 0,
}) async {
  cancel.throwIfCancelled();
  final client = clientFactory();
  cancel.addListener(client.close);
  try {
    var target = uri;
    late http.StreamedResponse response;
    for (var hop = 0; ; hop++) {
      final request =
          http.AbortableRequest(
              method,
              target,
              abortTrigger: cancel.whenCancelled,
            )
            ..followRedirects = false
            ..headers.addAll({
              'Accept': 'application/json, text/html, text/plain',
              ...headers,
            });
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = body;
      }
      response = await cancel.bind(
        client.send(request).timeout(const Duration(seconds: 25)),
      );
      final location = response.headers['location'];
      if (response.statusCode ~/ 100 != 3 ||
          response.statusCode == 304 ||
          maxRedirects == 0 ||
          location == null) {
        break;
      }
      await response.stream.drain<void>();
      if (hop >= maxRedirects) throw const SearchFailure('too_many_redirects');
      final next = target.resolve(location);
      if (!{'http', 'https'}.contains(next.scheme) ||
          next.host.isEmpty ||
          next.userInfo.isNotEmpty) {
        throw const SearchFailure('invalid_redirect');
      }
      if (isPrivateWebUrl(next.toString()) &&
          !isPrivateWebUrl(uri.toString())) {
        throw const SearchFailure('redirect_to_private');
      }
      target = next;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SearchFailure('http_${response.statusCode}');
    }
    final contentType = response.headers['content-type'] ?? '';
    if (RegExp(
          r'^\s*attachment(?:\s*;|\s*$)',
          caseSensitive: false,
        ).hasMatch(response.headers['content-disposition'] ?? '') ||
        allowedContentTypes != null &&
            !allowedContentTypes.contains(
              contentType.split(';').first.trim().toLowerCase(),
            )) {
      throw const SearchFailure('downloads_not_supported');
    }
    final bytes = <int>[];
    final text = await _readBody(response, bytes, cancel);
    return (text, contentType);
  } on RequestCancelled {
    rethrow;
  } on SearchFailure {
    rethrow;
  } catch (_) {
    cancel.throwIfCancelled();
    throw const SearchFailure('network_error');
  } finally {
    cancel.removeListener(client.close);
    client.close();
  }
}

Future<String> _readBody(
  http.StreamedResponse response,
  List<int> bytes,
  CancelToken cancel,
) async {
  final reader = StreamIterator(
    response.stream.timeout(const Duration(seconds: 25)),
  );
  try {
    while (await cancel.bind(reader.moveNext())) {
      final chunk = reader.current;
      if (bytes.length + chunk.length > 2 * 1024 * 1024) {
        throw const SearchFailure('response_too_large');
      }
      bytes.addAll(chunk);
    }
  } finally {
    await reader.cancel();
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// Conservative permission classification, not a DNS/IP isolation boundary.
/// Compact numeric hosts and local naming conventions must never silently gain
/// the public-web `safe` policy merely because they are not dotted RFC1918 IPs.
bool isPrivateWebUrl(String url) {
  final host = webUri(url).host
      .toLowerCase()
      .replaceAll(RegExp(r'^\[|\]$'), '')
      .replaceFirst(RegExp(r'\.+$'), '');
  if (host.isEmpty || host.contains('%') || isLocalHost(host)) return true;
  if (host.contains(':')) {
    try {
      final bytes = Uri.parseIPv6Address(host);
      // Global unicast is 2000::/3; unspecified, mapped IPv4, multicast,
      // link-local, unique-local and scoped addresses require approval.
      return bytes[0] & 0xe0 != 0x20 ||
          bytes[0] == 0x20 &&
              bytes[1] == 0x01 &&
              bytes[2] == 0x0d &&
              bytes[3] == 0xb8;
    } on FormatException {
      return true;
    }
  }
  if (!host.contains('.') ||
      const [
        '.localhost',
        '.local',
        '.internal',
        '.lan',
        '.home',
        '.home.arpa',
        '.test',
        '.invalid',
        '.example',
      ].any(host.endsWith)) {
    return true;
  }
  final labels = host.split('.');
  if (!labels.every(
    (part) => RegExp(r'^(?:[0-9]+|0x[0-9a-f]+)$').hasMatch(part),
  )) {
    return false;
  }
  // Operating systems may interpret one-to-three-part, octal, or hexadecimal
  // IPv4 spellings differently. Treat all such spellings as sensitive.
  if (labels.length != 4 ||
      labels.any((part) => part.length > 1 && part.startsWith('0'))) {
    return true;
  }
  final bytes = labels.map(int.tryParse).toList();
  if (bytes.any((part) => part == null || part > 255)) return true;
  final a = bytes[0]!, b = bytes[1]!, c = bytes[2]!;
  return a == 0 ||
      a >= 224 ||
      a == 100 && b >= 64 && b <= 127 ||
      a == 192 && b == 0 && (c == 0 || c == 2) ||
      a == 198 && (b == 18 || b == 19 || b == 51 && c == 100) ||
      a == 203 && b == 0 && c == 113;
}
