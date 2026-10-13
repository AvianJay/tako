import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/tools/tool_loop_detector.dart';

ToolCallBlock _call(String name, [String args = '{}']) => ToolCallBlock(
  id: 'different-${DateTime.now().microsecondsSinceEpoch}',
  name: name,
  arguments: args,
);
ToolResultBlock _result(String content) => ToolResultBlock(
  toolCallId: 'irrelevant',
  toolName: 'fixture',
  content: content,
);

void main() {
  test(
    'recognizes single, double and longer cycles only after three repeats',
    () {
      for (final period in [1, 2, 3, 8]) {
        final detector = ToolLoopDetector();
        for (var repeat = 0; repeat < 3; repeat++) {
          for (var step = 0; step < period; step++) {
            final call = _call('tool_$step');
            expect(detector.repeatingBefore(call), isNull);
            detector.record(call, _result('result_$step'));
          }
        }
        expect(detector.repeatingBefore(_call('tool_0'))!.period, period);
        expect(detector.repeatingBefore(_call('a_different_strategy')), isNull);
      }
    },
  );
  test('different outcomes or arguments count as progress', () {
    final detector = ToolLoopDetector();
    for (var i = 0; i < 50; i++) {
      detector.record(_call('poll'), _result('progress: $i'));
      expect(detector.repeatingBefore(_call('poll')), isNull);
    }
    for (var i = 0; i < 50; i++) {
      detector.record(_call('read', '{"page":$i}'), _result('same output'));
      expect(
        detector.repeatingBefore(_call('read', '{"page":${i + 1}}')),
        isNull,
      );
    }
  });
  test('JSON key order and display titles cannot hide a loop', () {
    final detector = ToolLoopDetector();
    detector.record(
      _call('tap', '{"id":1,"title":"Try"}'),
      _result('{"a":1,"b":2}'),
    );
    detector.record(
      _call('tap', '{"title":"Again","id":1}'),
      _result('{"b":2,"a":1}'),
    );
    detector.record(
      _call('tap', '{"id":1,"title":"Retry"}'),
      _result('{"a":1,"b":2}'),
    );
    expect(
      detector.repeatingBefore(_call('tap', '{"id":1,"title":"Next"}')),
      isNotNull,
    );
    final calendar = ToolLoopDetector();
    for (var i = 0; i < 3; i++) {
      calendar.record(
        _call('calendar_add', '{"title":"Event $i"}'),
        _result('done'),
      );
    }
    expect(
      calendar.repeatingBefore(_call('calendar_add', '{"title":"Event 3"}')),
      isNull,
    );
  });
  test('identical screenshot bytes detect a loop despite new paths', () {
    final detector = ToolLoopDetector();
    for (var i = 0; i < 3; i++) {
      detector.record(
        _call('read_screen'),
        _result('same screen'),
        attachments: [
          ImageBlock(
            path: '$i.jpg',
            mimeType: 'image/jpeg',
            data: 'same image bytes',
          ),
        ],
      );
    }
    expect(detector.repeatingBefore(_call('read_screen')), isNotNull);
    detector.record(
      _call('read_screen'),
      _result('same screen'),
      attachments: [
        const ImageBlock(
          path: 'new.jpg',
          mimeType: 'image/jpeg',
          data: 'changed image bytes',
        ),
      ],
    );
    expect(detector.repeatingBefore(_call('read_screen')), isNull);
  });
}
