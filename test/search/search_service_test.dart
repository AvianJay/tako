import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tako/core/providers/cancel_token.dart';
import 'package:tako/core/search/search_service.dart';

void main() {
  test('non-public host spellings require sensitive permission', () {
    for (final host in [
      'localhost',
      'localhost.',
      'printer',
      'router.lan',
      'nas.home.arpa',
      'metadata.google.internal',
      '169.254.169.254',
      '10.2.3.4',
      '192.168.1.2',
      '172.20.1.2',
      '127.0.0.1',
      '127.1',
      '2130706433',
      '0x7f000001',
      '0x7f.0.0.1',
      '0177.0.0.1',
      '127.0.0.1.',
      '0.0.0.0',
      '100.64.0.1',
      '198.18.0.1',
      '192.0.2.1',
      '224.0.0.1',
      '[::]',
      '[::1]',
      '[::ffff:127.0.0.1]',
      '[::ffff:7f00:1]',
      '[fd12::1]',
      '[fe90::1]',
      '[ff02::1]',
      '[2001:db8::1]',
    ]) {
      expect(isPrivateWebUrl('http://$host/path'), isTrue, reason: host);
    }
    for (final host in [
      'example.com',
      'flutter.dev',
      '8.8.8.8',
      '1.1.1.1',
      '[2606:4700:4700::1111]',
    ]) {
      expect(isPrivateWebUrl('https://$host/path'), isFalse, reason: host);
    }
  });

  test(
    'SearXNG uses GET, instance subpath, JSON format, and strips result markup',
    () async {
      final client = _Client((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/instance/search');
        expect(request.url.queryParameters, {
          'q': '台灣 & Dart',
          'format': 'json',
        });
        expect(request.followRedirects, isFalse);
        return _response(
          jsonEncode({
            'results': [
              {
                'title': '<b>Tako &amp; Dart</b>',
                'url': 'https://example.test/one',
                'content': '<p>中文 snippet</p>',
              },
              {
                'title': 'Second',
                'url': 'https://example.test/two',
                'content': 'ignored',
              },
            ],
          }),
        );
      });
      final service = SearchService(
        const SearchConfig(
          baseUrl: 'https://search.test/instance/',
          resultCount: 1,
        ),
        readSecret: (_) async => throw StateError('no secret needed'),
        clientFactory: () => client,
      );
      final results = await service.search('台灣 & Dart', cancel: CancelToken());
      expect(results.single.title, 'Tako & Dart');
      expect(results.single.snippet, '中文 snippet');
      expect(results.single.url, 'https://example.test/one');
      expect(client.closed, isTrue);
    },
  );

  test(
    'Tavily uses POST and Bearer auth without putting its key in JSON or URL',
    () async {
      const secret = 'test-only-tavily-key';
      final client = _Client((request) async {
        expect(request.url.toString(), 'https://api.tavily.com/search');
        expect(request.method, 'POST');
        expect(request.headers['Authorization'], 'Bearer $secret');
        final body = await request.finalize().bytesToString();
        expect(body, isNot(contains(secret)));
        expect(jsonDecode(body), {
          'query': 'Dart',
          'max_results': 5,
          'include_answer': false,
        });
        return _response(
          '{"results":[{"title":"Answer","url":"https://example.test","content":"Found it"}]}',
        );
      });
      final service = SearchService(
        const SearchConfig(kind: SearchKind.tavily, apiKeyRef: 'secret-ref'),
        readSecret: (ref) async {
          expect(ref, 'secret-ref');
          return secret;
        },
        clientFactory: () => client,
      );
      expect(
        (await service.search('Dart', cancel: CancelToken())).single.snippet,
        'Found it',
      );
    },
  );

  test(
    'Brave uses its subscription header and web.results response shape',
    () async {
      final client = _Client((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/res/v1/web/search');
        expect(request.url.queryParameters, {'q': 'Flutter', 'count': '3'});
        expect(request.headers['X-Subscription-Token'], 'test-only-brave-key');
        return _response(
          '{"web":{"results":[{"title":"Flutter","url":"https://flutter.dev","description":"<b>Build</b> apps"}]}}',
        );
      });
      final service = SearchService(
        const SearchConfig(
          kind: SearchKind.brave,
          apiKeyRef: 'brave',
          resultCount: 3,
        ),
        readSecret: (_) async => 'test-only-brave-key',
        clientFactory: () => client,
      );
      expect(
        (await service.search('Flutter', cancel: CancelToken())).single.snippet,
        'Build apps',
      );
    },
  );

  test(
    'Serper posts q and num with a header key and maps organic results',
    () async {
      const secret = 'test-only-serper-key';
      final client = _Client((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(), 'https://google.serper.dev/search');
        expect(request.headers['X-API-KEY'], secret);
        expect(request.headers.containsKey('Authorization'), isFalse);
        expect(request.headers['Content-Type'], 'application/json');
        expect(request.followRedirects, isFalse);
        final body = await request.finalize().bytesToString();
        expect(body, isNot(contains(secret)));
        expect(jsonDecode(body), {'q': 'Flutter & Dart', 'num': 1});
        return _response(
          jsonEncode({
            'organic': [
              {
                'title': '<b>Flutter &amp; Dart</b>',
                'link': 'https://flutter.dev',
                'snippet': '<b>Build</b> apps',
              },
              {
                'title': 'Second',
                'link': 'https://dart.dev',
                'snippet': 'Ignored beyond requested count',
              },
            ],
          }),
        );
      });
      final service = SearchService(
        const SearchConfig(
          kind: SearchKind.serper,
          apiKeyRef: 'serper-ref',
          resultCount: 1,
        ),
        readSecret: (reference) async {
          expect(reference, 'serper-ref');
          return secret;
        },
        clientFactory: () => client,
      );
      expect(
        (await service.search(
          'Flutter & Dart',
          cancel: CancelToken(),
        )).single.toJson(),
        {
          'title': 'Flutter & Dart',
          'url': 'https://flutter.dev',
          'snippet': 'Build apps',
        },
      );
      expect(client.closed, isTrue);
    },
  );

  test('DDGS posts to a configured server without needing a secret', () async {
    final client = _Client((request) async {
      expect(request.method, 'POST');
      expect(request.url.toString(), 'http://localhost:4479/search/text');
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(request.headers.containsKey('X-API-KEY'), isFalse);
      expect(jsonDecode(await request.finalize().bytesToString()), {
        'query': 'Flutter & Dart',
        'max_results': 3,
      });
      return _response(
        '{"results":[{"title":"<b>Dart</b>","href":"https://dart.dev",'
        '"body":"<p>Fast &amp; portable</p>"}]}',
      );
    });
    final service = SearchService(
      const SearchConfig(
        kind: SearchKind.ddgs,
        baseUrl: 'http://localhost:4479/',
        resultCount: 3,
      ),
      readSecret: (_) async => throw StateError('no secret needed'),
      clientFactory: () => client,
    );
    expect(service.isAvailable, isTrue);
    expect(
      (await service.search(
        'Flutter & Dart',
        cancel: CancelToken(),
      )).single.toJson(),
      {
        'title': 'Dart',
        'url': 'https://dart.dev',
        'snippet': 'Fast & portable',
      },
    );
  });

  test('DDGS only sends a Bearer token when configured', () async {
    const secret = 'test-only-proxy-key';
    final client = _Client((request) async {
      expect(request.headers['Authorization'], 'Bearer $secret');
      expect(request.url.toString(), isNot(contains(secret)));
      expect(await request.finalize().bytesToString(), isNot(contains(secret)));
      return _response('{"results":[]}');
    });
    final service = SearchService(
      const SearchConfig(
        kind: SearchKind.ddgs,
        baseUrl: 'https://search.test/ddgs',
        apiKeyRef: 'ddgs-ref',
      ),
      readSecret: (reference) async {
        expect(reference, 'ddgs-ref');
        return secret;
      },
      clientFactory: () => client,
    );
    expect(await service.search('query', cancel: CancelToken()), isEmpty);
  });

  test(
    'new provider endpoints keep subpaths and do not duplicate suffixes',
    () async {
      for (final (kind, endpoint, response) in [
        (SearchKind.serper, '/search', '{"organic":[]}'),
        (SearchKind.ddgs, '/search/text', '{"results":[]}'),
      ]) {
        for (final suffix in ['', '/', endpoint, '$endpoint/']) {
          final client = _Client((request) async {
            expect(request.url.path, '/proxy$endpoint');
            return _response(response);
          });
          final service = SearchService(
            SearchConfig(
              kind: kind,
              baseUrl: 'https://search.test/proxy$suffix',
              apiKeyRef: kind.requiresApiKey ? 'provider-ref' : null,
            ),
            readSecret: (_) async => 'test-only-key',
            clientFactory: () => client,
          );
          expect(await service.search('query', cancel: CancelToken()), isEmpty);
        }
      }
    },
  );

  test('Serper and DDGS reject malformed response containers', () async {
    for (final kind in [SearchKind.serper, SearchKind.ddgs]) {
      final container = kind == SearchKind.serper ? 'organic' : 'results';
      for (final response in [
        'not JSON',
        '[]',
        '{}',
        '{"$container":null}',
        '{"$container":{}}',
      ]) {
        final service = SearchService(
          SearchConfig(
            kind: kind,
            baseUrl: 'https://search.test',
            apiKeyRef: kind.requiresApiKey ? 'provider-ref' : null,
          ),
          readSecret: (_) async => 'test-only-key',
          clientFactory: () => _Client((_) async => _response(response)),
        );
        await expectLater(
          service.search('query', cancel: CancelToken()),
          throwsA(
            isA<SearchFailure>().having(
              (error) => error.code,
              'code',
              'invalid_search_response',
            ),
          ),
        );
      }
    }
  });

  test('Serper and DDGS clamp requested count and bound snippets', () async {
    for (final kind in [SearchKind.serper, SearchKind.ddgs]) {
      final service = SearchService(
        SearchConfig(
          kind: kind,
          baseUrl: 'https://search.test',
          apiKeyRef: kind.requiresApiKey ? 'provider-ref' : null,
          resultCount: 100,
        ),
        readSecret: (_) async => 'test-only-key',
        clientFactory: () => _Client((request) async {
          final payload =
              jsonDecode(await request.finalize().bytesToString())
                  as Map<String, dynamic>;
          expect(
            payload[kind == SearchKind.serper ? 'num' : 'max_results'],
            10,
          );
          return _response(
            jsonEncode({
              kind == SearchKind.serper ? 'organic' : 'results': [
                for (var index = 0; index < 12; index++)
                  {
                    'title': 'Result $index',
                    kind == SearchKind.serper ? 'link' : 'href':
                        'https://example.test/$index',
                    kind == SearchKind.serper ? 'snippet' : 'body': 'x' * 2000,
                  },
              ],
            }),
          );
        }),
      );
      final results = await service.search('query', cancel: CancelToken());
      expect(results, hasLength(10));
      expect(results.last.snippet, hasLength(1800));
    }
  });

  test('new providers round-trip config without storing secret values', () {
    for (final kind in [SearchKind.serper, SearchKind.ddgs]) {
      final config = SearchConfig(
        kind: kind,
        baseUrl: 'https://search.test',
        apiKeyRef: 'search.${kind.name}.key',
        resultCount: 7,
      );
      expect(SearchConfig.fromJson(config.toJson()).toJson(), config.toJson());
    }
  });

  test(
    'provider availability requires only the fields each provider needs',
    () {
      for (final kind in SearchKind.values) {
        SearchService service({String baseUrl = '', String? reference}) =>
            SearchService(
              SearchConfig(kind: kind, baseUrl: baseUrl, apiKeyRef: reference),
              readSecret: (_) async => null,
            );
        expect(service().isAvailable, isFalse);
        expect(
          service(baseUrl: 'https://search.test').isAvailable,
          !kind.requiresApiKey,
        );
        expect(
          service(reference: 'key-ref').isAvailable,
          !kind.requiresBaseUrl,
        );
        expect(service(baseUrl: ' ', reference: ' ').isAvailable, isFalse);
        expect(
          service(
            baseUrl: 'https://search.test',
            reference: 'key-ref',
          ).isAvailable,
          isTrue,
        );
      }
    },
  );

  test(
    'missing configured credentials fail before allocating transport',
    () async {
      for (final kind in [SearchKind.serper, SearchKind.ddgs]) {
        for (final secret in [null, '', ' ']) {
          final service = SearchService(
            SearchConfig(
              kind: kind,
              baseUrl: 'https://search.test',
              apiKeyRef: 'provider-ref',
            ),
            readSecret: (_) async => secret,
            clientFactory: () => throw StateError('should not create client'),
          );
          await expectLater(
            service.search('query', cancel: CancelToken()),
            throwsA(
              isA<SearchFailure>().having(
                (error) => error.code,
                'code',
                'search_not_configured',
              ),
            ),
          );
        }
      }
    },
  );

  test(
    'cancelling Serper while loading its key never sends a request',
    () async {
      final secret = Completer<String?>();
      final started = Completer<void>();
      final token = CancelToken();
      final service = SearchService(
        const SearchConfig(kind: SearchKind.serper, apiKeyRef: 'serper-ref'),
        readSecret: (_) {
          started.complete();
          return secret.future;
        },
        clientFactory: () => throw StateError('should not create client'),
      );
      final expectation = expectLater(
        service.search('query', cancel: token),
        throwsA(isA<RequestCancelled>()),
      );
      await started.future;
      token.cancel();
      await expectation.timeout(const Duration(seconds: 2));
      secret.complete('test-only-key');
    },
  );

  test('cancellation before sending does not allocate a transport', () async {
    var created = false;
    final token = CancelToken()..cancel();
    await expectLater(
      boundedRequest(
        Uri.parse('https://example.test'),
        cancel: token,
        clientFactory: () {
          created = true;
          return _Client((_) async => _response('{}'));
        },
      ),
      throwsA(isA<RequestCancelled>()),
    );
    expect(created, isFalse);
  });

  test(
    'cancellation before headers closes client and stops promptly',
    () async {
      final started = Completer<void>();
      final headers = Completer<http.StreamedResponse>();
      final client = _Client((_) {
        started.complete();
        return headers.future;
      });
      final token = CancelToken();
      final request = boundedRequest(
        Uri.parse('https://example.test'),
        cancel: token,
        clientFactory: () => client,
      );
      final expectation = expectLater(
        request,
        throwsA(isA<RequestCancelled>()),
      );
      await started.future;
      token.cancel();
      await expectation.timeout(const Duration(seconds: 2));
      expect(client.closed, isTrue);
      headers.complete(_response('{}'));
    },
  );

  test(
    'cancellation of an idle response body cancels its subscription',
    () async {
      final subscribed = Completer<void>();
      var subscriptionCancelled = false;
      final controller = StreamController<List<int>>(
        onListen: subscribed.complete,
        onCancel: () {
          subscriptionCancelled = true;
        },
      );
      final client = _Client(
        (_) async => http.StreamedResponse(controller.stream, 200),
      );
      final token = CancelToken();
      final request = boundedRequest(
        Uri.parse('https://example.test'),
        cancel: token,
        clientFactory: () => client,
      );
      final expectation = expectLater(
        request,
        throwsA(isA<RequestCancelled>()),
      );
      await subscribed.future;
      token.cancel();
      await expectation.timeout(const Duration(seconds: 2));
      expect(subscriptionCancelled, isTrue);
      expect(client.closed, isTrue);
      await controller.close();
    },
  );

  test(
    'provider and transport errors never echo API keys or response bodies',
    () async {
      const secret = 'test-only-do-not-echo';
      for (final kind in SearchKind.values) {
        for (final transportFailure in [false, true]) {
          final client = _Client((_) async {
            if (transportFailure) {
              throw StateError('connection failed: $secret');
            }
            return _response('{"error":"$secret"}', status: 401);
          });
          final service = SearchService(
            SearchConfig(
              kind: kind,
              baseUrl: 'https://search.test',
              apiKeyRef: 'provider-ref',
            ),
            readSecret: (_) async => secret,
            clientFactory: () => client,
          );
          await expectLater(
            service.search('query', cancel: CancelToken()),
            throwsA(
              isA<SearchFailure>()
                  .having(
                    (error) => error.code,
                    'code',
                    transportFailure ? 'network_error' : 'http_401',
                  )
                  .having(
                    (error) => '${error.code} $error',
                    'safe error',
                    isNot(contains(secret)),
                  ),
            ),
          );
          expect(client.closed, isTrue);
        }
      }
    },
  );

  test(
    'bounded responses stop above 2 MiB and preserve split UTF-8 below limit',
    () async {
      final large = _Client(
        (_) async => http.StreamedResponse(
          Stream.value(Uint8List(2 * 1024 * 1024 + 1)),
          200,
        ),
      );
      await expectLater(
        boundedRequest(
          Uri.parse('https://example.test'),
          cancel: CancelToken(),
          clientFactory: () => large,
        ),
        throwsA(
          isA<SearchFailure>().having(
            (error) => error.code,
            'code',
            'response_too_large',
          ),
        ),
      );
      expect(large.closed, isTrue);
      final bytes = utf8.encode('台灣 Flutter');
      final split = _Client(
        (_) async => http.StreamedResponse(
          Stream.fromIterable([bytes.sublist(0, 2), bytes.sublist(2)]),
          200,
        ),
      );
      expect(
        (await boundedRequest(
          Uri.parse('https://example.test'),
          cancel: CancelToken(),
          clientFactory: () => split,
        )).$1,
        '台灣 Flutter',
      );
    },
  );

  test(
    'fetch selects main content, removes active/navigation content and separates paragraphs',
    () async {
      final client = _Client(
        (_) async => _response(
          '<html><head><title>Tako &amp; Flutter</title><style>bad-style</style></head>'
          '<body><nav>bad-navigation</nav><header>bad-header</header><main><h1>Headline</h1>'
          '<p>First paragraph.</p><p>Second paragraph.</p><script>bad-script</script><form>bad-form</form></main>'
          '<aside>bad-aside</aside><footer>bad-footer</footer></body></html>',
          mime: 'text/html; charset=utf-8',
        ),
      );
      final result = await PageFetcher(
        clientFactory: () => client,
      ).fetch('https://example.test/page', cancel: CancelToken());
      expect(result['title'], 'Tako & Flutter');
      expect(result['text'], 'Headline First paragraph. Second paragraph.');
      expect(result['text'], isNot(contains('bad-')));
      expect(result['truncated'], isFalse);
    },
  );

  test('fetch truncates plain text with an explicit indicator', () async {
    final fetcher = PageFetcher(
      clientFactory: () => _Client(
        (_) async => _response('  one\n two  three ', mime: 'text/plain'),
      ),
    );
    final result = await fetcher.fetch(
      'https://example.test',
      cancel: CancelToken(),
      maxCharacters: 7,
    );
    expect(result['text'], 'one two');
    expect(result['truncated'], isTrue);
  });

  test(
    'fetch blocks binary types, downloads and missing content types before reading body',
    () async {
      for (final headers in [
        {'content-type': 'application/pdf'},
        {'content-type': 'application/octet-stream'},
        {
          'content-type': 'text/plain',
          'content-disposition': 'attachment; filename="download.txt"',
        },
        <String, String>{},
      ]) {
        var listened = false;
        final controller = StreamController<List<int>>(
          onListen: () {
            listened = true;
          },
        );
        final client = _Client(
          (_) async =>
              http.StreamedResponse(controller.stream, 200, headers: headers),
        );
        await expectLater(
          PageFetcher(clientFactory: () => client)
              .fetch('https://example.test', cancel: CancelToken())
              .timeout(const Duration(seconds: 2)),
          throwsA(
            isA<SearchFailure>().having(
              (error) => error.code,
              'code',
              'downloads_not_supported',
            ),
          ),
        );
        expect(listened, isFalse);
        expect(client.closed, isTrue);
      }
    },
  );

  test(
    'fetch and search reject redirects without following or forwarding auth',
    () async {
      final client = _Client((request) async {
        expect(request.followRedirects, isFalse);
        return _response(
          '',
          status: 302,
          headers: {'location': 'http://127.0.0.1/private'},
        );
      });
      await expectLater(
        PageFetcher(
          clientFactory: () => client,
        ).fetch('https://example.com', cancel: CancelToken()),
        throwsA(
          isA<SearchFailure>().having(
            (error) => error.code,
            'code',
            'redirect_to_private',
          ),
        ),
      );
      for (final kind in SearchKind.values) {
        final search = SearchService(
          SearchConfig(
            kind: kind,
            baseUrl: 'https://search.test',
            apiKeyRef: 'provider-ref',
          ),
          readSecret: (_) async => 'test-only-key',
          clientFactory: () => client,
        );
        await expectLater(
          search.search('query', cancel: CancelToken()),
          throwsA(
            isA<SearchFailure>().having(
              (error) => error.code,
              'code',
              'http_302',
            ),
          ),
        );
      }
      expect(client.requests.length, 1 + SearchKind.values.length);
    },
  );

  test('fetch follows public redirects manually', () async {
    final client = _Client((request) async {
      expect(request.followRedirects, isFalse);
      if (request.url.host == 'example.com') {
        return _response(
          '',
          status: 302,
          headers: {'location': 'https://www.example.com/final'},
        );
      }
      return _response(
        '<html><title>Done</title><body><p>Hello</p></body></html>',
        headers: {'content-type': 'text/html'},
      );
    });
    final result = await PageFetcher(
      clientFactory: () => client,
    ).fetch('https://example.com', cancel: CancelToken());
    expect(result['title'], 'Done');
    expect(client.requests.length, 2);
  });

  test(
    'invalid URLs fail before creating transport and missing configuration is unavailable',
    () async {
      final fetcher = PageFetcher(
        clientFactory: () => throw StateError('should not create client'),
      );
      for (final url in [
        'file:///tmp/a',
        'javascript:alert(1)',
        'https://user:password@example.test',
        '/relative',
      ]) {
        await expectLater(
          fetcher.fetch(url, cancel: CancelToken()),
          throwsA(
            isA<SearchFailure>().having(
              (error) => error.code,
              'code',
              'invalid_url',
            ),
          ),
        );
      }
      expect(
        SearchService(
          const SearchConfig(),
          readSecret: (_) async => null,
        ).isAvailable,
        isFalse,
      );
      expect(SearchConfig.fromJson({'resultCount': 100}).resultCount, 10);
    },
  );
}

http.StreamedResponse _response(
  String text, {
  int status = 200,
  String mime = 'application/json',
  Map<String, String> headers = const {},
}) => http.StreamedResponse(
  Stream.value(utf8.encode(text)),
  status,
  headers: {'content-type': mime, ...headers},
);

class _Client extends http.BaseClient {
  _Client(this.onSend);
  final Future<http.StreamedResponse> Function(http.BaseRequest request) onSend;
  final List<http.BaseRequest> requests = [];
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return onSend(request);
  }

  @override
  void close() {
    closed = true;
  }
}
