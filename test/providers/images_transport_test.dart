import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/providers/images/images_adapter.dart';
import 'package:tako/core/providers/providers.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=';

class _Client extends http.BaseClient {
  _Client(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
  @override
  void close() => closed = true;
}

http.StreamedResponse _json(Object body, [int status = 200]) =>
    http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: {'content-type': 'application/json'},
    );

ProviderConfig _config({bool references = true}) => ProviderConfig(
  id: 'images',
  displayName: 'Image provider',
  apiType: ApiType.chatCompletions,
  baseUrl: 'https://provider.example/v1/images/generations',
  model: 'gpt-image-1',
  capabilities: ProviderCapabilities(
    imageGeneration: ImageGenerationMode.imagesApi,
    imageReferenceInput: references,
  ),
);

ChatRequest _request({bool reference = false}) => ChatRequest(
  systemPrompt: 'Do not send system prompt to the image API',
  messages: [
    ChatMessage(
      id: 'user',
      conversationId: 'chat',
      role: MessageRole.user,
      createdAt: DateTime.utc(2026),
      content: [
        const TextBlock('A bird'),
        if (reference)
          const ImageBlock(
            path: 'attachments/ref.png',
            mimeType: 'image/png',
            data: _png,
          ),
      ],
    ),
  ],
);

ChatRequest _references(int count) {
  final base = _request(reference: true);
  return ChatRequest(
    systemPrompt: '',
    messages: [
      base.messages.single.copyWith(
        content: [
          const TextBlock('A bird'),
          for (var i = 0; i < count; i++)
            ImageBlock(
              path: 'attachments/ref-$i.png',
              mimeType: 'image/png',
              data: _png,
            ),
        ],
      ),
    ],
  );
}

void main() {
  test(
    'factory routes image profile to authenticated JSON generation endpoint',
    () async {
      final client = _Client((request) async {
        expect(
          request.url.toString(),
          'https://provider.example/v1/images/generations',
        );
        expect(request.headers['authorization'], 'Bearer test-key');
        expect(request.followRedirects, isFalse);
        expect(jsonDecode((request as http.Request).body), {
          'model': 'gpt-image-1',
          'prompt': 'A bird',
          'n': 1,
        });
        return _json({
          'data': [
            {'b64_json': _png},
          ],
          'usage': {'input_tokens': 5, 'output_tokens': 8, 'total_tokens': 13},
        });
      });
      final adapter = ProviderAdapter.create(
        _config(),
        apiKey: 'test-key',
        clientFactory: () => client,
      );
      expect(adapter, isA<ImagesAdapter>());
      final events = await adapter
          .send(_request(), cancel: CancelToken())
          .toList();
      expect(events.whereType<GeneratedImage>().single.base64, _png);
      expect(events.whereType<Usage>().single.totalTokens, 13);
      expect(events.last, isA<Done>());
      expect(client.closed, isTrue);
    },
  );

  test(
    'reference images use multipart edit with actual bytes and MIME type',
    () async {
      final client = _Client((request) async {
        expect(request.url.path, '/v1/images/edits');
        final multipart = request as http.MultipartRequest;
        expect(multipart.fields['prompt'], 'A bird');
        expect(multipart.files.single.field, 'image');
        expect(multipart.files.single.contentType.toString(), 'image/png');
        expect(
          await multipart.files.single.finalize().toBytes(),
          base64Decode(_png),
        );
        return _json({
          'data': [
            {'b64_json': _png},
          ],
        });
      });
      final events = await ImagesAdapter(
        _config(),
        clientFactory: () => client,
      ).send(_request(reference: true), cancel: CancelToken()).toList();
      expect(events.last, isA<Done>());
    },
  );

  test('unsupported references fail before any network request', () async {
    var called = false;
    final client = _Client((_) async {
      called = true;
      return _json({});
    });
    final events = await ImagesAdapter(
      _config(references: false),
      clientFactory: () => client,
    ).send(_request(reference: true), cancel: CancelToken()).toList();
    expect(events.single, isA<ProviderError>());
    expect(called, isFalse);
  });

  for (final count in [2, 16]) {
    test('multipart edits send all $count ordered reference files', () async {
      final client = _Client((request) async {
        expect(request.url.path, '/v1/images/edits');
        final files = (request as http.MultipartRequest).files;
        expect(files, hasLength(count));
        for (var i = 0; i < count; i++) {
          expect(files[i].field, 'image[]');
          expect(files[i].filename, 'reference-${i + 1}.png');
          expect(await files[i].finalize().toBytes(), base64Decode(_png));
        }
        return _json({
          'data': [
            {'b64_json': _png},
          ],
        });
      });
      final events = await ImagesAdapter(
        _config(),
        clientFactory: () => client,
      ).send(_references(count), cancel: CancelToken()).toList();
      expect(events.last, isA<Done>());
    });
  }

  for (final (api, mode) in [
    (ApiType.chatCompletions, ImageGenerationMode.imagesApi),
    (ApiType.chatCompletions, ImageGenerationMode.chatOutput),
    (ApiType.responses, ImageGenerationMode.responsesTool),
  ]) {
    test('$mode enforces custom limits before sending a request', () async {
      var sent = false;
      final client = _Client((_) async {
        sent = true;
        return _json({});
      });
      final adapter = ProviderAdapter.create(
        _config().copyWith(
          apiType: api,
          capabilities: ProviderCapabilities(
            imageGeneration: mode,
            imageReferenceInput: true,
            maxReferenceImages: 1,
          ),
        ),
        clientFactory: () => client,
      );
      final events = await adapter
          .send(_references(2), cancel: CancelToken())
          .toList();
      expect(
        events.whereType<ProviderError>().single.code,
        'too_many_reference_images',
      );
      expect(sent, isFalse);
    });
  }

  test(
    'chat image input limits include images replayed from earlier turns',
    () async {
      var sent = false;
      final client = _Client((_) async {
        sent = true;
        return _json({});
      });
      final base = _references(1).messages.single;
      final adapter = ProviderAdapter.create(
        _config().copyWith(
          capabilities: const ProviderCapabilities(
            imageGeneration: ImageGenerationMode.chatOutput,
            imageReferenceInput: true,
            maxReferenceImages: 1,
          ),
        ),
        clientFactory: () => client,
      );
      final events = await adapter
          .send(
            ChatRequest(
              systemPrompt: '',
              messages: [
                base,
                ChatMessage(
                  id: 'next',
                  conversationId: 'chat',
                  role: MessageRole.user,
                  createdAt: DateTime.utc(2026),
                  content: base.content,
                ),
              ],
            ),
            cancel: CancelToken(),
          )
          .toList();
      expect(
        events.whereType<ProviderError>().single.code,
        'too_many_reference_images',
      );
      expect(sent, isFalse);
    },
  );

  for (final referenceCount in [0, 1, 2]) {
    test(
      'xAI image requests use JSON with $referenceCount reference images',
      () async {
        final client = _Client((request) async {
          expect(
            request.url.path,
            referenceCount == 0 ? '/v1/images/generations' : '/v1/images/edits',
          );
          expect(request.headers['content-type'], 'application/json');
          expect(request.followRedirects, isFalse);
          final body =
              jsonDecode((request as http.Request).body)
                  as Map<String, Object?>;
          expect(body['model'], 'grok-imagine-image-2.0');
          expect(body['response_format'], 'b64_json');
          if (referenceCount > 0) {
            final references = referenceCount == 1
                ? [body['image']]
                : body['images'] as List<Object?>;
            expect(references, hasLength(referenceCount));
            expect(references.first, {
              'type': 'image_url',
              'url': 'data:image/png;base64,$_png',
            });
          }
          return _json({
            'data': [
              {'b64_json': _png},
            ],
          });
        });
        final base = _request(reference: true);
        final request = ChatRequest(
          systemPrompt: base.systemPrompt,
          messages: [
            base.messages.single.copyWith(
              content: [
                const TextBlock('A bird'),
                for (var i = 0; i < referenceCount; i++)
                  base.messages.single.content.last,
              ],
            ),
          ],
        );
        final config = _config().copyWith(
          baseUrl: 'https://api.x.ai/v1',
          model: 'grok-imagine-image-2.0',
        );
        final events = await ImagesAdapter(
          config,
          clientFactory: () => client,
        ).send(request, cancel: CancelToken()).toList();
        expect(events.whereType<GeneratedImage>().single.base64, _png);
        expect(events.last, isA<Done>());
      },
    );
  }

  test('xAI rejects more than five references before sending', () async {
    var sent = false;
    final client = _Client((_) async {
      sent = true;
      return _json({});
    });
    final base = _request(reference: true);
    final request = ChatRequest(
      systemPrompt: '',
      messages: [
        base.messages.single.copyWith(
          content: [
            const TextBlock('A bird'),
            for (var i = 0; i < 6; i++) base.messages.single.content.last,
          ],
        ),
      ],
    );
    final events = await ImagesAdapter(
      _config().copyWith(baseUrl: 'https://api.x.ai/v1'),
      clientFactory: () => client,
    ).send(request, cancel: CancelToken()).toList();
    expect(events.single, isA<ProviderError>());
    expect(sent, isFalse);
  });

  test('output URL download never receives provider credentials', () async {
    var count = 0;
    final adapter = ImagesAdapter(
      _config(),
      apiKey: 'test-key',
      secretHeaders: {'x-private': 'private-header'},
      clientFactory: () {
        count++;
        return _Client((request) async {
          if (request.method == 'POST') {
            return _json({
              'data': [
                {'url': 'https://cdn.example/image.png?signature=test'},
              ],
            });
          }
          expect(request.headers.keys, isNot(contains('authorization')));
          expect(request.headers.keys, isNot(contains('x-private')));
          expect(request.followRedirects, isFalse);
          return http.StreamedResponse(
            Stream.value(base64Decode(_png)),
            200,
            headers: {'content-type': 'image/png'},
          );
        });
      },
    );
    final events = await adapter
        .send(_request(), cancel: CancelToken())
        .toList();
    expect(events.whereType<GeneratedImage>().single.mimeType, 'image/png');
    expect(count, 2);
  });

  test('unsafe image URLs are rejected before a download', () async {
    var requests = 0;
    final adapter = ImagesAdapter(
      _config(),
      clientFactory: () => _Client((_) async {
        requests++;
        return _json({
          'data': [
            {'url': 'https://127.0.0.1/image.png'},
          ],
        });
      }),
    );
    final events = await adapter
        .send(_request(), cancel: CancelToken())
        .toList();
    expect(events.whereType<ProviderError>().single.code, 'invalid_image_url');
    expect(requests, 1);
  });

  test('errors redact keys and custom authorization values', () async {
    final client = _Client(
      (_) async => _json({
        'error': {'message': 'test-key private-header', 'code': 'test-key'},
      }, 401),
    );
    final adapter = ImagesAdapter(
      _config(),
      apiKey: 'test-key',
      secretHeaders: {'x-private': 'private-header'},
      clientFactory: () => client,
    );
    final error =
        (await adapter.send(_request(), cancel: CancelToken()).toList()).single
            as ProviderError;
    expect(error.message, isNot(contains('test-key')));
    expect(error.message, isNot(contains('private-header')));
    expect(error.code, isNot(contains('test-key')));
    expect(error.statusCode, 401);
  });

  test(
    'malformed image payload does not become a successful response',
    () async {
      final client = _Client(
        (_) async => _json({
          'data': [
            {'b64_json': 'not an image'},
          ],
        }),
      );
      final events = await ImagesAdapter(
        _config(),
        clientFactory: () => client,
      ).send(_request(), cancel: CancelToken()).toList();
      expect(events.single, isA<ProviderError>());
    },
  );

  test('Stop cancels a pending image generation request', () async {
    final entered = Completer<void>();
    final pending = Completer<http.StreamedResponse>();
    final client = _Client((_) {
      entered.complete();
      return pending.future;
    });
    final cancel = CancelToken();
    final result = ImagesAdapter(
      _config(),
      clientFactory: () => client,
    ).send(_request(), cancel: cancel).toList();
    await entered.future;
    cancel.cancel();
    expect(await result.timeout(const Duration(seconds: 1)), isEmpty);
    expect(client.closed, isTrue);
    pending.complete(
      _json({
        'data': [
          {'b64_json': _png},
        ],
      }),
    );
  });
}
