// Opt-in real proxy verification. Credentials are read only from ignored env.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/chat/response_accumulator.dart';
import 'package:tako/core/providers/providers.dart';

void main() {
  test(
    'proxy discovers GPT and Claude and streams a GPT Responses tool call',
    () async {
      final env = <String, String>{};
      for (final line in File('cpa.env').readAsLinesSync()) {
        final split = line.indexOf('=');
        if (split > 0) {
          env[line.substring(0, split).trim()] = line
              .substring(split + 1)
              .trim()
              .replaceAll(RegExp(r'''^["']|["']$'''), '');
        }
      }
      final proxy = ProviderConfig(
        id: 'live',
        displayName: 'CPA',
        apiType: ApiType.messages,
        baseUrl: env['api_endpoint']!,
        model: 'claude-haiku-5-5',
        autoRouteModels: true,
      );
      final models = await ProviderAdapter.create(
        proxy,
        apiKey: env['api_key'],
      ).listModels();
      expect(models.any((m) => m.id == 'gpt-6.1-sol'), true);
      expect(models.any((m) => m.id == 'claude-haiku-5-5'), true);
      final selected = mergeDiscoveredModels(
        proxy,
        models,
      ).forModel('gpt-6.1-sol');
      final adapter = ProviderAdapter.create(selected, apiKey: env['api_key']);
      final output = ResponseAccumulator(
        sourceApi: selected.apiType.name,
        promptHash: 'proxy-smoke',
      );
      await for (final event in adapter.send(
        ChatRequest(
          systemPrompt:
              'Call echo_test exactly once with value READY. This is a harmless in-memory wire format test. Do not answer with plain text.',
          messages: [
            ChatMessage(
              id: 'test',
              conversationId: 'live',
              role: MessageRole.user,
              createdAt: DateTime.now(),
              content: const [TextBlock('Call echo_test with READY now.')],
            ),
          ],
          maxTokens: 512,
          tools: const [
            ToolDefinition(
              name: 'echo_test',
              description: 'Harmless protocol test.',
              schema: {
                'type': 'object',
                'properties': {
                  'value': {'type': 'string'},
                },
                'required': ['value'],
                'additionalProperties': false,
              },
            ),
          ],
        ),
        cancel: CancelToken(),
      )) {
        expect(event, isNot(isA<ProviderError>()));
        output.add(event);
      }
      final call = output.content.whereType<ToolCallBlock>().single;
      expect(call.name, 'echo_test');
      expect(call.arguments, contains('READY'));
    },
    skip: Platform.environment['TAKO_PROVIDER_LIVE'] != '1',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
