import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/app/app_controller.dart';
import 'package:tako/core/permissions/permission_gate.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/data/database.dart';
import 'package:tako/l10n/gen/app_localizations.dart';
import 'package:tako/platform/services.dart';
import 'package:tako/ui/chat/tool_widgets.dart';
import 'package:tako/ui/settings/provider_editor.dart';

class _Services extends PlatformServices {
  final secrets = <String, String>{};

  @override
  Future<String?> readSecret(String reference) async => secrets[reference];

  @override
  Future<void> writeSecret(String reference, String? value) async {
    if (value == null) {
      secrets.remove(reference);
    } else {
      secrets[reference] = value;
    }
  }
}

class _ProbeAdapter implements ProviderAdapter {
  _ProbeAdapter({this.hold = false});

  final bool hold;
  final requests = <ChatRequest>[];
  CancelToken? token;

  @override
  Future<List<ModelInfo>> listModels({CancelToken? cancel}) async => const [];

  @override
  Stream<ProviderEvent> send(
    ChatRequest request, {
    required CancelToken cancel,
  }) async* {
    requests.add(request);
    token = cancel;
    if (hold) {
      await cancel.whenCancelled;
      return;
    }
    yield const HostedSearchEvent(success: true);
    yield const TextDelta('A public search was completed.');
    yield const Done('stop');
  }
}

ProviderConfig _provider({ApiType api = ApiType.responses}) => ProviderConfig(
  id: 'cpa-test-provider',
  displayName: 'CPA',
  apiType: api,
  baseUrl: 'https://cpa.example.test/v1',
  model: 'first-model',
  models: const [
    ModelProfile(
      id: 'first-model',
      capabilities: ProviderCapabilities(contextWindow: 32768),
    ),
    ModelProfile(
      id: 'second-model',
      capabilities: ProviderCapabilities(contextWindow: 32768),
    ),
  ],
);

class _Harness {
  _Harness(this.app, this.services, this.navigator);

  final AppController app;
  final _Services services;
  final GlobalKey<NavigatorState> navigator;

  Future<void> reopen(WidgetTester tester, ProviderConfig provider) async {
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute(builder: (_) => ProviderEditor(provider: provider)),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Future<_Harness> _boot(
  WidgetTester tester, {
  required _ProbeAdapter adapter,
  ApiType api = ApiType.responses,
  PermissionPolicy? permissionPolicy,
}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final database = AppDatabase(NativeDatabase.memory());
  final services = _Services();
  final app = AppController(
    titleGenerator: (_, _, _) async => null,
    database: database,
    services: services,
    promptTemplate: 'Assistant',
    adapterFactory: (_, _, _) => adapter,
  );
  await tester.runAsync(() async {
    await app.initialize();
    await app.saveProvider(_provider(api: api));
  });
  if (permissionPolicy != null) app.permissionGate.policy = permissionPolicy;
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appControllerProvider.overrideWith((ref) => app)],
      child: MaterialApp(
        navigatorKey: navigator,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(database.close);
  });
  final harness = _Harness(app, services, navigator);
  await harness.reopen(tester, app.providers.single);
  return harness;
}

Finder get _native => find.byKey(const ValueKey('provider-native-search'));
Finder get _custom =>
    find.byKey(const ValueKey('provider-custom-search-endpoint'));
Finder get _probe => find.byKey(const ValueKey('provider-probe-search'));
Finder get _cancel => find.byKey(const ValueKey('provider-probe-cancel'));
Finder get _result => find.byKey(const ValueKey('provider-probe-result'));

Future<void> _scrollTo(
  WidgetTester tester,
  Finder finder, {
  double delta = 300,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find
        .descendant(
          of: find.byType(ProviderEditor),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pump();
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 80 && !ready(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    // Real async work (SQLite) and Flutter route/sheet animations use separate
    // clocks in widget tests; advance both before observing UI completion.
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(
    ready(),
    isTrue,
    reason: 'Expected the pending UI operation to finish',
  );
}

void main() {
  testWidgets(
    'image mode and references persist independently for each model',
    (tester) async {
      final harness = await _boot(tester, adapter: _ProbeAdapter());
      final modes = find.byType(DropdownButtonFormField<ImageGenerationMode>);
      await _scrollTo(tester, modes);
      await tester.tap(modes);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Images API').last);
      await tester.pumpAndSettle();
      final references = find.byKey(const ValueKey('provider-image-reference'));
      await _scrollTo(tester, references);
      await tester.tap(references);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(references).value, isTrue);
      final second = find.widgetWithText(InputChip, 'second-model');
      await _scrollTo(tester, second, delta: -300);
      await tester.tap(second);
      await tester.pumpAndSettle();
      await _scrollTo(tester, modes);
      expect(
        tester
            .widget<DropdownButtonFormField<ImageGenerationMode>>(modes)
            .initialValue,
        ImageGenerationMode.none,
      );
      await tester.tap(modes);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Responses image tool').last);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(references).value, isFalse);
      final save = find.widgetWithText(FilledButton, 'Save');
      await _scrollTo(tester, save);
      await tester.tap(save);
      await _waitFor(
        tester,
        () => find.byType(ProviderEditor).evaluate().isEmpty,
      );
      final saved = (await tester.runAsync(
        harness.app.providerRepository.list,
      ))!.single;
      expect(
        saved.forModel('first-model').capabilities.imageGeneration,
        ImageGenerationMode.imagesApi,
      );
      expect(
        saved.forModel('first-model').capabilities.imageReferenceInput,
        isTrue,
      );
      expect(
        saved.forModel('second-model').capabilities.imageGeneration,
        ImageGenerationMode.responsesTool,
      );
      expect(
        saved.forModel('second-model').capabilities.imageReferenceInput,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('manual native search flags persist independently per model', (
    tester,
  ) async {
    final harness = await _boot(tester, adapter: _ProbeAdapter());
    await _scrollTo(tester, _native);
    await tester.tap(_native);
    await _scrollTo(tester, _custom);
    await tester.tap(_custom);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(_custom).value, isTrue);
    await _scrollTo(tester, _native, delta: -300);
    expect(tester.widget<SwitchListTile>(_native).value, isTrue);

    final second = find.widgetWithText(InputChip, 'second-model');
    await _scrollTo(tester, second, delta: -300);
    await tester.tap(second);
    await tester.pump();
    await _scrollTo(tester, _native);
    expect(tester.widget<SwitchListTile>(_native).value, isFalse);
    await _scrollTo(tester, _custom);
    expect(tester.widget<SwitchListTile>(_custom).value, isFalse);

    final save = find.widgetWithText(FilledButton, 'Save');
    await _scrollTo(tester, save);
    await tester.tap(save);
    await _waitFor(
      tester,
      () => find.byType(ProviderEditor).evaluate().isEmpty,
    );
    final saved = (await tester.runAsync(
      harness.app.providerRepository.list,
    ))!.single;
    expect(saved.forModel('first-model').capabilities.builtInWebSearch, isTrue);
    expect(
      saved.forModel('first-model').capabilities.allowCustomSearchEndpoint,
      isTrue,
    );
    expect(
      saved.forModel('second-model').capabilities.builtInWebSearch,
      isFalse,
    );
    expect(
      saved.forModel('second-model').capabilities.allowCustomSearchEndpoint,
      isFalse,
    );
    await harness.reopen(tester, saved);
    await _scrollTo(tester, _native);
    expect(tester.widget<SwitchListTile>(_native).value, isTrue);
    await _scrollTo(tester, _custom);
    expect(tester.widget<SwitchListTile>(_custom).value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('successful probe reports receipt without enabling or saving', (
    tester,
  ) async {
    final adapter = _ProbeAdapter();
    final harness = await _boot(tester, adapter: adapter);
    final before = harness.app.providers.single.toJson();
    await _scrollTo(tester, _probe);
    await tester.tap(_probe);
    await _waitFor(tester, () => _result.evaluate().isNotEmpty);
    expect(
      tester.widget<Text>(_result).data,
      'Verified: the provider completed a native search.',
    );
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.builtInWebSearch, isTrue);
    expect(adapter.requests.single.forceBuiltInWebSearch, isTrue);
    await _scrollTo(tester, _native, delta: -300);
    expect(tester.widget<SwitchListTile>(_native).value, isFalse);
    await _scrollTo(tester, _custom);
    expect(tester.widget<SwitchListTile>(_custom).value, isFalse);
    expect(harness.app.providers.single.toJson(), before);
    final persisted = (await tester.runAsync(
      harness.app.providerRepository.list,
    ))!.single;
    expect(persisted.toJson(), before);
    expect(harness.services.secrets, isEmpty);
    expect(find.byType(ProviderEditor), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending native search permission is visible and cancellable', (
    tester,
  ) async {
    final adapter = _ProbeAdapter();
    final harness = await _boot(
      tester,
      adapter: adapter,
      permissionPolicy: const PermissionPolicy(
        overrides: {'web_search': ToolPermission.ask},
      ),
    );
    await _scrollTo(tester, _probe);
    await tester.tap(_probe);
    await _waitFor(
      tester,
      () => find.byType(ToolApprovalSheet).evaluate().isNotEmpty,
    );
    expect(harness.app.pendingApproval, isNotNull);
    expect(find.byType(ToolApprovalSheet), findsOneWidget);
    expect(find.text('Allow once').hitTestable(), findsOneWidget);
    expect(adapter.requests, isEmpty);
    expect(_cancel.hitTestable(), findsOneWidget);
    await tester.tap(_cancel);
    await _waitFor(
      tester,
      () =>
          harness.app.pendingApproval == null &&
          find.byType(ToolApprovalSheet).evaluate().isEmpty,
    );
    expect(find.byType(ToolApprovalSheet), findsNothing);
    expect(adapter.requests, isEmpty);
    expect(find.byType(ProviderEditor), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active native search probe can be cancelled', (tester) async {
    final adapter = _ProbeAdapter(hold: true);
    await _boot(tester, adapter: adapter);
    await _scrollTo(tester, _probe);
    await tester.tap(_probe);
    await _waitFor(tester, () => adapter.requests.isNotEmpty);
    expect(_cancel.hitTestable(), findsOneWidget);
    await tester.tap(_cancel);
    await _waitFor(tester, () => adapter.token?.isCancelled == true);
    await _waitFor(tester, () => _result.evaluate().isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Chat Completions does not offer unsupported native controls', (
    tester,
  ) async {
    final adapter = _ProbeAdapter();
    await _boot(tester, adapter: adapter, api: ApiType.chatCompletions);
    await _scrollTo(tester, _native);
    expect(tester.widget<SwitchListTile>(_native).onChanged, isNull);
    if (_custom.evaluate().isNotEmpty) {
      expect(tester.widget<SwitchListTile>(_custom).onChanged, isNull);
    }
    if (_probe.evaluate().isNotEmpty) {
      expect(tester.widget<ButtonStyleButton>(_probe).onPressed, isNull);
    }
    expect(adapter.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
