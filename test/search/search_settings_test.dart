import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/app/app_controller.dart';
import 'package:tako/core/search/search_service.dart';
import 'package:tako/data/database.dart';
import 'package:tako/l10n/gen/app_localizations.dart';
import 'package:tako/platform/services.dart';
import 'package:tako/ui/settings/search_settings_screen.dart';

class _Services extends PlatformServices {
  final keys = <String, String>{};

  @override
  Future<String?> readSecret(String reference) async => keys[reference];

  @override
  Future<void> writeSecret(String reference, String? value) async {
    if (value == null) {
      keys.remove(reference);
    } else {
      keys[reference] = value;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'search keys stay with their provider and never enter settings JSON',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final services = _Services();
      final app = AppController(
        database: db,
        services: services,
        promptTemplate: 'Assistant',
      );
      addTearDown(() async {
        app.dispose();
        await db.close();
      });
      await app.initialize();
      await app.saveSearchConfig(
        const SearchConfig(kind: SearchKind.serper),
        key: 'test-only-serper-secret',
      );
      expect(app.searchConfig.apiKeyRef, 'search.serper.key');
      expect(await app.hasSearchKey(SearchKind.serper), isTrue);
      expect(await app.hasSearchKey(SearchKind.ddgs), isFalse);

      // A stale reference from the old provider must not authenticate DDGS.
      await app.saveSearchConfig(
        SearchConfig(
          kind: SearchKind.ddgs,
          baseUrl: 'http://localhost:4479',
          apiKeyRef: app.searchConfig.apiKeyRef,
        ),
      );
      expect(app.searchConfig.apiKeyRef, isNull);
      expect(
        SearchService(
          app.searchConfig,
          readSecret: services.readSecret,
        ).isAvailable,
        isTrue,
      );
      await app.saveSearchConfig(
        app.searchConfig,
        key: 'test-only-proxy-token',
      );
      expect(app.searchConfig.apiKeyRef, 'search.ddgs.key');

      await app.saveSearchConfig(
        SearchConfig(
          kind: SearchKind.serper,
          apiKeyRef: app.searchConfig.apiKeyRef,
        ),
      );
      expect(app.searchConfig.apiKeyRef, 'search.serper.key');
      expect(services.keys['search.serper.key'], 'test-only-serper-secret');
      expect(services.keys['search.ddgs.key'], 'test-only-proxy-token');
      final preferences = await app.settings.readAll();
      expect(preferences['search.config'], isNot(contains('test-only-')));

      await app.saveSearchConfig(app.searchConfig, removeKey: true);
      expect(app.searchConfig.apiKeyRef, isNull);
      expect(await app.hasSearchKey(SearchKind.serper), isFalse);
      expect(await app.hasSearchKey(SearchKind.ddgs), isTrue);
      expect(
        SearchService(
          app.searchConfig,
          readSecret: services.readSecret,
        ).isAvailable,
        isFalse,
      );
    },
  );

  test(
    'invalid DDGS configuration cannot overwrite the active config or key',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final services = _Services();
      final app = AppController(
        database: db,
        services: services,
        promptTemplate: 'Assistant',
      );
      addTearDown(() async {
        app.dispose();
        await db.close();
      });
      await app.initialize();
      await app.saveSearchConfig(
        const SearchConfig(kind: SearchKind.serper),
        key: 'test-only-serper',
      );
      for (final invalid in [
        const SearchConfig(kind: SearchKind.ddgs),
        const SearchConfig(kind: SearchKind.ddgs, baseUrl: 'file:///search'),
        const SearchConfig(
          kind: SearchKind.ddgs,
          baseUrl: 'http://localhost:4479',
          resultCount: 11,
        ),
      ]) {
        await expectLater(
          app.saveSearchConfig(invalid, key: 'test-only-should-not-save'),
          throwsA(isA<SearchFailure>()),
        );
      }
      expect(app.searchConfig.kind, SearchKind.serper);
      expect(services.keys, {'search.serper.key': 'test-only-serper'});
      expect(app.busy, isFalse);
    },
  );

  testWidgets(
    'switching Serper to DDGS clears unsaved credentials and saves without a key',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final services = _Services();
      final app = AppController(
        database: db,
        services: services,
        promptTemplate: 'Assistant',
      );
      await tester.runAsync(app.initialize);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith((ref) => app)],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            initialRoute: '/search',
            routes: {
              '/': (_) => const Scaffold(),
              '/search': (_) => const SearchSettingsScreen(),
            },
          ),
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(db.close);
      });
      await tester.pumpAndSettle();

      Future<void> choose(String name) async {
        await tester.tap(find.byType(DropdownButtonFormField<SearchKind>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();
      }

      Finder field(String label) => find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );

      await choose('Serper');
      expect(
        tester.widget<TextField>(field('Search endpoint')).controller!.text,
        'https://google.serper.dev',
      );
      await tester.enterText(field('Search API key'), 'test-only-unsaved-key');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await choose('DDGS');
      expect(
        tester
            .widget<TextField>(field('Bearer token (optional)'))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      expect(find.textContaining('DDGS API server'), findsOneWidget);
      await tester.enterText(field('Search endpoint'), 'http://localhost:4479');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      expect(app.searchConfig.kind, SearchKind.ddgs);
      expect(app.searchConfig.baseUrl, 'http://localhost:4479');
      expect(app.searchConfig.apiKeyRef, isNull);
      expect(services.keys, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
