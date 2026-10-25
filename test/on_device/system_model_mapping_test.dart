import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/platform/on_device/system_model_mapping.dart';

const tools = [ToolDefinition(name: 'test', description: '', schema: {})];

List<ProviderEvent> agentEvents(
  Map<Object?, Object?> reply,
  List<ToolDefinition> tools,
) => systemModelAgentEvents(reply, tools, invalidCode: 'apple_invalid_tools');

void main() {
  test('invalid reply diagnostics contain only fixed reason labels', () {
    const privateContent = 'private-reply-name-and-arguments';
    const validCall = {'name': 'test', 'arguments': '{}'};
    const reply = {
      'kind': 'tool_calls',
      'text': privateContent,
      'calls': [validCall],
    };
    Map<String, Object?> callReply(Map<String, Object?> call) => {
      ...reply,
      'calls': [call],
    };
    final cases = <(String, Map<String, Object?>)>[
      (
        'text_type',
        {
          ...reply,
          'text': [privateContent],
        },
      ),
      ('text_size', {...reply, 'text': privateContent * 3000}),
      ('calls_type', {...reply, 'calls': privateContent}),
      ('calls_size', {...reply, 'calls': List.filled(9, validCall)}),
      ('answer_calls', {...reply, 'kind': 'answer'}),
      ('answer_blank', {'kind': 'answer', 'text': ' ', 'calls': []}),
      (
        'kind_type',
        {
          ...reply,
          'kind': [privateContent],
        },
      ),
      ('kind', {...reply, 'kind': privateContent}),
      ('empty_calls', {...reply, 'calls': []}),
      ('tools_disabled', reply),
      (
        'call_type',
        {
          ...reply,
          'calls': [privateContent],
        },
      ),
      (
        'name_type',
        callReply({
          ...validCall,
          'name': [privateContent],
        }),
      ),
      ('unknown_tool', callReply({...validCall, 'name': privateContent})),
      (
        'arguments_type',
        callReply({
          ...validCall,
          'arguments': {privateContent: true},
        }),
      ),
      (
        'arguments_size',
        callReply({...validCall, 'arguments': privateContent * 3000}),
      ),
      (
        'arguments_json',
        callReply({...validCall, 'arguments': '{$privateContent'}),
      ),
      (
        'arguments_object',
        callReply({...validCall, 'arguments': '["$privateContent"]'}),
      ),
    ];
    for (final (expectedReason, invalidReply) in cases) {
      final diagnostics = <String>[];
      expect(
        () => systemModelAgentEvents(
          invalidReply,
          expectedReason == 'tools_disabled' ? [] : tools,
          invalidCode: 'aicore_invalid_tools',
          onInvalid: diagnostics.add,
        ),
        throwsA(
          isA<ProviderError>()
              .having((e) => e.code, 'code', 'aicore_invalid_tools')
              .having(
                (e) => e.message,
                'message',
                isNot(contains(privateContent)),
              ),
        ),
        reason: expectedReason,
      );
      expect(diagnostics, [expectedReason]);
      expect(diagnostics.single, isNot(contains(privateContent)));
    }
  });

  test('valid answer and tool replies do not emit invalid diagnostics', () {
    for (final reply in [
      {'kind': 'answer', 'text': 'A reply', 'calls': []},
      {
        'kind': 'tool_calls',
        'text': '',
        'calls': [
          {'name': 'test', 'arguments': '{}'},
        ],
      },
    ]) {
      final diagnostics = <String>[];
      expect(
        systemModelAgentEvents(
          reply,
          tools,
          invalidCode: 'aicore_invalid_tools',
          onInvalid: diagnostics.add,
        ),
        isNotEmpty,
      );
      expect(diagnostics, isEmpty);
    }
  });

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
