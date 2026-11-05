import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tako/app/app.dart';
import 'package:tako/app/app_controller.dart';
import 'package:tako/core/den/den_account.dart';
import 'package:tako/core/den/den_client.dart';
import 'package:tako/data/database.dart';
import 'package:tako/platform/services.dart';
import 'package:tako/ui/den/den_connect_screen.dart';
import 'package:tako/ui/den/den_screen.dart';
import 'package:tako/ui/settings/settings_screen.dart';

const _capture = bool.fromEnvironment('UPDATE_UI_SCREENSHOTS');
const _captureKey = Key('den-screenshot');

final class _Services extends PlatformServices {
  final secrets = <String, String>{};
  final opened = <Uri>[];

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

  @override
  Future<bool> openLink(Uri uri) async {
    opened.add(uri);
    return true;
  }
}

/// A Den with one account that already has a chat from another device.
final class _FakeDen {
  final pushed = <String>[];
  var signedOut = false;
  final _now = DateTime.utc(2026, 11, 5, 9).toIso8601String();

  late final client = MockClient(_handle);

  Map<String, Object?> get _user => {
    'id': 'u1',
    'username': 'ana',
    'displayName': 'Ana',
    'role': 'user',
  };

  Future<http.Response> _handle(http.Request request) async {
    http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
    switch (request.url.path) {
      case '/v1/info':
        return json({
          'name': 'Home Den',
          'version': '0.2.0',
          'setupRequired': false,
          'registration': 'invite',
          'passwordLogin': true,
          'oauth': [
            {'id': 'discord', 'type': 'discord', 'name': 'Discord'},
          ],
          'features': ['sync', 'gateway', 'device-login', 'oauth'],
        });
      case '/v1/auth/login':
        final body = jsonDecode(request.body) as Map;
        if (body['password'] != 'secret-password') {
          return json({
            'error': {'code': 'invalid_login', 'message': 'Wrong.'},
          }, 401);
        }
        return json({
          'token': 'tako_phone',
          'device': {'id': 'phone', 'name': body['deviceName']},
          'user': _user,
        });
      case '/v1/auth/device':
        return json({
          'deviceCode': 'long-device-code',
          'userCode': 'WXYZ-2345',
          'verificationUrl': 'https://den.example.com/link?code=WXYZ-2345',
          'expiresIn': 600,
          'interval': 3,
        });
      case '/v1/auth/device/poll':
        return json({'status': 'pending'}, 202);
      case '/v1/auth/logout':
        signedOut = true;
        return json({'ok': true});
      case '/v1/models':
        return json({
          'object': 'list',
          'data': [
            {'id': 'openai/gpt-5.5', 'object': 'model'},
          ],
        });
      case '/v1/sync/push':
        final changes = (jsonDecode(request.body) as Map)['changes'] as List;
        return json({
          'seq': 10,
          'results': [
            for (final change in changes.cast<Map<String, Object?>>())
              () {
                pushed.add('${change['collection']}/${change['id']}');
                return {
                  'status': 'ok',
                  'collection': change['collection'],
                  'id': change['id'],
                  'version': 1,
                  'seq': 10,
                };
              }(),
          ],
        });
      case '/v1/sync/pull':
        final since = int.parse(request.url.queryParameters['since'] ?? '0');
        if (since > 0) return json({'changes': [], 'seq': 2, 'more': false});
        return json({
          'changes': [
            {
              'collection': 'conversations',
              'id': 'web-chat',
              'version': 1,
              'seq': 1,
              'updatedAt': _now,
              'deviceId': 'web',
              'data': {
                'id': 'web-chat',
                'title': 'Trip to Tainan',
                'createdAt': _now,
                'updatedAt': _now,
                'systemPrompt': 'You are Tako.',
                'activeLeafId': 'web-1',
              },
            },
            {
              'collection': 'messages',
              'id': 'web-1',
              'version': 1,
              'seq': 2,
              'updatedAt': _now,
              'deviceId': 'web',
              'data': {
                'id': 'web-1',
                'conversationId': 'web-chat',
                'parentId': null,
                'role': 'user',
                'content': [
                  {'type': 'text', 'text': 'Plan a day in Tainan'},
                ],
                'createdAt': _now,
                'status': 'done',
              },
            },
          ],
          'seq': 2,
          'more': false,
        });
      case '/v1/events':
        // No live connection in tests; the engine retries after a backoff.
        return json({
          'error': {'code': 'unavailable', 'message': 'No events.'},
        }, 503);
    }
    return json({
      'error': {'code': 'not_found', 'message': request.url.path},
    }, 404);
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  if (!_capture) return;
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('build/qa').create(recursive: true);
    await File('build/qa/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

/// Lets the sync engine's HTTP and database work finish.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    if (!_capture) return;
    // Capture-only fonts, as in test/widget_test.dart.
    for (final (family, path) in [
      ('Roboto', 'C:/Windows/Fonts/msjh.ttc'),
      ('Roboto', 'C:/Windows/Fonts/msjhbd.ttc'),
      (
        'Roboto',
        'D:/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      (
        'MaterialIcons',
        'D:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    ]) {
      final file = File(path);
      if (await file.exists()) {
        await (FontLoader(
          family,
        )..addFont(file.readAsBytes().then(ByteData.sublistView))).load();
      }
    }
  });

  testWidgets('connects to a Den from the first screen, syncs and signs out', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final den = _FakeDen();
    final services = _Services();
    final database = AppDatabase(NativeDatabase.memory());
    final controller = AppController(
      titleGenerator: (_, _, _) async => null,
      database: database,
      services: services,
      promptTemplate: 'You are {{app_name}}.',
      denClientFactory: (server, token) =>
          DenClient(server, token: token, client: den.client),
    );
    await tester.runAsync(() async {
      await controller.initialize();
      await controller.updateAppearance(language: const Locale('en'));
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: ProviderScope(
          overrides: [appControllerProvider.overrideWith((ref) => controller)],
          child: const TakoApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The first screen offers the Den below the provider choices.
    await tester.tap(find.byKey(const ValueKey('setup-den')));
    await tester.pumpAndSettle();
    expect(find.byType(DenConnectScreen), findsOneWidget);
    await _shot(tester, 'den-connect-address');

    await tester.enterText(
      find.byKey(const ValueKey('den-address')),
      'den.example.com',
    );
    await tester.tap(find.text('Continue'));
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(find.text('Continue with Discord'), findsOneWidget);
    expect(find.byKey(const ValueKey('den-browser')), findsOneWidget);
    await _shot(tester, 'den-connect-sign-in');

    // OAuth opens the Den's public address with the app's device code.
    await tester.tap(find.text('Continue with Discord'));
    await tester.runAsync(() async {});
    // The waiting dialog's progress indicator never settles.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      services.opened.single.toString(),
      'https://den.example.com/v1/auth/oauth/discord/start?device=WXYZ-2345',
    );
    expect(find.textContaining('WXYZ-2345'), findsWidgets);
    if (_capture) {
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(_captureKey),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/qa').create(recursive: true);
        await File(
          'build/qa/den-connect-browser.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(DenConnectScreen), findsOneWidget);

    // A wrong password is explained; the right one signs in.
    await tester.enterText(find.byKey(const ValueKey('den-username')), 'ana');
    await tester.enterText(
      find.byKey(const ValueKey('den-password')),
      'wrong-password',
    );
    await tester.tap(find.byKey(const ValueKey('den-sign-in')));
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(find.text('Wrong username or password.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('den-password')),
      'secret-password',
    );
    await tester.tap(find.byKey(const ValueKey('den-sign-in')));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(DenConnectScreen), findsNothing);
    expect(find.text('Connected to Home Den'), findsOneWidget);

    // The Den became the provider, and the account's chat arrived.
    expect(controller.den.connected, isTrue);
    expect(services.secrets[DenAccount.tokenKey], 'tako_phone');
    final provider = controller.providers.single;
    expect(provider.id, DenAccount.providerId);
    expect(provider.baseUrl, 'https://den.example.com/v1');
    expect(provider.model, 'openai/gpt-5.5');
    expect(provider.isLocal, isFalse);
    await _settle(tester);
    expect(
      controller.conversations.map((c) => c.title),
      contains('Trip to Tainan'),
    );
    expect(
      find.text(
        'Ask, explore, or work something out. '
        'Your conversations sync with Home Den.',
      ),
      findsOneWidget,
    );
    await _shot(tester, 'den-connected-chat');

    // Settings show the account and open the Den screen.
    unawaited(
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
    );
    await tester.pumpAndSettle();
    final tile = find.byKey(const ValueKey('settings-den'));
    expect(
      find.descendant(of: tile, matching: find.text('Ana · den.example.com')),
      findsOneWidget,
    );
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byType(DenScreen), findsOneWidget);
    await _shot(tester, 'den-screen');

    // Signing out keeps the chats and removes the provider.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('den-sign-out')),
      200,
    );
    await tester.tap(find.byKey(const ValueKey('den-sign-out')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(den.signedOut, isTrue);
    expect(controller.den.connected, isFalse);
    expect(controller.providers, isEmpty);
    expect(services.secrets[DenAccount.tokenKey], isNull);
    expect(
      controller.conversations.map((c) => c.title),
      contains('Trip to Tainan'),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(database.close);
  });
}
