// Real Android AICore checks, using only synthetic prompts and a minimal UI.
// Run with: flutter test integration_test/aicore_test.dart --flavor full -d <device>
// Optionally add --dart-define=AICORE_MODEL=aicore:gemini-nano-preview
// (or aicore:gemini-nano) to require one route to be ready and test only it.
// The native service reports the actual base model in the STATUS output.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/on_device/on_device_capability.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/platform/android/aicore_on_device.dart';

import '../test/on_device/real_chat_fixture.dart';

const _selectedModel = String.fromEnvironment('AICORE_MODEL');
const _generationTimeout = Duration(minutes: 2);

/// Observe shapes on the engine's own subscription without logging contents.
class _ShapeDiagnosticEvents extends EventChannel {
  const _ShapeDiagnosticEvents() : super('tw.avianjay.tako/aicore/events');

  @override
  Stream<dynamic> receiveBroadcastStream([dynamic arguments]) =>
      super.receiveBroadcastStream(arguments).map((event) {
        if (event is Map<Object?, Object?> && event['type'] == 'agent_json') {
          final json = event['json'];
          if (json is! String || json.length > 262144) {
            debugPrint('AICORE JSON SHAPE invalid_payload');
            return event;
          }
          final Object? decoded;
          try {
            decoded = jsonDecode(json);
          } on FormatException {
            debugPrint('AICORE JSON SHAPE invalid_json');
            return event;
          }
          if (decoded is! Map<String, Object?>) {
            debugPrint('AICORE JSON SHAPE non_object');
            return event;
          }
          final hasCalls = decoded.containsKey('calls');
          final calls = decoded['calls'];
          final kindKnown = switch (decoded['kind']) {
            'answer' => 'answer',
            'tool_calls' => 'tool_calls',
            _ => 'unknown',
          };
          final argumentTypes = calls is List<Object?>
              ? [
                  for (final call in calls.take(9))
                    if (call is! Map<String, Object?>)
                      'invalid_call'
                    else if (!call.containsKey('arguments'))
                      'missing'
                    else
                      _shapeType(call['arguments']),
                ]
              : const <String>[];
          debugPrint(
            'AICORE JSON SHAPE hasCalls=$hasCalls '
            'callsType=${hasCalls ? _shapeType(calls) : 'missing'} '
            'kindKnown=$kindKnown argumentTypes=$argumentTypes',
          );
        }
        return event;
      });
}

String _shapeType(Object? value) => switch (value) {
  null => 'null',
  String() => 'string',
  bool() => 'boolean',
  num() => 'number',
  List<Object?>() => 'list',
  Map<Object?, Object?>() => 'object',
  _ => 'other',
};

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
  LocalModel model,
  ChatRequest request,
) async {
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
            maxOutputTokens: request.maxTokens ?? 1024,
          ),
          request,
          cancel: cancel,
        )
        .toList()
        .timeout(
          _generationTimeout,
          onTimeout: () {
            cancel.cancel();
            throw TestFailure(
              '${model.id}: ${request.tools.isNotEmpty ? 'structured' : 'text'} '
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
    for (final scenario in const [
      (name: 'text', structured: false, userText: null, toolCall: false),
      (
        name: 'minimal structured answer',
        structured: true,
        userText: null,
        toolCall: false,
      ),
      (
        name: 'real app greeting in English',
        structured: true,
        userText: 'hi',
        toolCall: false,
      ),
      (
        name: 'real app greeting in Chinese',
        structured: true,
        userText: '你好',
        toolCall: false,
      ),
      (
        name: 'real app read-only tool request',
        structured: true,
        userText:
            'Use get_device_status now to read the current battery level. '
            'Call that tool exactly once with no arguments; do not guess '
            'the battery level or call any other tool.',
        toolCall: true,
      ),
    ]) {
      final structured = scenario.structured;
      final mode = scenario.name;
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

          final engine = AicoreOnDevice(events: const _ShapeDiagnosticEvents());
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

          final request = scenario.userText == null
              ? _request(structured: structured)
              : await realisticAicoreChatRequest(
                  promptTemplate: await rootBundle.loadString(
                    'assets/prompts/system_prompt.md',
                  ),
                  userText: scenario.userText!,
                );
          if (scenario.userText != null) {
            // Exercise the full production prompt and registry, including the
            // real user context envelope and normal 1,024-token output budget.
            expect(request.tools.length, greaterThanOrEqualTo(32));
            expect(request.maxTokens, 1024);
            expect(request.messages.single.contextEnvelope, isNotNull);
            expect(
              request.tools.map((tool) => tool.name),
              containsAll([
                'get_device_status',
                'file_read',
                'browser_read',
                'memory_search',
                'automation_save',
                'fetch_page',
              ]),
            );
          }
          final events = await _generate(engine, model, request);
          expect(
            events.whereType<ProviderError>().map((event) => event.code),
            isEmpty,
            reason: '${model.id} $mode failed in the native AICore path.',
          );
          final reply = events.whereType<TextDelta>().map((e) => e.text).join();
          if (scenario.toolCall) {
            // Inspect the proposed call only. There is no executor attached to
            // this generation, so no device data is read or action performed.
            final calls = events.whereType<ToolCallStart>().toList();
            expect(calls, hasLength(1));
            expect(calls.single.name, 'get_device_status');
            final ends = events.whereType<ToolCallEnd>().toList();
            expect(ends, hasLength(1));
            expect(ends.single.id, calls.single.id);
            final arguments = events
                .whereType<ToolCallArgsDelta>()
                .where((event) => event.id == calls.single.id)
                .map((event) => event.jsonFragment)
                .join();
            expect(jsonDecode(arguments), <String, Object?>{});
          } else {
            expect(events.whereType<ToolCallStart>(), isEmpty);
            expect(events.whereType<ToolCallArgsDelta>(), isEmpty);
            expect(events.whereType<ToolCallEnd>(), isEmpty);
            expect(
              reply.trim(),
              isNotEmpty,
              reason: '${model.id} $mode was empty.',
            );
          }
          expect(events.whereType<Done>(), hasLength(1));
          expect(
            events.whereType<Done>().single.stopReason,
            scenario.toolCall ? 'tool_calls' : 'stop',
          );
          expect(engine.loadedModel, model.id);
          expect(engine.loadingModel, isNull);
          debugPrint('AICORE PASS ${model.id}: $mode (${reply.length} chars)');
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );
    }
  }
}
