import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/providers/cancel_token.dart';
import 'package:tako/core/providers/chat_completions/chat_completions_adapter.dart';
import 'package:tako/core/providers/provider_adapter.dart';
import 'package:tako/core/providers/provider_config.dart';
import 'package:tako/core/providers/provider_event.dart';
import 'package:tako/core/providers/responses/responses_adapter.dart';
import 'package:tako/core/providers/sse.dart';
import 'package:tako/core/util/json.dart';

const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=';
const imageUrl = 'data:image/png;base64,$png';

ProviderConfig configuration(ApiType type, ImageGenerationMode mode) =>
    ProviderConfig(
      id: 'provider',
      displayName: 'Provider',
      apiType: type,
      baseUrl: 'https://provider.example/v1',
      model: 'image-chat',
      capabilities: ProviderCapabilities(imageGeneration: mode),
    );

ChatMessage message(
  List<ContentBlock> blocks, {
  MessageRole role = MessageRole.assistant,
}) => ChatMessage(
  id: 'message',
  conversationId: 'conversation',
  role: role,
  content: blocks,
  createdAt: DateTime.utc(2026),
  providerId: 'provider',
  model: 'image-chat',
);

const request = ChatRequest(systemPrompt: 'help', messages: []);

Stream<SseEvent> events(List<Map<String, Object?>> values) =>
    Stream.fromIterable(
      values.map((value) => SseEvent(data: jsonEncode(value))),
    );

Map<String, Object?> chunk(Map<String, Object?> delta, {String? finish}) => {
  'choices': [
    {'index': 0, 'delta': delta, 'finish_reason': finish},
  ],
};

Map<String, Object?> imageItem({String status = 'completed'}) => {
  'id': 'img_1',
  'type': 'image_generation_call',
  'status': status,
  'result': png,
  'output_format': 'png',
  'revised_prompt': 'A tiny image',
};

class StreamClient extends http.BaseClient {
  StreamClient(this.values);
  final List<Map<String, Object?>> values;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.fromIterable(
          values.map((value) => utf8.encode('data: ${jsonEncode(value)}\n\n')),
        ),
        200,
      );

  @override
  void close() => closed = true;
}

void main() {
  test(
    'generated image with a function call keeps its tool response adjacent',
    () {
      final adapter = ChatCompletionsAdapter(
        configuration(ApiType.chatCompletions, ImageGenerationMode.chatOutput),
      );
      final body = adapter.buildBody(
        ChatRequest(
          systemPrompt: 'help',
          messages: [
            message([
              const ImageBlock(
                path: 'attachments/result.png',
                mimeType: 'image/png',
                data: png,
              ),
              const ToolCallBlock(
                id: 'call',
                name: 'get_device_status',
                arguments: '{}',
              ),
            ]),
            message([
              const ToolResultBlock(
                toolCallId: 'call',
                toolName: 'get_device_status',
                content: '{}',
              ),
            ], role: MessageRole.tool),
          ],
        ),
      );
      final messages = (body['messages']! as List).cast<Map<String, Object?>>();
      final assistant = messages.indexWhere((m) => m['role'] == 'assistant');
      expect(messages[assistant + 1]['role'], 'tool');
      expect(messages[assistant + 1]['tool_call_id'], 'call');
    },
  );

  group('chat image output', () {
    ChatCompletionsAdapter adapter([
      ImageGenerationMode mode = ImageGenerationMode.chatOutput,
    ]) => ChatCompletionsAdapter(configuration(ApiType.chatCompletions, mode));

    test('requests image modalities only for the configured chat model', () {
      expect(adapter().buildBody(request)['modalities'], ['text', 'image']);
      expect(
        adapter(ImageGenerationMode.none).buildBody(request),
        isNot(contains('modalities')),
      );
      expect(
        adapter(ImageGenerationMode.responsesTool).buildBody(request),
        isNot(contains('modalities')),
      );
    });

    test('streams text and deduplicates repeated image output', () async {
      final image = {
        'type': 'image_url',
        'image_url': {'url': imageUrl},
      };
      final result = await adapter()
          .decode(
            events([
              chunk({
                'content': 'Here it is. ',
                'images': [image],
              }),
              chunk({
                'images': [image],
              }),
              chunk({'content': 'Enjoy.'}, finish: 'stop'),
            ]),
          )
          .toList();
      expect(
        result.whereType<TextDelta>().map((e) => e.text).join(),
        'Here it is. Enjoy.',
      );
      expect(result.whereType<GeneratedImage>().single.base64, png);
      expect(result.whereType<GeneratedImage>().single.mimeType, 'image/png');
      expect(result.last, isA<Done>());
    });

    test('supports content parts and a final message envelope', () async {
      final result = await adapter()
          .decode(
            events([
              chunk({
                'content': [
                  {'type': 'text', 'text': 'Picture'},
                  {
                    'type': 'image_url',
                    'image_url': {'url': imageUrl},
                  },
                ],
              }),
              {
                'choices': [
                  {
                    'index': 0,
                    'delta': {},
                    'message': {
                      'images': [
                        {
                          'image_url': {'url': imageUrl},
                        },
                      ],
                    },
                    'finish_reason': 'stop',
                  },
                ],
              },
            ]),
          )
          .toList();
      expect(result.whereType<TextDelta>().single.text, 'Picture');
      expect(result.whereType<GeneratedImage>(), hasLength(1));
      expect(result.last, isA<Done>());
    });

    test('image-only completion succeeds without synthetic text', () async {
      final result = await adapter()
          .decode(
            events([
              {
                'choices': [
                  {
                    'message': {
                      'images': [
                        {
                          'image_url': {'url': imageUrl},
                        },
                      ],
                    },
                    'finish_reason': 'stop',
                  },
                ],
              },
            ]),
          )
          .toList();
      expect(result.whereType<TextDelta>(), isEmpty);
      expect(result.whereType<GeneratedImage>(), hasLength(1));
      expect(result.last, isA<Done>());
    });

    test(
      'rejects remote output URLs and malformed image bytes explicitly',
      () async {
        for (final url in [
          'https://image.example/output.png',
          'data:image/png;base64,bad',
        ]) {
          final client = StreamClient([
            chunk({
              'images': [
                {
                  'image_url': {'url': url},
                },
              ],
            }, finish: 'stop'),
          ]);
          final result = await ChatCompletionsAdapter(
            configuration(
              ApiType.chatCompletions,
              ImageGenerationMode.chatOutput,
            ),
            clientFactory: () => client,
          ).send(request, cancel: CancelToken()).toList();
          expect(result.whereType<Done>(), isEmpty);
          expect(
            result.whereType<ProviderError>().single.code,
            url.startsWith('https:')
                ? 'unsupported_image_url'
                : 'invalid_image',
          );
          expect(client.closed, isTrue);
        }
      },
    );

    test(
      'keeps generated assistant images as valid user attachment context',
      () {
        final body = adapter().buildBody(
          ChatRequest(
            systemPrompt: 'help',
            messages: [
              message([
                const TextBlock('Here is the image.'),
                const ImageBlock(
                  path: 'attachments/image.png',
                  mimeType: 'image/png',
                  data: png,
                ),
              ]),
            ],
          ),
        );
        final messages = asList(body['messages'])!;
        expect(messages[1], {
          'role': 'assistant',
          'content': 'Here is the image.',
        });
        final attachment = asMap(messages[2])!;
        expect(attachment['role'], 'user');
        final image = asMap(asList(attachment['content'])![1])!;
        expect(asMap(image['image_url'])!['url'], imageUrl);
      },
    );
  });

  group('Responses image generation', () {
    ResponsesAdapter adapter([
      ImageGenerationMode mode = ImageGenerationMode.responsesTool,
    ]) => ResponsesAdapter(configuration(ApiType.responses, mode));

    test('injects a native tool only when configured', () {
      expect(adapter().buildBody(request)['tools'], [
        {'type': 'image_generation'},
      ]);
      expect(
        adapter(ImageGenerationMode.none).buildBody(request),
        isNot(contains('tools')),
      );
      expect(
        adapter(ImageGenerationMode.chatOutput).buildBody(request),
        isNot(contains('tools')),
      );
    });

    test(
      'emits final image once and omits image bytes from replay state',
      () async {
        final item = imageItem();
        final result = await adapter()
            .decode(
              events([
                {
                  'type': 'response.image_generation_call.partial_image',
                  'partial_image_b64': png,
                },
                {'type': 'response.output_text.delta', 'delta': 'Ready.'},
                {
                  'type': 'response.output_item.done',
                  'output_index': 0,
                  'item': item,
                },
                {
                  'type': 'response.completed',
                  'response': {
                    'status': 'completed',
                    'output': [
                      item,
                      {
                        'type': 'message',
                        'role': 'assistant',
                        'content': [
                          {'type': 'output_text', 'text': 'Ready.'},
                        ],
                      },
                    ],
                    'usage': {'input_tokens': 2, 'output_tokens': 4},
                  },
                },
              ]),
            )
            .toList();
        expect(result.whereType<GeneratedImage>(), hasLength(1));
        expect(result.whereType<GeneratedImage>().single.alt, 'A tiny image');
        expect(result.whereType<TextDelta>().single.text, 'Ready.');
        expect(result.whereType<Usage>().single.outputTokens, 4);
        final state = result.whereType<ProviderStateMetadata>().single;
        expect(jsonEncode(state.content), isNot(contains(png)));
        expect(
          state.content.any((item) => item['type'] == 'image_generation_call'),
          isFalse,
        );
        expect(result.last, isA<Done>());
      },
    );

    test(
      'supports completed-envelope image output without item events',
      () async {
        final result = await adapter()
            .decode(
              events([
                {
                  'type': 'response.completed',
                  'response': {
                    'output': [imageItem()],
                  },
                },
              ]),
            )
            .toList();
        expect(result.whereType<GeneratedImage>().single.base64, png);
        expect(result.whereType<ProviderStateMetadata>(), isEmpty);
        expect(result.last, isA<Done>());
      },
    );

    test(
      'failed and missing results cannot be reported as clean completion',
      () async {
        for (final item in [
          imageItem(status: 'failed'),
          {'type': 'image_generation_call', 'status': 'completed'},
        ]) {
          final client = StreamClient([
            {
              'type': 'response.completed',
              'response': {
                'output': [item],
              },
            },
          ]);
          final result = await ResponsesAdapter(
            configuration(ApiType.responses, ImageGenerationMode.responsesTool),
            clientFactory: () => client,
          ).send(request, cancel: CancelToken()).toList();
          expect(result.whereType<GeneratedImage>(), isEmpty);
          expect(result.whereType<ProviderError>(), hasLength(1));
          expect(result.whereType<Done>(), isEmpty);
        }
      },
    );

    test('replays local generated images alongside opaque reasoning state', () {
      final body = adapter().buildBody(
        ChatRequest(
          systemPrompt: 'help',
          promptHash: 'prompt',
          messages: [
            message([
              const TextBlock('Ready.'),
              const ImageBlock(
                path: 'attachments/image.png',
                mimeType: 'image/png',
                data: png,
              ),
              const ProviderStateBlock(
                sourceApi: 'responses',
                promptHash: 'prompt',
                content: [
                  {'type': 'reasoning', 'encrypted_content': 'opaque'},
                ],
              ),
            ]),
          ],
        ),
      );
      final input = asList(body['input'])!;
      expect(asMap(input[0])!['type'], 'reasoning');
      expect(input[1], {'role': 'assistant', 'content': 'Ready.'});
      final attachment = asMap(input[2])!;
      expect(attachment['role'], 'user');
      expect(asList(attachment['content'])![1], {
        'type': 'input_image',
        'image_url': imageUrl,
      });
    });

    test('replays image-only history without assistant input_image parts', () {
      final body = adapter().buildBody(
        ChatRequest(
          systemPrompt: 'help',
          messages: [
            message([
              const ImageBlock(
                path: 'attachments/image.png',
                mimeType: 'image/png',
                data: png,
              ),
            ]),
          ],
        ),
      );
      final attachment = asMap(asList(body['input'])!.single)!;
      expect(attachment['role'], 'user');
      final image = asMap(asList(attachment['content'])![1])!;
      expect(image['image_url'], imageUrl);
    });
  });
}
