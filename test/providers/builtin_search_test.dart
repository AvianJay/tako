import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/chat/response_accumulator.dart';
import 'package:tako/core/providers/cancel_token.dart';
import 'package:tako/core/providers/messages/messages_adapter.dart';
import 'package:tako/core/providers/provider_adapter.dart';
import 'package:tako/core/providers/provider_config.dart';
import 'package:tako/core/providers/provider_event.dart';
import 'package:tako/core/providers/responses/responses_adapter.dart';
import 'package:tako/core/providers/sse.dart';
import 'package:tako/core/util/json.dart';

ProviderConfig config(
  ApiType type, {
  String? url,
  bool enabled = true,
  bool allowCustom = false,
}) => ProviderConfig(
  id: 'provider',
  displayName: 'Provider',
  apiType: type,
  baseUrl:
      url ??
      (type == ApiType.responses
          ? 'https://api.openai.com/v1'
          : 'https://api.anthropic.com/v1'),
  model: 'fixture-model',
  capabilities: ProviderCapabilities(
    builtInWebSearch: enabled,
    allowCustomSearchEndpoint: allowCustom,
  ),
);

ChatRequest request({
  bool granted = true,
  bool force = false,
  List<ChatMessage> messages = const [],
  List<ToolDefinition> tools = const [],
  bool replay = true,
  String hash = 'hash',
}) => ChatRequest(
  systemPrompt: 'system',
  messages: messages,
  tools: tools,
  builtInWebSearch: granted,
  forceBuiltInWebSearch: force,
  replayOpaqueReasoning: replay,
  promptHash: hash,
);

ChatMessage message(
  List<ContentBlock> content, {
  String model = 'fixture-model',
  String provider = 'provider',
  MessageRole role = MessageRole.assistant,
}) => ChatMessage(
  id: 'message',
  conversationId: 'chat',
  role: role,
  content: content,
  createdAt: DateTime.utc(2026),
  providerId: provider,
  model: model,
);

Stream<SseEvent> stream(List<Map<String, Object?>> events) =>
    Stream.fromIterable([
      for (final event in events) SseEvent(data: jsonEncode(event)),
    ]);

const citation = {
  'type': 'web_search_result_location',
  'title': 'Example',
  'url': 'https://example.com/source',
  'encrypted_index': 'opaque-reference',
  'cited_text': 'A fact.',
};
const serverUse = {
  'type': 'server_tool_use',
  'id': 'server1',
  'name': 'web_search',
  'input': <String, Object?>{},
};
const serverResult = {
  'type': 'web_search_tool_result',
  'tool_use_id': 'server1',
  'content': [
    {
      'type': 'web_search_result',
      'url': 'https://example.com/source',
      'title': 'Example',
      'encrypted_content': 'opaque-result',
    },
  ],
};

List<Map<String, Object?>> anthropicSearch({String stop = 'end_turn'}) => [
  {'type': 'content_block_start', 'index': 0, 'content_block': serverUse},
  {
    'type': 'content_block_delta',
    'index': 0,
    'delta': {'type': 'input_json_delta', 'partial_json': '{"query":"news"}'},
  },
  {'type': 'content_block_stop', 'index': 0},
  {'type': 'content_block_start', 'index': 1, 'content_block': serverResult},
  {'type': 'content_block_stop', 'index': 1},
  {
    'type': 'content_block_start',
    'index': 2,
    'content_block': {'type': 'text', 'text': ''},
  },
  {
    'type': 'content_block_delta',
    'index': 2,
    'delta': {'type': 'text_delta', 'text': 'A fact.'},
  },
  {
    'type': 'content_block_delta',
    'index': 2,
    'delta': {'type': 'citations_delta', 'citation': citation},
  },
  {'type': 'content_block_stop', 'index': 2},
  {
    'type': 'message_delta',
    'delta': {'stop_reason': stop},
  },
  {'type': 'message_stop'},
];

void main() {
  for (final type in [ApiType.responses, ApiType.messages]) {
    Map<String, Object?> body(ProviderConfig config, ChatRequest request) =>
        type == ApiType.responses
        ? ResponsesAdapter(config).buildBody(request)
        : MessagesAdapter(config).buildBody(request);
    test(
      '${type.name}: config and a request permission grant are both required',
      () {
        expect(
          body(config(type), request(granted: false)).containsKey('tools'),
          isFalse,
        );
        expect(
          body(config(type, enabled: false), request()).containsKey('tools'),
          isFalse,
        );
        final enabled = body(config(type), request());
        expect(
          enabled['tools'],
          type == ApiType.responses
              ? [
                  {'type': 'web_search'},
                ]
              : [
                  {
                    'type': 'web_search_20250305',
                    'name': 'web_search',
                    'max_uses': 1,
                  },
                ],
        );
        if (type == ApiType.responses) expect(enabled['max_tool_calls'], 1);
      },
    );

    test(
      '${type.name}: custom endpoints require explicit hosted search opt-in',
      () {
        final host = type == ApiType.responses
            ? 'api.openai.com'
            : 'api.anthropic.com';
        for (final url in [
          'https://custom.example/v1',
          'http://$host/v1',
          'https://$host.evil.example/v1',
          'https://$host:8443/v1',
          'https://$host/proxy',
          'https://name:pass@$host/v1',
          'https://$host/v1?secret=value',
        ]) {
          expect(
            body(config(type, url: url), request()).containsKey('tools'),
            isFalse,
            reason: url,
          );
        }
        expect(
          supportsBuiltInWebSearch(config(type, url: 'https://$host/')),
          isTrue,
        );
      },
    );

    test(
      '${type.name}: opt-in works for proxy paths and local HTTP servers',
      () {
        for (final url in [
          'https://cpa.example/v1',
          'http://127.0.0.1:8317/v1',
          'http://192.168.1.20:8317/custom/prefix',
        ]) {
          final custom = config(type, url: url, allowCustom: true);
          expect(supportsBuiltInWebSearch(custom), isTrue);
          final payload = body(custom, request(force: true));
          expect(payload['tools'], isNotEmpty);
          expect(
            payload['tool_choice'],
            type == ApiType.responses
                ? {'type': 'web_search'}
                : {'type': 'tool', 'name': 'web_search'},
          );
          expect(
            body(custom, request(granted: false, force: true)),
            isNot(contains('tools')),
          );
          expect(
            body(custom, request(granted: false, force: true)),
            isNot(contains('tool_choice')),
          );
        }
        final disabled = config(
          type,
          url: 'https://cpa.example/v1',
          allowCustom: true,
          enabled: false,
        );
        expect(body(disabled, request(force: true)), isNot(contains('tools')));
      },
    );

    test('${type.name}: custom opt-in never bypasses URL validation', () {
      for (final url in [
        'file:///v1',
        'https://user:pass@cpa.example/v1',
        'https://cpa.example/v1?secret=value',
        'https://cpa.example/v1#fragment',
        '/relative/v1',
        '',
      ]) {
        final custom = config(type, url: url, allowCustom: true);
        expect(supportsBuiltInWebSearch(custom), isFalse, reason: url);
        expect(body(custom, request(force: true)), isNot(contains('tools')));
      }
    });

    test('${type.name}: forcing a search is limited to an explicit probe', () {
      final normal = body(config(type), request());
      expect(normal, isNot(contains('tool_choice')));
      final forced = body(config(type), request(force: true));
      expect(forced, contains('tool_choice'));
    });

    test(
      '${type.name}: proxy request sends native search and receives proof',
      () async {
        final client = MockClient((outgoing) async {
          expect(
            outgoing.url.toString(),
            'http://127.0.0.1:8317/proxy/${type == ApiType.responses ? 'responses' : 'messages'}',
          );
          expect(outgoing.followRedirects, isFalse);
          final body = asMap(jsonDecode(outgoing.body))!;
          final nativeTool = asMap(asList(body['tools'])!.single)!;
          expect(
            nativeTool['type'],
            type == ApiType.responses ? 'web_search' : 'web_search_20250305',
          );
          expect(
            body['tool_choice'],
            type == ApiType.responses
                ? {'type': 'web_search'}
                : {'type': 'tool', 'name': 'web_search'},
          );
          final events = type == ApiType.responses
              ? [
                  {
                    'type': 'response.completed',
                    'response': {
                      'output': [
                        {
                          'type': 'web_search_call',
                          'id': 'ws1',
                          'status': 'completed',
                        },
                      ],
                    },
                  },
                ]
              : anthropicSearch();
          return http.Response(
            events.map((event) => 'data: ${jsonEncode(event)}\n\n').join(),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        });
        final adapter = ProviderAdapter.create(
          config(type, url: 'http://127.0.0.1:8317/proxy', allowCustom: true),
          clientFactory: () => client,
        );
        final events = await adapter
            .send(request(force: true), cancel: CancelToken())
            .toList();
        expect(events.whereType<ProviderError>(), isEmpty);
        expect(events.whereType<ToolCallStart>(), isEmpty);
        expect(events.whereType<HostedSearchEvent>().single.success, isTrue);
        expect(events.last, isA<Done>());
      },
    );

    test(
      '${type.name}: hosted search replaces duplicate local search only after grant',
      () {
        const tools = [
          ToolDefinition(name: 'web_search', description: 'search', schema: {}),
          ToolDefinition(
            name: 'get_device_status',
            description: 'status',
            schema: {},
          ),
        ];
        final enabled =
            body(config(type), request(tools: tools))['tools'] as List;
        expect(enabled, hasLength(2));
        expect(asMap(enabled.last)?['name'], 'get_device_status');
        final disabled =
            body(config(type), request(granted: false, tools: tools))['tools']
                as List;
        expect(asMap(disabled.first)?['name'], 'web_search');
      },
    );
  }

  test(
    'Anthropic server search streams citations without executing a client tool',
    () async {
      final events = await MessagesAdapter(
        config(ApiType.messages),
      ).decode(stream(anthropicSearch())).toList();
      expect(events.whereType<ToolCallStart>(), isEmpty);
      expect(events.whereType<HostedSearchEvent>().single.success, isTrue);
      expect(events.whereType<ProviderError>(), isEmpty);
      expect(
        events.whereType<TextDelta>().map((event) => event.text).join(),
        'A fact. [Example](https://example.com/source)',
      );
      final state = events.whereType<ProviderStateMetadata>().single;
      expect(state.content, [
        {
          ...serverUse,
          'input': {'query': 'news'},
        },
        serverResult,
        {
          'type': 'text',
          'text': 'A fact.',
          'citations': [citation],
        },
      ]);
    },
  );

  test(
    'Anthropic search state survives storage and round-trips exact original wire content',
    () async {
      final adapter = MessagesAdapter(config(ApiType.messages));
      final accumulator = ResponseAccumulator(
        sourceApi: ApiType.messages.name,
        promptHash: 'hash',
      );
      for (final event
          in await adapter.decode(stream(anthropicSearch())).toList()) {
        accumulator.add(event);
      }
      final stored = ChatMessage.fromJson(
        asMap(jsonDecode(jsonEncode(message(accumulator.content).toJson())))!,
      );
      final body = adapter.buildBody(request(messages: [stored]));
      expect(
        asMap((body['messages'] as List).single)?['content'],
        stored.content.whereType<ProviderStateBlock>().single.content,
      );
      expect(stored.text, contains('[Example](https://example.com/source)'));
      // Disabling search, rewriting history or switching model/provider must not
      // replay an old pending server request or expose opaque provider state.
      for (final request in [
        ChatRequest(
          systemPrompt: 'system',
          messages: [stored],
          promptHash: 'hash',
        ),
        ChatRequest(
          systemPrompt: 'system',
          messages: [stored],
          promptHash: 'hash',
          builtInWebSearch: true,
          replayOpaqueReasoning: false,
        ),
        ChatRequest(
          systemPrompt: 'system',
          messages: [stored],
          promptHash: 'new',
          builtInWebSearch: true,
        ),
        ChatRequest(
          systemPrompt: 'system',
          messages: [message(accumulator.content, model: 'different')],
          promptHash: 'hash',
          builtInWebSearch: true,
        ),
        ChatRequest(
          systemPrompt: 'system',
          messages: [message(accumulator.content, provider: 'different')],
          promptHash: 'hash',
          builtInWebSearch: true,
        ),
      ]) {
        expect(
          jsonEncode(adapter.buildBody(request)),
          isNot(contains('opaque-result')),
        );
      }
    },
  );

  test(
    'Anthropic pause_turn preserves provider state for a bounded continuation',
    () async {
      final events = await MessagesAdapter(
        config(ApiType.messages),
      ).decode(stream(anthropicSearch(stop: 'pause_turn'))).toList();
      expect(events.whereType<ProviderError>(), isEmpty);
      expect(events.whereType<Done>().single.stopReason, 'pause_turn');
      expect(events.whereType<ProviderStateMetadata>(), hasLength(1));
    },
  );

  test(
    'Responses search citations are clickable and duplicate annotations are suppressed',
    () async {
      const annotation = {
        'type': 'url_citation',
        'title': 'Example',
        'url': 'https://example.com/source',
      };
      const output = [
        {'type': 'web_search_call', 'id': 'ws1', 'status': 'completed'},
        {
          'type': 'message',
          'id': 'm1',
          'role': 'assistant',
          'status': 'completed',
          'content': [
            {
              'type': 'output_text',
              'text': 'A fact.',
              'annotations': [annotation],
            },
          ],
        },
      ];
      final adapter = ResponsesAdapter(config(ApiType.responses));
      final events = await adapter
          .decode(
            stream([
              {'type': 'response.output_text.delta', 'delta': 'A fact.'},
              {
                'type': 'response.output_text.annotation.added',
                'annotation': annotation,
              },
              {
                'type': 'response.output_item.done',
                'output_index': 1,
                'item': output.last,
              },
              {
                'type': 'response.completed',
                'response': {'output': output},
              },
            ]),
          )
          .toList();
      expect(events.whereType<ToolCallStart>(), isEmpty);
      expect(events.whereType<HostedSearchEvent>().single.success, isTrue);
      expect(
        events.whereType<TextDelta>().map((event) => event.text).join(),
        'A fact. [Example](https://example.com/source)',
      );
      final accumulator = ResponseAccumulator(
        sourceApi: ApiType.responses.name,
        promptHash: 'hash',
      );
      events.forEach(accumulator.add);
      expect(
        adapter.buildBody(
          request(messages: [message(accumulator.content)]),
        )['input'],
        output,
      );
    },
  );

  test('Chat Completions cannot opt in to hosted search', () {
    expect(
      supportsBuiltInWebSearch(
        config(
          ApiType.chatCompletions,
          url: 'http://127.0.0.1:8317/v1',
          allowCustom: true,
        ),
      ),
      isFalse,
    );
  });

  test(
    'Responses search receipts are deduplicated across streamed events',
    () async {
      const item = {
        'type': 'web_search_call',
        'id': 'ws1',
        'status': 'completed',
      };
      final events = await ResponsesAdapter(config(ApiType.responses))
          .decode(
            stream([
              {
                'type': 'response.web_search_call.completed',
                'item_id': 'ws1',
                'output_index': 0,
              },
              {
                'type': 'response.output_item.done',
                'output_index': 0,
                'item': item,
              },
              {
                'type': 'response.completed',
                'response': {
                  'output': [item],
                },
              },
            ]),
          )
          .toList();
      expect(events.whereType<HostedSearchEvent>(), hasLength(1));
      expect(events.whereType<HostedSearchEvent>().single.success, isTrue);
    },
  );

  test('Responses failed search is a failed structured receipt', () async {
    final events = await ResponsesAdapter(config(ApiType.responses))
        .decode(
          stream([
            {
              'type': 'response.completed',
              'response': {
                'output': [
                  {'type': 'web_search_call', 'id': 'ws1', 'status': 'failed'},
                ],
              },
            },
          ]),
        )
        .toList();
    final receipt = events.whereType<HostedSearchEvent>().single;
    expect(receipt.success, isFalse);
    expect(receipt.errorCode, 'web_search_failed');
  });

  test(
    'Responses final failure overrides an earlier success receipt',
    () async {
      final events = await ResponsesAdapter(config(ApiType.responses))
          .decode(
            stream([
              {
                'type': 'response.web_search_call.completed',
                'item_id': 'ws1',
                'output_index': 0,
              },
              {
                'type': 'response.completed',
                'response': {
                  'status': 'completed',
                  'output': [
                    {
                      'type': 'web_search_call',
                      'id': 'ws1',
                      'status': 'failed',
                    },
                  ],
                },
              },
            ]),
          )
          .toList();
      expect(events.whereType<HostedSearchEvent>().map((e) => e.success), [
        true,
        false,
      ]);
    },
  );

  test(
    'Responses a failed receipt cannot be overwritten by later success',
    () async {
      final events = await ResponsesAdapter(config(ApiType.responses))
          .decode(
            stream([
              {
                'type': 'response.output_item.done',
                'output_index': 0,
                'item': {
                  'type': 'web_search_call',
                  'id': 'ws1',
                  'status': 'failed',
                },
              },
              {
                'type': 'response.web_search_call.completed',
                'item_id': 'ws1',
                'output_index': 0,
              },
              {
                'type': 'response.completed',
                'response': {
                  'status': 'completed',
                  'output': [
                    {
                      'type': 'web_search_call',
                      'id': 'ws1',
                      'status': 'completed',
                    },
                  ],
                },
              },
            ]),
          )
          .toList();
      expect(events.whereType<HostedSearchEvent>().single.success, isFalse);
    },
  );

  for (final status in ['incomplete', 'failed', 'in_progress', 'cancelled']) {
    test('Responses completed event rejects envelope status $status', () async {
      final events = await ResponsesAdapter(config(ApiType.responses))
          .decode(
            stream([
              {'type': 'response.web_search_call.completed', 'item_id': 'ws1'},
              {
                'type': 'response.completed',
                'response': {'status': status},
              },
            ]),
          )
          .toList();
      expect(events.whereType<HostedSearchEvent>().single.success, isTrue);
      expect(events.whereType<ProviderError>(), hasLength(1));
      expect(events.whereType<Done>(), isEmpty);
    });
  }

  test(
    'text claims, citations and uncompleted calls never confirm search',
    () async {
      final responses = await ResponsesAdapter(config(ApiType.responses))
          .decode(
            stream([
              {
                'type': 'response.output_text.delta',
                'delta': 'I searched the web.',
              },
              {
                'type': 'response.output_text.annotation.added',
                'annotation': {
                  'type': 'url_citation',
                  'url': 'https://example.com',
                  'title': 'Source',
                },
              },
              {
                'type': 'response.completed',
                'response': {
                  'output': [
                    {
                      'type': 'web_search_call',
                      'id': 'ws1',
                      'status': 'in_progress',
                    },
                  ],
                },
              },
            ]),
          )
          .toList();
      final messages = await MessagesAdapter(config(ApiType.messages))
          .decode(
            stream([
              {
                'type': 'content_block_start',
                'index': 0,
                'content_block': serverUse,
              },
              {'type': 'content_block_stop', 'index': 0},
              {'type': 'message_stop'},
            ]),
          )
          .toList();
      expect(responses.whereType<HostedSearchEvent>(), isEmpty);
      expect(messages.whereType<HostedSearchEvent>(), isEmpty);
    },
  );

  test(
    'Anthropic search errors are not mistaken for a supported search',
    () async {
      final events = await MessagesAdapter(config(ApiType.messages))
          .decode(
            stream([
              {
                'type': 'content_block_start',
                'index': 0,
                'content_block': {
                  'type': 'web_search_tool_result',
                  'tool_use_id': 'server1',
                  'content': {
                    'type': 'web_search_tool_result_error',
                    'error_code': 'unavailable',
                  },
                },
              },
              {'type': 'content_block_stop', 'index': 0},
              {'type': 'message_stop'},
            ]),
          )
          .toList();
      final receipt = events.whereType<HostedSearchEvent>().single;
      expect(receipt.success, isFalse);
      expect(receipt.errorCode, 'unavailable');
    },
  );

  test(
    'malformed tool args replay only when an error result has been supplied',
    () {
      final adapter = MessagesAdapter(config(ApiType.messages));
      final call = message([
        const ToolCallBlock(id: 'bad', name: 'file_read', arguments: '{'),
      ]);
      expect(
        () => adapter.buildBody(request(messages: [call])),
        throwsA(isA<ProviderError>()),
      );
      final result = message([
        const ToolResultBlock(
          toolCallId: 'bad',
          toolName: 'file_read',
          content: '{"error":"invalid_arguments"}',
          isError: true,
        ),
      ], role: MessageRole.tool);
      final body = adapter.buildBody(
        request(messages: [call, result], replay: false),
      );
      expect(
        asMap(
          asList(asMap((body['messages'] as List).first)?['content'])!.first,
        )?['input'],
        <String, Object?>{},
      );
    },
  );

  test('citation metadata cannot inject active schemes or markdown syntax', () {
    expect(
      providerCitationLink({'url': 'javascript:alert(1)', 'title': 'unsafe'}),
      isNull,
    );
    expect(
      providerCitationLink({'url': 'https://user:pass@example.com'}),
      isNull,
    );
    final link = providerCitationLink({
      'url': 'https://example.com/a(b)',
      'title': '[click](javascript:bad)',
    });
    expect(link, r' [\[click\](javascript:bad)](https://example.com/a%28b%29)');
  });
}
