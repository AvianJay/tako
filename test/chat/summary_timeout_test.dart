import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/context_compaction.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/providers/providers.dart';

class _SummaryAdapter implements ProviderAdapter {
  final streams = <StreamController<ProviderEvent>>[];
  final requests = <ChatRequest>[];
  @override
  Stream<ProviderEvent> send(
    ChatRequest request, {
    required CancelToken cancel,
  }) {
    requests.add(request);
    final stream = StreamController<ProviderEvent>();
    streams.add(stream);
    return stream.stream;
  }

  @override
  Future<List<ModelInfo>> listModels({CancelToken? cancel}) async => [];
}

Future<String> _summarize(
  _SummaryAdapter adapter, {
  Duration idle = const Duration(minutes: 1),
}) {
  final message = ChatMessage(
    id: 'old',
    conversationId: 'chat',
    role: MessageRole.user,
    content: [TextBlock('detail ' * 350)],
    createdAt: DateTime.utc(2026),
  );
  return summarizeContext(
    adapterFor: () async => adapter,
    resumeAt: message,
    history: [message],
    previous: null,
    contextWindow: 800,
    maxOutputTokens: 80,
    idleTimeout: idle,
    cancel: CancelToken(),
  );
}

void main() {
  testWidgets(
    'summary idle timeout renews on progress across a multi-minute batch',
    (tester) async {
      final adapter = _SummaryAdapter();
      final result = _summarize(adapter);
      await tester.pump();
      // Each chunk runs for 100 simulated seconds but never stalls for a minute.
      for (var i = 0; i < adapter.streams.length; i++) {
        final stream = adapter.streams[i];
        await tester.pump(const Duration(seconds: 50));
        stream.add(const TextDelta('complete summary'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 50));
        stream.add(const Done('stop'));
        await stream.close();
        await tester.pump();
      }
      expect(await result, 'complete summary');
      expect(adapter.streams.length, greaterThan(1));
      expect(
        adapter.requests.every(
          (r) => r.responseStartTimeout == const Duration(minutes: 1),
        ),
        isTrue,
      );
    },
  );

  test(
    'a stalled transport is cancelled and reports a distinct timeout',
    () async {
      final adapter = _SummaryAdapter();
      final result = _summarize(
        adapter,
        idle: const Duration(milliseconds: 100),
      );
      await Future<void>.delayed(Duration.zero);
      final stream = adapter.streams.single;
      stream.add(const TextDelta('partial'));
      await expectLater(
        result,
        throwsA(
          isA<ContextCompactionFailed>().having(
            (e) => e.code,
            'code',
            'contextCompactionTimeout',
          ),
        ),
      );
      expect(stream.hasListener, isFalse);
      await stream.close();
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );
}
