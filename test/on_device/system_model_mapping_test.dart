import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/platform/on_device/system_model_mapping.dart';

const tools = [ToolDefinition(name: 'test', description: '', schema: {})];

List<ProviderEvent> agentEvents(
  Map<Object?, Object?> reply,
  List<ToolDefinition> tools,
) => systemModelAgentEvents(reply, tools, invalidCode: 'apple_invalid_tools');

void main() {
  for (final arguments in ['[]', 'null', '42', '"text"', '{', '{} trailing']) {
    test(
      'rejects tool arguments $arguments as an incomplete or non-object response',
      () {
        expect(
          () => agentEvents({
            'kind': 'tool_calls',
            'text': '',
            'calls': [
              {'name': 'test', 'arguments': arguments},
            ],
          }, tools),
          throwsA(isA<ProviderError>()),
        );
      },
    );
  }
  test('validates every call before publishing text or any tool event', () {
    expect(
      () => agentEvents({
        'kind': 'tool_calls',
        'text': 'intro',
        'calls': [
          {'name': 'test', 'arguments': '{}'},
          {'name': 'test', 'arguments': '[]'},
        ],
      }, tools),
      throwsA(
        isA<ProviderError>().having(
          (e) => e.code,
          'code',
          'apple_invalid_tools',
        ),
      ),
    );
  });
  test(
    'rejects calls with tools disabled and contradictory answer envelopes',
    () {
      const calls = [
        {'name': 'test', 'arguments': '{}'},
      ];
      expect(
        () =>
            agentEvents({'kind': 'tool_calls', 'text': '', 'calls': calls}, []),
        throwsA(isA<ProviderError>()),
      );
      expect(
        () => agentEvents({
          'kind': 'answer',
          'text': 'answer',
          'calls': calls,
        }, tools),
        throwsA(isA<ProviderError>()),
      );
    },
  );
  test(
    'assigns fresh call IDs for successive rounds and enforces the call limit',
    () {
      const reply = {
        'kind': 'tool_calls',
        'text': '',
        'calls': [
          {'name': 'test', 'arguments': '{}'},
        ],
      };
      final one = agentEvents(reply, tools).whereType<ToolCallStart>().single;
      final two = agentEvents(reply, tools).whereType<ToolCallStart>().single;
      expect(one.id, isNot(two.id));
      expect(
        () => agentEvents({
          'kind': 'tool_calls',
          'text': '',
          'calls': List.filled(9, const {'name': 'test', 'arguments': '{}'}),
        }, tools),
        throwsA(isA<ProviderError>()),
      );
    },
  );
}
