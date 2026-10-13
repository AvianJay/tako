import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/app/app_controller.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/data/database.dart';

import 'app_controller_test.dart' show FakeServices, config;

class _Adapter implements ProviderAdapter {
  final titles = <ChatRequest>[];
  final replies = <ChatRequest>[];
  Completer<void>? pending;
  bool fail = false;

  @override
  Future<List<ModelInfo>> listModels({CancelToken? cancel}) async => [];

  @override
  Stream<ProviderEvent> send(
    ChatRequest request, {
    required CancelToken cancel,
  }) async* {
    if (!request.systemPrompt.startsWith('Write a short title')) {
      replies.add(request);
      yield const TextDelta('An answer');
      yield const Done('stop');
      return;
    }
    titles.add(request);
    if (pending != null) await cancel.bind(pending!.future);
    if (fail) {
      yield const ProviderError('Unavailable');
      return;
    }
    yield const TextDelta('「旅行規劃」\nExtra explanation');
    yield const Done('stop');
  }
}

Future<void> _settled(AppController app) async {
  for (var i = 0; app.isGeneratingTitle && i < 200; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(app.isGeneratingTitle, isFalse);
}

void main() {
  late AppDatabase database;
  late AppController app;
  late _Adapter adapter;
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    adapter = _Adapter();
    app = AppController(
      database: database,
      services: FakeServices(),
      promptTemplate: 'Private system context',
      adapterFactory: (_, _, _) => adapter,
    );
    await app.initialize();
    await app.saveProvider(config());
  });
  tearDown(() async {
    app.dispose();
    await Future<void>.delayed(Duration.zero);
    await database.close();
  });

  test(
    'first reply generates an isolated title and no extra message',
    () async {
      await app.send('請幫我規劃旅行');
      await _settled(app);
      expect(app.conversation!.title, '旅行規劃');
      expect(app.visibleMessages, hasLength(2));
      expect(app.visibleMessages.last.text, 'An answer');
      final request = adapter.titles.single;
      expect(request.tools, isEmpty);
      expect(request.builtInWebSearch, isFalse);
      expect(request.messages.single.contextEnvelope, isNull);
      expect(request.messages.single.content, everyElement(isA<TextBlock>()));
      expect(request.systemPrompt, isNot(contains('Private system context')));
      await app.send('More details');
      expect(adapter.titles, hasLength(1));
      await app.generateConversationTitle();
      expect(adapter.titles, hasLength(2));
      expect(app.visibleMessages, hasLength(4));
    },
  );

  test('background title never overwrites a user rename', () async {
    adapter.pending = Completer<void>();
    await app.send('Original');
    expect(app.busy, isFalse);
    await app.renameConversation('My chosen title');
    adapter.pending!.complete();
    await _settled(app);
    expect(app.conversation!.title, 'My chosen title');
  });

  test('background title cannot restore a deleted conversation', () async {
    adapter.pending = Completer<void>();
    await app.send('Delete this');
    final id = app.conversation!.id;
    await app.deleteConversation(id);
    adapter.pending!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(await app.chats.getConversation(id), isNull);
    expect(app.conversations, isEmpty);
  });

  test('title failure preserves the response and fallback title', () async {
    adapter.fail = true;
    await app.send('Fallback title');
    await _settled(app);
    expect(app.conversation!.title, 'Fallback title');
    expect(app.errorCode, isNull);
    expect(app.visibleMessages.last.status, MessageStatus.done);
    expect(await app.generateConversationTitle(), isFalse);
  });

  test('incognito chats never request a title', () async {
    await app.newChat(incognito: true);
    await app.send('Private question');
    expect(adapter.titles, isEmpty);
    expect(await app.generateConversationTitle(), isFalse);
  });
}
