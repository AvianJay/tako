import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/app/app.dart';
import 'package:tako/app/app_controller.dart';
import 'package:tako/core/on_device/gguf.dart';
import 'package:tako/core/on_device/on_device_capability.dart';
import 'package:tako/core/on_device/recommended_models.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/data/database.dart';
import 'package:tako/l10n/gen/app_localizations.dart';
import 'package:tako/platform/services.dart';
import 'package:tako/ui/settings/on_device_models_screen.dart';
import 'package:tako/ui/settings/provider_editor.dart';

import 'on_device/gguf_fixture.dart';

const _qwen = LocalModel(
  id: 'Qwen3.5-0.8B-Q4_K_M.gguf',
  sizeBytes: 532517120,
  info: GgufInfo(
    architecture: 'qwen35',
    name: 'Qwen3.5 0.8B',
    contextLength: 262144,
    chatTemplate: qwenTemplate,
  ),
);

const _nano = LocalModel.system(
  id: 'aicore:gemini-nano',
  name: 'Gemini Nano (AICore)',
  profile: ModelProfile(
    id: 'aicore:gemini-nano',
    autoDetect: true,
    capabilities: ProviderCapabilities(tools: true, contextWindow: 8192),
    maxOutputTokens: 1024,
  ),
);

class _OnDevice extends OnDeviceCapability {
  @override
  SystemModelStatus? systemModelStatus;
  SystemModelStatus? previewStatus;
  @override
  List<SystemModelStatus> get systemModelStatuses => [
    ?systemModelStatus,
    ?previewStatus,
  ];
  int preparations = 0;
  @override
  Future<void> prepareSystemModel({
    String modelId = 'aicore:gemini-nano',
  }) async {
    preparations++;
    final model = modelId == aicorePreviewModel.id
        ? LocalModel.system(
            id: modelId,
            name: aicorePreviewModel.displayName,
            profile: ModelProfile(
              id: modelId,
              capabilities: _nano.profile().capabilities,
            ),
          )
        : _nano;
    final status = SystemModelStatus(SystemModelState.ready, model: model);
    if (modelId == aicorePreviewModel.id) {
      previewStatus = status;
    } else {
      systemModelStatus = status;
    }
    models = [model, ...models];
    loadedModel = modelId;
    notifyListeners();
  }

  @override
  List<LocalModel> models = [_qwen];
  @override
  List<ModelDownload> downloads = [];
  @override
  String? loadedModel;
  @override
  String? loadingModel;
  final started = <(String, String?, int?, String?, String?)>[];
  final paused = <String>[];
  final requests = <(ProviderConfig, ChatRequest)>[];

  @override
  bool get isAvailable => true;
  @override
  int get storageBytes => _qwen.sizeBytes;
  @override
  Future<void> refresh() async {}
  @override
  Future<LocalModel?> importModel() async => null;
  @override
  Future<void> importProjector(String modelId) async {}
  @override
  Future<void> download(
    Uri url, {
    required String fileName,
    String? sha256,
    int? size,
    String? catalogId,
    String? projectorFor,
  }) async {
    started.add((fileName, sha256, size, catalogId, projectorFor));
    downloads = [
      ...downloads,
      ModelDownload(id: fileName, url: url, received: 0, total: size),
    ];
    notifyListeners();
  }

  @override
  void pauseDownload(String id) => paused.add(id);
  @override
  Future<void> removeDownload(String id) async {}
  @override
  Future<void> delete(String modelId) async {
    models = [
      for (final model in models)
        if (model.id != modelId) model,
    ];
    notifyListeners();
  }

  @override
  Future<void> removeProjector(String modelId) async {}
  @override
  Future<void> unload() async {}
  @override
  Stream<ProviderEvent> generate(
    ProviderConfig config,
    ChatRequest request, {
    required CancelToken cancel,
  }) async* {
    if (!models.any((model) => model.id == config.model)) {
      yield const ProviderError('missing', code: 'model_missing');
      return;
    }
    requests.add((config, request));
    yield const TextDelta('Hi from the phone.');
    yield const Done('stop');
  }
}

class _Services extends PlatformServices {
  _Services(this._onDevice);
  final _OnDevice _onDevice;
  @override
  OnDeviceCapability get onDevice => _onDevice;
  @override
  Future<DeviceContext> deviceContext() async =>
      const DeviceContext(osVersion: 'test', model: 'test device');
  @override
  Future<String?> readSecret(String reference) async => null;
  @override
  Future<void> writeSecret(String reference, String? value) async {}
}

Future<AppController> _boot(
  WidgetTester tester,
  _OnDevice onDevice, {
  Widget? home,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final database = AppDatabase(NativeDatabase.memory());
  final controller = AppController(
    database: database,
    services: _Services(onDevice),
    promptTemplate:
        'You are {{app_name}}.{{#on_device}} You run on this phone.{{/on_device}}',
  );
  await tester.runAsync(() async {
    await controller.initialize();
    await controller.updateAppearance(language: const Locale('en'));
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appControllerProvider.overrideWith((ref) => controller)],
      child: home == null
          ? const TakoApp()
          : MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: home,
            ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });
  return controller;
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 250 && !ready(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(ready(), isTrue);
  await tester.pump();
}

void main() {
  testWidgets(
    'AICore setup detects tool support without offering file actions',
    (tester) async {
      final onDevice = _OnDevice()
        ..systemModelStatus = const SystemModelStatus(
          SystemModelState.available,
        );
      final app = await _boot(
        tester,
        onDevice,
        home: const OnDeviceModelsScreen(),
      );
      await tester.tap(find.byKey(const ValueKey('prepare-aicore')));
      await tester.pumpAndSettle();
      expect(onDevice.preparations, 1);
      final model = find.byKey(ValueKey('local-model-${aicoreModel.id}'));
      await tester.scrollUntilVisible(model, 100);
      await tester.tap(
        find.byKey(ValueKey('local-model-menu-${aicoreModel.id}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsNothing);
      expect(find.text('Add vision projector'), findsNothing);
      expect(find.text('Unload from memory'), findsOne);
      await tester.tap(find.text('Use in chat'));
      await _waitFor(tester, () => app.providers.isNotEmpty);
      expect(app.selectedProvider!.model, aicoreModel.id);
      expect(app.selectedProvider!.baseUrl, '');
      expect(app.selectedProvider!.isLocal, isTrue);
      expect(app.selectedProvider!.capabilities.tools, isTrue);
      expect(app.selectedProvider!.capabilities.vision, isFalse);
      expect(app.selectedProvider!.capabilities.reasoning, isFalse);
    },
  );

  testWidgets('AICore preview setup selects the preview provider with tools', (
    tester,
  ) async {
    final onDevice = _OnDevice()
      ..previewStatus = const SystemModelStatus(
        SystemModelState.available,
        model: aicorePreviewModel,
      );
    final app = await _boot(
      tester,
      onDevice,
      home: const OnDeviceModelsScreen(),
    );
    expect(find.textContaining('Preview models require enrollment'), findsOne);
    await tester.tap(find.byKey(const ValueKey('prepare-aicore-preview')));
    await tester.pumpAndSettle();
    final model = find.byKey(ValueKey('local-model-${aicorePreviewModel.id}'));
    await tester.scrollUntilVisible(model, 100);
    await tester.tap(model);
    await _waitFor(tester, () => app.providers.isNotEmpty);
    expect(app.selectedProvider!.model, aicorePreviewModel.id);
    expect(app.selectedProvider!.capabilities.tools, isTrue);
  });

  testWidgets('reselecting AICore refreshes the saved capability profile', (
    tester,
  ) async {
    final onDevice = _OnDevice();
    final app = await _boot(tester, onDevice);
    await tester.runAsync(() async {
      await app.useOnDeviceModel(
        const LocalModel.system(
          id: 'aicore:gemini-nano',
          name: 'Old AICore profile',
          profile: ModelProfile(
            id: 'aicore:gemini-nano',
            autoDetect: true,
            maxOutputTokens: 2048,
          ),
        ),
        providerName: 'Local',
      );
      expect(app.selectedProvider!.capabilities.tools, isFalse);
      await app.useOnDeviceModel(_nano, providerName: 'Local');
    });
    expect(app.selectedProvider!.capabilities.tools, isTrue);
    expect(app.selectedProvider!.capabilities.contextWindow, 8192);
    expect(app.selectedProvider!.maxOutputTokens, 2048);
    expect(app.providers.single.models, hasLength(1));
  });

  testWidgets(
    'unavailable AICore explains requirements alongside GGUF models',
    (tester) async {
      final onDevice = _OnDevice()
        ..systemModelStatus = const SystemModelStatus(
          SystemModelState.unavailable,
        );
      await _boot(tester, onDevice, home: const OnDeviceModelsScreen());
      expect(find.textContaining("This model isn't available"), findsOne);
      expect(find.byKey(const ValueKey('prepare-aicore')), findsNothing);
      final gguf = find.byKey(ValueKey('local-model-${_qwen.id}'));
      await tester.scrollUntilVisible(gguf, 100);
      expect(gguf, findsOne);
    },
  );

  testWidgets('a recommended model downloads with its projector, checked', (
    tester,
  ) async {
    final onDevice = _OnDevice();
    await _boot(tester, onDevice, home: const OnDeviceModelsScreen());
    expect(find.text('Qwen3.5 0.8B'), findsWidgets);
    expect(find.textContaining('Models use 508 MB'), findsOneWidget);

    final recommended = RecommendedModel.all.last;
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('recommended-download-${recommended.id}')),
      200,
    );
    await tester.ensureVisible(
      find.byKey(ValueKey('recommended-download-${recommended.id}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('recommended-download-${recommended.id}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Download with image input'));
    await tester.pumpAndSettle();
    expect(onDevice.started, [
      (
        'Qwen3VL-2B-Instruct-Q4_K_M.gguf',
        recommended.model.sha256,
        recommended.model.size,
        'qwen3-vl-2b-instruct',
        null,
      ),
      (
        'Qwen3VL-2B-Instruct-Q4_K_M.mmproj.gguf',
        recommended.projector!.sha256,
        recommended.projector!.size,
        null,
        'Qwen3VL-2B-Instruct-Q4_K_M.gguf',
      ),
    ]);
    // The running download shows progress and can be paused.
    await tester.scrollUntilVisible(find.text('Downloading'), -200);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    await tester.tap(find.byTooltip('Pause').first);
    expect(onDevice.paused, ['Qwen3VL-2B-Instruct-Q4_K_M.gguf']);
  });

  testWidgets('a URL download is refused unless it is HTTPS or local', (
    tester,
  ) async {
    final onDevice = _OnDevice();
    await _boot(tester, onDevice, home: const OnDeviceModelsScreen());
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('download-model-url')),
      200,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('download-model-url')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('download-model-url')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('model-url')), 'ftp://x');
    await tester.tap(find.widgetWithText(FilledButton, 'Download'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Use an http(s) URL'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('model-url')),
      'https://huggingface.co/o/r/resolve/main/Tiny-Q8_0.gguf',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Download'));
    // An unknown size shows an endless progress bar: no pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 500));
    expect(onDevice.started.single.$1, 'Tiny-Q8_0.gguf');
    expect(onDevice.started.single.$2, isNull);
  });

  testWidgets('Use in chat sets up the on-device provider, and it answers', (
    tester,
  ) async {
    final onDevice = _OnDevice();
    final app = await _boot(tester, onDevice);
    await tester.runAsync(
      () => app.useOnDeviceModel(_qwen, providerName: 'On-device models'),
    );
    final provider = app.selectedProvider!;
    expect(provider.apiType, ApiType.onDevice);
    expect(provider.isLocal, isTrue);
    expect(provider.model, _qwen.id);
    expect(provider.capabilities.tools, isTrue);
    expect(provider.capabilities.reasoning, isTrue);
    expect(provider.capabilities.contextWindow, 8192);
    expect(provider.reasoningMode, ReasoningMode.off);

    await tester.runAsync(() => app.send('Hello'));
    await tester.pumpAndSettle();
    expect(find.text('Hi from the phone.'), findsOneWidget);
    final (config, request) = onDevice.requests.single;
    expect(config.model, _qwen.id);
    expect(request.systemPrompt, contains('You run on this phone.'));

    // Using it again neither duplicates the provider nor its model.
    await tester.runAsync(
      () => app.useOnDeviceModel(_qwen, providerName: 'On-device models'),
    );
    expect(app.providers.single.models.single.id, _qwen.id);

    // A deleted file is explained rather than sent.
    await tester.runAsync(() => onDevice.delete(_qwen.id));
    await tester.runAsync(() => app.send('Again'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no longer on the phone'), findsOneWidget);
    expect(onDevice.requests, hasLength(1));
  });

  testWidgets('deleting a model removes it from the provider', (tester) async {
    final onDevice = _OnDevice();
    final other = LocalModel(id: 'Other.gguf', sizeBytes: 1, info: _qwen.info!);
    onDevice.models = [_qwen, other];
    final app = await _boot(tester, onDevice);
    await tester.runAsync(() async {
      await app.useOnDeviceModel(other, providerName: 'On-device models');
      await app.useOnDeviceModel(_qwen, providerName: 'On-device models');
      await app.deleteOnDeviceModel(_qwen.id);
    });
    expect(app.providers.single.models.map((m) => m.id), ['Other.gguf']);
    expect(app.selectedProvider!.model, 'Other.gguf');
  });

  testWidgets('the provider editor offers the phone models, without a URL', (
    tester,
  ) async {
    final onDevice = _OnDevice();
    final app = await _boot(tester, onDevice, home: const ProviderEditor());
    await tester.enterText(find.byType(TextFormField).first, 'Phone');
    await tester.tap(find.text('OpenAI Chat Completions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('On-device (llama.cpp / AICore)').last);
    await tester.pumpAndSettle();
    expect(find.text('Base URL'), findsNothing);
    expect(find.text('API key'), findsNothing);
    expect(find.text('Test connection'), findsNothing);
    expect(find.byKey(const ValueKey('manage-on-device-models')), findsOne);

    await tester.tap(find.text('Load models'));
    await _waitFor(
      tester,
      () => find.text('Qwen3.5 0.8B').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Qwen3.5 0.8B'));
    await tester.pump();
    await tester.tap(find.text('Add selected'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Save'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await _waitFor(tester, () => app.providers.isNotEmpty);
    final saved = app.providers.single;
    expect(saved.apiType, ApiType.onDevice);
    expect(saved.baseUrl, '');
    expect(saved.models.map((m) => m.id), [_qwen.id]);
    expect(saved.models.single.capabilities.contextWindow, 8192);
    expect(saved.models.single.capabilities.tools, isTrue);
  });

  test('a recommended model names its projector after itself', () {
    expect(
      RecommendedModel.all.map((m) => m.projectorName).toSet(),
      hasLength(RecommendedModel.all.length),
    );
    expect(
      RecommendedModel.all.first.model.url.toString(),
      'https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/'
      '23749fefcc72300e3a2ad315e1317431b06b590a/Qwen3-0.6B-Q8_0.gguf',
    );
  });
}
