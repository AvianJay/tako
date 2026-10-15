import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/conversation_tree.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/ui/chat/chat_timeline.dart';

ChatMessage node(
  String id, {
  String? parent,
  MessageRole role = MessageRole.assistant,
  List<ContentBlock> blocks = const [],
  MessageStatus status = MessageStatus.done,
  String provider = 'provider',
  String model = 'model',
  DateTime? at,
}) => ChatMessage(
  id: id,
  conversationId: 'chat',
  parentId: parent,
  role: role,
  content: blocks,
  createdAt: at ?? DateTime.utc(2026, 10, 12, 10),
  providerId: provider,
  model: model,
  status: status,
);

ToolCallBlock call(String id, {String name = 'web_search'}) =>
    ToolCallBlock(id: id, name: name, arguments: '{}');

ToolResultBlock result(
  String id,
  String content, {
  String name = 'web_search',
}) => ToolResultBlock(toolCallId: id, toolName: name, content: content);

void main() {
  group('generated images', () {
    const image = ImageBlock(
      path: 'attachments/abc123-generated.png',
      mimeType: 'image/png',
    );
    final assistant = node(
      'a',
      blocks: [call('image-call', name: 'generate_image')],
    );
    final receipt = node(
      'r',
      parent: 'a',
      role: MessageRole.tool,
      blocks: [
        const ToolResultBlock(
          toolCallId: 'image-call',
          toolName: 'generate_image',
          content: '{}',
          attachments: [image],
        ),
      ],
    );
    List<AssistantSegment> turn(
      String reply, {
      MessageStatus status = MessageStatus.done,
    }) => buildAssistantSegments([
      assistant,
      receipt,
      node('a2', parent: 'r', status: status, blocks: [TextBlock(reply)]),
    ]);
    List<ContentBlock> appended(List<AssistantSegment> segments) => [
      for (final segment in segments.whereType<AssistantContentSegment>().where(
        (s) => s.message.id == 'r',
      ))
        ...segment.blocks,
    ];

    test('unplaced images follow the reply, not the tool receipt', () {
      final segments = turn('Here it is.');
      expect(segments.map((segment) => segment.runtimeType), [
        ToolRunSegment,
        AssistantContentSegment,
        AssistantContentSegment,
      ]);
      expect((segments[1] as AssistantContentSegment).message.id, 'a2');
      expect((segments.last as AssistantContentSegment).blocks.single, image);
      expect(generatedImages([assistant, receipt]), [image]);
      // Before the reply arrives the image still shows, after the run.
      final waiting = buildAssistantSegments([assistant, receipt]);
      expect(waiting.first, isA<ToolRunSegment>());
      expect((waiting.last as AssistantContentSegment).blocks.single, image);
      final unrelated = node(
        'other',
        parent: 'different',
        role: MessageRole.tool,
        blocks: receipt.content,
      );
      expect(
        buildAssistantSegments([
          assistant,
          unrelated,
        ]).whereType<AssistantContentSegment>(),
        isEmpty,
      );
    });

    test('a generated image does not split consecutive tool steps', () {
      final segments = buildAssistantSegments([
        assistant,
        receipt,
        node('a2', parent: 'r', blocks: [call('c2')]),
      ]);
      expect(
        (segments.first as ToolRunSegment).steps.map((step) => step.call.id),
        ['image-call', 'c2'],
      );
      expect(segments.last, isA<AssistantContentSegment>());
    });

    test('tags, Markdown and path variants place the image inline', () {
      for (final reply in [
        '<image src="attachments/abc123-generated.png"/>',
        '<image src="attachments/abc123-generated.png">',
        "<IMAGE SRC='attachments/abc123-generated.png'></image>",
        '<image path="./attachments/abc123-generated.png" alt="Bird"/>',
        '<file path="attachments/abc123-generated.png"/>',
        '![Bird](attachments/abc123-generated.png)',
        r'<image src="\attachments\abc123-generated.png"/>',
        '<image src="file:///attachments/abc123-generated.png"/>',
        '<image src="abc123-generated.png"/>',
        '<image src="workspace/attachments/abc123-generated.png"/>',
      ]) {
        expect(appended(turn('Done:\n\n$reply')), isEmpty, reason: reply);
      }
    });

    test('code, unfinished, remote and unknown references fall back', () {
      for (final reply in [
        '```\n<image src="attachments/abc123-generated.png"/>\n```',
        // Cards draw their text without tags, so the image still follows.
        '```cards\n[{"title": "Bird", "text": '
            r'"<image src=\"attachments/abc123-generated.png\"/>"}]'
            '\n```',
        '`<image src="attachments/abc123-generated.png"/>`',
        '<image src="https://example.com/abc123-generated.png"/>',
        '<image src="attachments/other.png"/>',
        '<image src="generated.png"/>',
        '<image src=attachments/abc123-generated.png/>',
      ]) {
        expect(appended(turn(reply)), [image], reason: reply);
      }
      expect(
        appended(
          turn(
            '<image src="attachments/abc123-generated.png',
            status: MessageStatus.streaming,
          ),
        ),
        [image],
      );
    });

    test('a file name matches only when it is unambiguous', () {
      const twin = ImageBlock(
        path: 'other/abc123-generated.png',
        mimeType: 'image/png',
      );
      expect(placedGeneratedImage('abc123-generated.png', [image]), image);
      expect(
        placedGeneratedImage('abc123-generated.png', [image, twin]),
        isNull,
      );
      expect(
        placedGeneratedImage('other/abc123-generated.png', [image, twin]),
        twin,
      );
      expect(placedGeneratedImage('  ', [image]), isNull);
    });
  });

  test('one assistant turn contains tool rounds and its final answer', () {
    final messages = [
      node('u1', role: MessageRole.user),
      node('a1', parent: 'u1', blocks: [call('c1')]),
      node('r1', parent: 'a1', role: MessageRole.tool),
      node('a2', parent: 'r1', blocks: [call('c2')]),
      node('r2', parent: 'a2', role: MessageRole.tool),
      node('a3', parent: 'r2', blocks: [const TextBlock('Answer')]),
      node('u2', parent: 'a3', role: MessageRole.user),
      node('a4', parent: 'u2', blocks: [const TextBlock('Next answer')]),
    ];
    final entries = buildChatTimeline(messages);
    expect(entries.map((entry) => entry.isAssistantTurn), [
      false,
      true,
      false,
      true,
    ]);
    expect(entries[1].messages.map((message) => message.id), [
      'a1',
      'r1',
      'a2',
      'r2',
      'a3',
    ]);
    expect(entries[1].anchor.id, 'a1');
    expect(entries[1].lastAssistant!.id, 'a3');
    expect(entries.first.lastAssistant, isNull);
  });

  test(
    'provider, model, local day and disconnected paths start a new header',
    () {
      for (final next in [
        node('a2', parent: 'r1', provider: 'different'),
        node('a2', parent: 'r1', model: 'different'),
        node('a2', parent: 'r1', at: DateTime.utc(2026, 10, 13)),
        node('a2', parent: 'off-branch'),
      ]) {
        final entries = buildChatTimeline([
          node('a1'),
          node('r1', parent: 'a1', role: MessageRole.tool),
          next,
        ]);
        expect(entries, hasLength(2));
        expect(entries.first.messages.map((message) => message.id), [
          'a1',
          'r1',
        ]);
        expect(entries.last.anchor.id, 'a2');
      }
    },
  );

  test(
    'midnight receipts remain attached and orphan tools leave no blank rows',
    () {
      final entries = buildChatTimeline([
        node('orphan', role: MessageRole.tool),
        node('a1', at: DateTime.utc(2026, 10, 12, 23, 59)),
        node(
          'r1',
          parent: 'a1',
          role: MessageRole.tool,
          at: DateTime.utc(2026, 10, 13),
        ),
        node('a2', parent: 'r1', at: DateTime.utc(2026, 10, 13)),
        node('orphan2', parent: 'not-a2', role: MessageRole.tool),
      ]);
      expect(entries, hasLength(2));
      expect(entries.first.messages.map((message) => message.id), ['a1', 'r1']);
      expect(entries.last.messages.map((message) => message.id), ['a2']);
    },
  );

  test('tool-only rounds combine across receipts and hidden reasoning', () {
    final messages = [
      node(
        'a1',
        blocks: [
          const ReasoningBlock(text: 'First plan'),
          call('c1'),
          call('c2'),
        ],
      ),
      node(
        'r1',
        parent: 'a1',
        role: MessageRole.tool,
        blocks: [result('c1', 'one'), result('c2', 'two')],
      ),
      node(
        'a2',
        parent: 'r1',
        blocks: [
          const ReasoningBlock(text: 'Next plan'),
          call('c3'),
        ],
      ),
      node(
        'r2',
        parent: 'a2',
        role: MessageRole.tool,
        blocks: [result('c3', 'three')],
      ),
      node('a3', parent: 'r2', blocks: [const TextBlock('Finished')]),
    ];
    final segments = buildAssistantSegments(messages);
    expect(segments, hasLength(2));
    final run = segments.first as ToolRunSegment;
    expect(run.steps.map((step) => step.call.id), ['c1', 'c2', 'c3']);
    expect(run.steps.map((step) => step.result!.content), [
      'one',
      'two',
      'three',
    ]);
    expect(
      run.steps.first.message.content.whereType<ReasoningBlock>().single.text,
      'First plan',
    );
    expect((segments.last as AssistantContentSegment).message.id, 'a3');
  });

  test(
    'visible output splits runs in original order, including one message',
    () {
      const picture = ImageBlock(
        path: 'attachments/a.png',
        mimeType: 'image/png',
      );
      const document = FileBlock(
        path: 'attachments/a.txt',
        name: 'a.txt',
        mimeType: 'text/plain',
      );
      final segments = buildAssistantSegments([
        node(
          'a1',
          blocks: [
            const TextBlock('Before'),
            call('c1'),
            call('c2'),
            const TextBlock('Between'),
            call('c3'),
            picture,
            call('c4'),
            document,
            call('c5'),
            const TextBlock('After'),
          ],
        ),
      ]);
      expect(segments.map((segment) => segment.runtimeType), [
        AssistantContentSegment,
        ToolRunSegment,
        AssistantContentSegment,
        ToolRunSegment,
        AssistantContentSegment,
        ToolRunSegment,
        AssistantContentSegment,
        ToolRunSegment,
        AssistantContentSegment,
      ]);
      expect(
        segments.whereType<ToolRunSegment>().map(
          (run) => run.steps.map((step) => step.call.id).toList(),
        ),
        [
          ['c1', 'c2'],
          ['c3'],
          ['c4'],
          ['c5'],
        ],
      );
      expect(
        segments.whereType<AssistantContentSegment>().expand(
          (segment) => segment.blocks,
        ),
        [
          const TextBlock('Before'),
          const TextBlock('Between'),
          picture,
          document,
          const TextBlock('After'),
        ],
      );
    },
  );

  test('tool-round reasoning stays in details while text keeps its order', () {
    const thought = ReasoningBlock(text: 'Considering the result');
    final segments = buildAssistantSegments([
      node(
        'a1',
        blocks: [
          call('c1'),
          thought,
          const TextBlock('Explanation'),
          call('c2'),
        ],
      ),
    ]);
    expect(segments, hasLength(3));
    expect((segments[1] as AssistantContentSegment).blocks, [
      const TextBlock('Explanation'),
    ]);
    expect(
      (segments.first as ToolRunSegment).steps.single.message.content,
      contains(thought),
    );
  });

  test(
    'text arriving after a later call does not retroactively split its run',
    () {
      final messages = [
        node('a1', blocks: [call('c1')]),
        node(
          'r1',
          parent: 'a1',
          role: MessageRole.tool,
          blocks: [result('c1', 'first')],
        ),
        node(
          'a2',
          parent: 'r1',
          blocks: [
            const ReasoningBlock(text: 'Next step'),
            call('c2'),
          ],
        ),
      ];
      final before = buildAssistantSegments(messages).single as ToolRunSegment;
      final after = buildAssistantSegments([
        ...messages.take(2),
        messages.last.copyWith(
          content: [
            ...messages.last.content,
            const TextBlock('Here is the answer'),
          ],
        ),
      ]);
      expect(after, hasLength(2));
      final run = after.first as ToolRunSegment;
      expect(run.id, before.id);
      expect(run.steps.map((step) => step.call.id), ['c1', 'c2']);
      expect((after.last as AssistantContentSegment).blocks, [
        const TextBlock('Here is the answer'),
      ]);
    },
  );

  test('reused call IDs resolve only to their actual parent receipt', () {
    final segments = buildAssistantSegments([
      node('a1', blocks: [call('reused')]),
      node(
        'r1',
        parent: 'a1',
        role: MessageRole.tool,
        blocks: [result('reused', 'first')],
      ),
      node('a2', parent: 'r1', blocks: [call('reused')]),
      node(
        'r2',
        parent: 'a2',
        role: MessageRole.tool,
        blocks: [result('reused', 'second')],
      ),
    ]);
    final run = segments.single as ToolRunSegment;
    expect(run.steps.map((step) => step.result!.content), ['first', 'second']);
  });

  test('off-branch receipts never appear in a visible tool run', () {
    final assistant = node('a1', blocks: [call('c1')]);
    final selectedReceipt = node(
      'r1',
      parent: 'a1',
      role: MessageRole.tool,
      blocks: [result('c1', 'selected')],
    );
    final alternateReceipt = node(
      'r2',
      parent: 'a1',
      role: MessageRole.tool,
      blocks: [result('c1', 'alternate')],
    );
    final tree = ConversationTree([
      assistant,
      selectedReceipt,
      alternateReceipt,
    ]);
    final selected =
        buildAssistantSegments(tree.pathTo('r1')).single as ToolRunSegment;
    expect(selected.steps.single.result!.content, 'selected');
    final beforeReceipt =
        buildAssistantSegments(tree.pathTo('a1')).single as ToolRunSegment;
    expect(beforeReceipt.steps.single.result, isNull);
    final wrongEdge =
        buildAssistantSegments([
              assistant,
              node(
                'wrong',
                parent: 'different-assistant',
                role: MessageRole.tool,
                blocks: [result('c1', 'wrong')],
              ),
            ]).single
            as ToolRunSegment;
    expect(wrongEdge.steps.single.result, isNull);
  });

  test('ambiguous or mislabeled receipts do not confirm a call', () {
    for (final receiptBlocks in [
      [result('c1', 'wrong tool', name: 'file_read')],
      [result('c1', 'one'), result('c1', 'two')],
    ]) {
      final run =
          buildAssistantSegments([
                node('a1', blocks: [call('c1')]),
                node(
                  'r1',
                  parent: 'a1',
                  role: MessageRole.tool,
                  blocks: receiptBlocks,
                ),
              ]).single
              as ToolRunSegment;
      expect(run.steps.single.result, isNull);
    }
    final duplicateCalls =
        buildAssistantSegments([
              node('a1', blocks: [call('c1'), call('c1')]),
              node(
                'r1',
                parent: 'a1',
                role: MessageRole.tool,
                blocks: [result('c1', 'ambiguous')],
              ),
            ]).single
            as ToolRunSegment;
    expect(duplicateCalls.steps.every((step) => step.result == null), isTrue);
  });

  test(
    'empty interrupted or streaming messages retain their status anchor',
    () {
      for (final status in [
        MessageStatus.streaming,
        MessageStatus.error,
        MessageStatus.stopped,
      ]) {
        final assistant = node('a1', status: status);
        final entry = buildChatTimeline([assistant]).single;
        final segment =
            buildAssistantSegments(entry.messages).single
                as AssistantContentSegment;
        expect(segment.message, same(assistant));
        expect(segment.blocks, isEmpty);
      }
      const reasoning = ReasoningBlock(text: 'Still thinking');
      final segment =
          buildAssistantSegments([
                node(
                  'a1',
                  status: MessageStatus.streaming,
                  blocks: [reasoning],
                ),
              ]).single
              as AssistantContentSegment;
      expect(segment.blocks, [reasoning]);
    },
  );

  test('opaque state and blank tool-round text do not split a run', () {
    final run =
        buildAssistantSegments([
              node(
                'a1',
                blocks: [
                  call('c1'),
                  const ProviderStateBlock(
                    sourceApi: 'responses',
                    promptHash: 'hash',
                    content: [],
                  ),
                  const TextBlock('  \n'),
                  const ReasoningBlock(text: '', encryptedContent: 'opaque'),
                  call('c2'),
                ],
              ),
            ]).single
            as ToolRunSegment;
    expect(run.steps.map((step) => step.call.id), ['c1', 'c2']);
  });

  test(
    'run identity survives streamed calls, receipts and additional rounds',
    () {
      final first = node(
        'a1',
        status: MessageStatus.streaming,
        blocks: [call('c1')],
      );
      final before = buildAssistantSegments([first]).single as ToolRunSegment;
      final after =
          buildAssistantSegments([
                first.copyWith(
                  status: MessageStatus.done,
                  content: [call('c1'), call('c2')],
                ),
                node(
                  'r1',
                  parent: 'a1',
                  role: MessageRole.tool,
                  blocks: [result('c1', 'one'), result('c2', 'two')],
                ),
                node('a2', parent: 'r1', blocks: [call('c3')]),
              ]).single
              as ToolRunSegment;
      expect(after.id, before.id);
      final split = buildAssistantSegments([
        first.copyWith(
          content: [call('c1'), const TextBlock('Update'), call('c1')],
        ),
      ]).whereType<ToolRunSegment>().toList();
      expect(split[0].id, isNot(split[1].id));
    },
  );

  test('presentation collections cannot mutate stored message lists', () {
    final messages = [
      node('a1', blocks: [call('c1')]),
    ];
    final entries = buildChatTimeline(messages);
    final segments = buildAssistantSegments(entries.single.messages);
    messages.clear();
    expect(entries.single.messages, hasLength(1));
    expect(entries.clear, throwsUnsupportedError);
    expect(() => entries.single.messages.clear(), throwsUnsupportedError);
    expect(
      () => (segments.single as ToolRunSegment).steps.clear(),
      throwsUnsupportedError,
    );
    expect(entries.single.anchor.content, hasLength(1));
  });
}
