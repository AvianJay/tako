import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/prompt/context_budget.dart';
import 'package:tako/core/prompt/context_envelope.dart';
import 'package:tako/core/prompt/prompt_builder.dart';

ChatMessage message(String id, MessageRole role, List<ContentBlock> content) =>
    ChatMessage(
      id: id,
      conversationId: 'c',
      role: role,
      content: content,
      createdAt: DateTime.utc(2026),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('permission instructions match the selected modes', () async {
    final builder = PromptBuilder(
      await rootBundle.loadString('assets/prompts/system_prompt.md'),
    );
    final defaults = builder.render({'screen_delegate': true});
    expect(defaults, isNot(contains('Full permissions are enabled')));
    expect(defaults, isNot(contains('user enabled skipping')));
    expect(defaults, contains('Per-tool ask/deny rules still apply'));
    final automatic = builder.render({
      'screen_delegate': true,
      'full_permissions': true,
      'skip_high_risk_confirmations': true,
    });
    expect(automatic, contains('Full permissions are enabled'));
    expect(automatic, contains('user enabled skipping'));
    expect(automatic, contains('Do not ask the user to navigate manually'));
    expect(automatic, contains('uncertain mutation outcome'));
  });

  test('envelope captures explicit timezone, optional values and long gap', () {
    final now = DateTime.utc(2026, 10, 9, 17, 31);
    expect(
      ContextEnvelope.build(
        now: now,
        previousMessageAt: now.subtract(const Duration(days: 2, hours: 3)),
        timezoneOffsetMinutes: 480,
        batteryPercent: 54,
        network: 'wifi',
        foregroundApp: 'com.example.app',
      ),
      '<ctx time="2026-10-10 Sat 01:31 +08:00" since_last="2d 3h" battery="54%" net="wifi" app="com.example.app"/>',
    );
  });

  test(
    'since_last starts at exactly thirty minutes; absent state is omitted',
    () {
      final now = DateTime.utc(2026, 1, 1);
      final recent = ContextEnvelope.build(
        now: now,
        previousMessageAt: now.subtract(
          const Duration(minutes: 29, seconds: 59),
        ),
        timezoneOffsetMinutes: -210,
      );
      expect(recent, '<ctx time="2025-12-31 Wed 20:30 -03:30"/>');
      expect(
        ContextEnvelope.build(
          now: now,
          previousMessageAt: now.subtract(const Duration(minutes: 30)),
        ),
        contains('since_last="30m"'),
      );
      expect(
        ContextEnvelope.build(
          now: now,
          previousMessageAt: now.add(const Duration(days: 1)),
        ),
        isNot(contains('since_last')),
      );
    },
  );

  test('envelope escapes attributes and always occupies one line', () {
    final envelope = ContextEnvelope.build(
      now: DateTime.utc(2026),
      foregroundApp: 'a"/><bad>&\n',
    );
    expect(envelope, contains('a&quot;/&gt;&lt;bad&gt;&amp;&#10;'));
    expect(envelope.split('\n'), hasLength(1));
  });

  test('Mustache flags and plain prompt values render without HTML escaping', () {
    final builder = PromptBuilder(
      '{{app_name}} {{#memory}}memory{{/memory}}{{^memory}}none{{/memory}} {{user_notes}}',
    );
    final variables = <String, Object?>{'user_notes': 'x < y & z'};
    final frozen = builder.render(variables);
    variables['memory'] = true;
    expect(frozen, 'Tako none x < y & z');
    expect(builder.render(variables), 'Tako memory x < y & z');
  });

  test(
    'provided template renders with optional capabilities disabled',
    () async {
      final template = await rootBundle.loadString(
        'assets/prompts/system_prompt.md',
      );
      final prompt = PromptBuilder(template).render({
        'provider_name': 'Example',
        'platform': 'Android',
        'os_version': 'unknown',
        'device_model': 'unknown',
      });
      expect(prompt, contains('You are Tako'));
      expect(prompt, contains('You run on Example'));
      expect(prompt, contains('## Formatting'));
      expect(prompt, isNot(contains('## Memory')));
      expect(prompt, isNot(contains('{{')));
    },
  );

  test('visual formats are explained unless the engine is built in', () async {
    final template = await rootBundle.loadString(
      'assets/prompts/system_prompt.md',
    );
    final builder = PromptBuilder(template);
    final visuals = builder.render({});
    expect(visuals, contains('```chart'));
    expect(visuals, contains('```mermaid'));
    expect(visuals, contains('```cards'));
    expect(visuals, contains('> [!NOTE]'));
    expect(visuals, isNot(contains('{{')));
    final plain = builder.render({'visuals': false});
    expect(plain, contains('## Formatting'));
    expect(plain, isNot(contains('```chart')));
    expect(plain, isNot(contains('[!NOTE]')));
    expect(builder.render({'markdown': false}), isNot(contains('```chart')));
  });

  test(
    'empty strings hide their sections, as the template table says',
    () async {
      final template = await rootBundle.loadString(
        'assets/prompts/system_prompt.md',
      );
      final builder = PromptBuilder(template);
      final empty = builder.render({
        'memory': true,
        'memory_profile': '',
        'user_notes': ' ',
        'browser': true,
      });
      expect(empty, contains('## Memory'));
      expect(empty, isNot(contains('What you know about the user')));
      expect(empty, isNot(contains('## Notes from the user')));
      expect(empty, contains('## Built-in browser'));
      final filled = builder.render({
        'memory': true,
        'memory_profile': '- Name is Alex',
        'user_notes': 'Preferred name: Alex',
      });
      expect(filled, contains('What you know about the user:\n- Name is Alex'));
      expect(filled, contains('## Notes from the user'));
      expect(filled, contains('Preferred name: Alex'));
    },
  );

  test(
    'without memory tools the pinned profile has a section of its own',
    () async {
      final template = await rootBundle.loadString(
        'assets/prompts/system_prompt.md',
      );
      final builder = PromptBuilder(template);
      String render(Map<String, Object?> values) => builder.render({
        'platform': 'Android',
        'web_search': true,
        ...values,
      });
      final withoutTools = render({
        'memory': false,
        'memory_profile': '- Name is Alex',
      });
      expect(withoutTools, isNot(contains('## Memory')));
      expect(withoutTools, isNot(contains('memory_search')));
      expect(
        withoutTools,
        contains(
          '## About the user\n'
          "From the user's saved memory, which they can view and edit:\n"
          '- Name is Alex\n',
        ),
      );
      // With tools the memory section is unchanged and holds the profile.
      final withTools = render({
        'memory': true,
        'memory_profile': '- Name is Alex',
      });
      expect(withTools, isNot(contains('## About the user')));
      expect(
        withTools,
        contains('What you know about the user:\n- Name is Alex'),
      );
      // An empty profile adds nothing, and the layout around it is unchanged.
      expect(
        render({'memory': false, 'memory_profile': ''}),
        render({'memory': false}),
      );
      expect(
        render({'memory': false, 'memory_profile': ''}),
        isNot(contains('About the user')),
      );
    },
  );

  test(
    'budget replaces old tool output without touching persistent originals',
    () {
      final messages = [
        message('u1', MessageRole.user, const [TextBlock('first')]),
        message('call', MessageRole.assistant, const [
          ToolCallBlock(id: 't', name: 'read', arguments: '{}'),
        ]),
        message('result', MessageRole.tool, [
          ToolResultBlock(
            toolCallId: 't',
            toolName: 'read',
            content: 'x' * 6000,
          ),
        ]),
        message('u2', MessageRole.user, const [TextBlock('next')]),
      ];
      final result = ContextBudget.trim(
        systemPrompt: 'system',
        messages: messages,
        contextWindow: 500,
        reserveOutputTokens: 50,
      );
      expect(result.wasTrimmed, isTrue);
      expect(result.exceedsBudget, isFalse);
      expect(result.removedToolOutputs, 1);
      expect(result.removedMessages, 0);
      expect(
        (result.messages[2].content.single as ToolResultBlock).content,
        '[older tool output removed]',
      );
      expect(
        (messages[2].content.single as ToolResultBlock).content.length,
        6000,
      );
    },
  );

  test('budget drops whole turns and preserves newest oversized turn', () {
    final messages = [
      message('u1', MessageRole.user, [TextBlock('x' * 900)]),
      message('a1', MessageRole.assistant, [TextBlock('x' * 900)]),
      message('u2', MessageRole.user, const [TextBlock('next')]),
    ];
    final result = ContextBudget.trim(
      systemPrompt: 'system',
      messages: messages,
      contextWindow: 100,
      reserveOutputTokens: 10,
    );
    expect(result.messages.map((m) => m.id), ['u2']);
    expect(result.removedMessages, 2);
    expect(result.exceedsBudget, isFalse);
    final oversized = ContextBudget.trim(
      systemPrompt: 'system',
      messages: [messages.first],
      contextWindow: 100,
      reserveOutputTokens: 10,
    );
    expect(oversized.messages.single.id, 'u1');
    expect(oversized.exceedsBudget, isTrue);
  });
}
