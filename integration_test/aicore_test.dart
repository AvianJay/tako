// Real Android AICore checks, using only synthetic prompts and a minimal UI.
// Run with: flutter test integration_test/aicore_test.dart --flavor full -d <device>
// Optionally add --dart-define=AICORE_MODEL=aicore:gemini-nano-preview
// (or aicore:gemini-nano) to require one route to be ready and test only it.
// The native service reports the actual base model in the STATUS output.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/on_device/on_device_capability.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/platform/android/aicore_on_device.dart';

const _selectedModel = String.fromEnvironment('AICORE_MODEL');
const _generationTimeout = Duration(minutes: 2);

ChatRequest _request({required bool structured}) => ChatRequest(
  systemPrompt:
      'Answer the user briefly. Do not request any tools. '
      'If a structured response is required, return kind="answer", '
      'the greeting as text, and calls=[].',
  messages: [
    ChatMessage(
      id: 'aicore-fixture-user',
      conversationId: 'aicore-fixture',
      role: MessageRole.user,
      createdAt: DateTime.utc(2026),
      content: const [TextBlock('Say hello in one short sentence.')],
    ),
  ],
  maxTokens: 256,
  // A declaration selects the native typed-output path. There is deliberately
  // no ToolExecutor, app controller, database, or provider fallback here.
  tools: structured
      ? const [
          ToolDefinition(
            name: 'fixture_unused',
            description: 'Unused test fixture. Never request this tool.',
            schema: {'type': 'object', 'properties': <String, Object?>{}},
          ),
        ]
      : const [],
);

Future<List<ProviderEvent>> _generate(
  AicoreOnDevice engine,
  LocalModel model, {
  required bool structured,
}) async {
  final cancel = CancelToken();
  try {
    return await engine
        .generate(
          ProviderConfig(
            id: 'aicore-fixture',
            displayName: model.displayName,
            apiType: ApiType.onDevice,
            baseUrl: '',
            model: model.id,
            capabilities: model.profile().capabilities,
            maxOutputTokens: 256,
          ),
          _request(structured: structured),
          cancel: cancel,
        )
        .toList()
        .timeout(
          _generationTimeout,
          onTimeout: () {
            cancel.cancel();
            throw TestFailure(
              '${model.id}: ${structured ? 'structured' : 'text'} '
              'generation exceeded $_generationTimeout.',
            );
          },
        );
  } finally {
    cancel.cancel();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const models = [aicoreModel, aicorePreviewModel];
  if (_selectedModel.isNotEmpty &&
      !models.any((model) => model.id == _selectedModel)) {
    throw ArgumentError.value(
      _selectedModel,
      'AICORE_MODEL',
      'Use ${models.map((model) => model.id).join(' or ')}.',
    );
  }

  for (final candidate in models) {
    if (_selectedModel.isNotEmpty && candidate.id != _selectedModel) continue;
    for (final structured in [false, true]) {
      final mode = structured ? 'structured answer' : 'text';
      testWidgets(
        '${candidate.id} generates $mode through native Android AICore',
        (tester) async {
          if (!Platform.isAndroid) {
            markTestSkipped('AICore integration tests require Android.');
            return;
          }
          // Keeping the Activity visible is required by the ML Kit Prompt API.
          await tester.pumpWidget(
            const Directionality(
              textDirection: TextDirection.ltr,
              child: Center(child: Text('AICore native integration test')),
            ),
          );
          await tester.pump();
          // The test binding resets lifecycleState to null between tests even
          // while the native Activity stays resumed. AICore enforces foreground
          // access itself; do not mistake that binding reset for a background app.

          final engine = AicoreOnDevice();
          addTearDown(() async {
            try {
              if (engine.isAvailable) {
                await engine.unload().timeout(const Duration(seconds: 10));
              }
            } finally {
              engine.dispose();
            }
          });
          await engine.refresh().timeout(const Duration(seconds: 45));
          final status = engine.systemModelStatuses.singleWhere(
            (status) => status.model.id == candidate.id,
          );
          final model = status.model;
          debugPrint(
            'AICORE STATUS ${model.id}: ${model.displayName}; '
            'state=${status.state.name}; '
            'structured=${model.profile().capabilities.tools}; '
            'reason=${status.error ?? 'none'}',
          );
          if (status.state != SystemModelState.ready) {
            final reason =
                '${model.id} is ${status.state.name} '
                '(${status.error ?? 'not ready'}). '
                'This test only runs models already ready in AICore.';
            if (_selectedModel.isNotEmpty) fail(reason);
            markTestSkipped(reason);
            return;
          }
          if (structured && !model.profile().capabilities.tools) {
            markTestSkipped('${model.id} does not support structured output.');
            return;
          }

          final events = await _generate(engine, model, structured: structured);
          expect(
            events.whereType<ProviderError>().map((event) => event.code),
            isEmpty,
            reason: '${model.id} $mode failed in the native AICore path.',
          );
          expect(events.whereType<ToolCallStart>(), isEmpty);
          expect(events.whereType<ToolCallArgsDelta>(), isEmpty);
          expect(events.whereType<ToolCallEnd>(), isEmpty);
          final reply = events.whereType<TextDelta>().map((e) => e.text).join();
          expect(
            reply.trim(),
            isNotEmpty,
            reason: '${model.id} $mode was empty.',
          );
          expect(events.whereType<Done>(), hasLength(1));
          expect(events.whereType<Done>().single.stopReason, 'stop');
          expect(engine.loadedModel, model.id);
          expect(engine.loadingModel, isNull);
          debugPrint('AICORE PASS ${model.id}: $mode (${reply.length} chars)');
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );
    }
  }
}
