import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tako/core/providers/cancel_token.dart';
import 'package:tako/core/screen/remote_screen.dart';
import 'package:tako/core/screen/screen_capability.dart';
import 'package:tako/core/screen/screen_reading.dart';
import 'package:tako/platform/device_tools_capability.dart';
import 'package:tako/platform/ios/ictrl_client.dart';
import 'package:tako/platform/ios/ictrl_crypto.dart';
import 'package:tako/platform/ios/ictrl_device_tools.dart';
import 'package:tako/platform/ios/ictrl_screen.dart';
import 'package:tako/platform/ios/ictrl_tree.dart';

void main() {
  test(
    'repeated keypad keys reuse live selectors until a fresh observation',
    () async {
      final client = _DeviceClient();
      final screen = IctrlScreen(client: client);
      await screen.connect();
      final tree = await screen.snapshot(
        screenshot: false,
        cancel: CancelToken(),
      );
      for (var i = 0; i < 3; i++) {
        await screen.resolveNode(tree.token, 1, CancelToken());
        await screen.act(
          ScreenAction(action: 'tap', token: tree.token, node: 1),
        );
      }
      expect(client.calls.where((c) => c.$1 == 'find_element'), hasLength(1));
      expect(client.calls.where((c) => c.$1 == 'tap'), hasLength(3));
      final fresh = await screen.snapshot(
        screenshot: false,
        cancel: CancelToken(),
      );
      await screen.resolveNode(fresh.token, 1, CancelToken());
      expect(client.calls.where((c) => c.$1 == 'find_element'), hasLength(2));
      screen.dispose();
    },
  );
  test(
    'observed action settles natively; stable result skips local polling',
    () async {
      final client = _DeviceClient()
        ..actionReceipt = {
          'settle': {'stable': true},
        }
        ..source = {
          'bundle_id': 'com.example.app',
          'source':
              "Application, label: 'App', {{0, 0}, {440, 956}}\n  Button, label: 'Start', {{20, 180}, {60, 40}}",
        };
      final screen = IctrlScreen(client: client);
      await screen.connect();
      final tree = await screen.snapshot(
        screenshot: false,
        cancel: CancelToken(),
      );
      await screen.act(
        ScreenAction(action: 'tap', token: tree.token, node: 1, settle: true),
      );
      final tap = client.calls.last;
      expect(tap.$2['settle'], true);
      expect(tap.$2['settle_timeout'], 1.2);
      await screen.snapshot(screenshot: false, cancel: CancelToken());
      expect(client.calls.where((c) => c.$1 == 'page_source'), hasLength(2));
      screen.dispose();
    },
  );
  test('post-action unchanged screen polls locally without replay', () async {
    final client = _DeviceClient();
    final screen = IctrlScreen(client: client);
    await screen.connect();
    final before = await screen.snapshot(
      screenshot: false,
      cancel: CancelToken(),
    );
    await screen.act(ScreenAction(action: 'tap', token: before.token, node: 1));
    client.sources = [
      {
        'bundle_id': 'com.apple.calculator',
        'source':
            "Application, label: 'Calculator', {{0, 0}, {440, 956}}\n  Key, label: '7', id: 'Seven', {{20, 180}, {60, 40}}",
      },
      {
        'bundle_id': 'com.apple.calculator',
        'source':
            "Application, label: 'Calculator', {{0, 0}, {440, 956}}\n  StaticText, label: '15', {{20, 180}, {60, 40}}",
      },
    ];
    final after = await screen.snapshot(
      screenshot: false,
      cancel: CancelToken(),
    );
    expect(after.nodes.last.text, '15');
    expect(client.calls.where((c) => c.$1 == 'tap'), hasLength(1));
    expect(client.calls.where((c) => c.$1 == 'page_source'), hasLength(3));
    screen.dispose();
  });
  test(
    'loading is polled to a bound and cancellation does not repeat actions',
    () async {
      final client = _DeviceClient()
        ..source = {
          'bundle_id': 'com.example.app',
          'source':
              "Application, label: 'App', {{0, 0}, {440, 956}}\n  StaticText, label: '載入中…', {{20, 180}, {60, 40}}",
        };
      final screen = IctrlScreen(client: client);
      await screen.connect();
      screen.expectObservation();
      await screen.snapshot(screenshot: false, cancel: CancelToken());
      expect(client.calls.where((c) => c.$1 == 'page_source'), hasLength(4));
      final cancel = CancelToken();
      screen.expectObservation();
      final reading = screen.snapshot(screenshot: false, cancel: cancel);
      cancel.cancel();
      await expectLater(reading, throwsA(isA<RequestCancelled>()));
      expect(client.calls.where((c) => c.$1 == 'tap'), isEmpty);
      screen.dispose();
    },
  );
  test(
    'server loading metadata delays an apparently populated page locally',
    () async {
      final client = _DeviceClient();
      final screen = IctrlScreen(client: client);
      await screen.connect();
      const source =
          "Application, label: 'App', {{0, 0}, {440, 956}}\n  StaticText, label: 'Ready', {{20, 180}, {60, 40}}";
      client.sources = [
        {'bundle_id': 'com.example.app', 'source': source, 'loading': true},
        {'bundle_id': 'com.example.app', 'source': source},
      ];
      screen.expectObservation(app: 'com.example.app');
      final tree = await screen.snapshot(
        screenshot: false,
        cancel: CancelToken(),
      );
      expect(tree.nodes.last.text, 'Ready');
      expect(client.calls.where((c) => c.$1 == 'page_source'), hasLength(2));
      expect(client.calls.where((c) => c.$1 == 'tap'), isEmpty);
      screen.dispose();
    },
  );
  test('envelope request matches the upstream Python reference vector', () {
    final envelope = IctrlCrypto.seal(
      List.generate(32, (i) => i),
      {
        'jsonrpc': '2.0',
        'id': 7,
        'method': 'device_info',
        'params': <String, Object?>{},
      },
      nonce: List.generate(16, (i) => i),
      timestamp: 1700000000,
    );
    expect(envelope['tok'], '630dcd29');
    // Fixed independent vector generated with upstream Scripts/ictrl_rpc.py.
    expect(envelope['ct'], requestVector);
    expect(envelope['tag'], requestTag);
  });
  test('authenticated response validates direction, tag and request nonce', () {
    final key = List.generate(32, (i) => i);
    final nonce = List.generate(16, (i) => i);
    final response = <String, Object?>{
      'v': 1,
      'nonce': IctrlCrypto.hex(nonce),
      'ct': responseVector,
      'tag': responseTag,
    };
    expect(IctrlCrypto.open(key, response, nonce)['id'], 7);
    expect(
      () => IctrlCrypto.open(key, {...response, 'tag': '00' * 32}, nonce),
      throwsFormatException,
    );
    expect(
      () => IctrlCrypto.open(key, response, List.filled(16, 1)),
      throwsFormatException,
    );
  });
  test('endpoint limits credentials, redirects and plain public HTTP', () {
    for (final url in [
      'http://127.0.0.1:8200',
      'http://192.168.2.180:8200',
      'http://100.77.80.7:8200',
      'http://phone.tail.ts.net:8200',
    ]) {
      expect(IctrlClient.validateEndpoint(url).host, isNotEmpty);
    }
    for (final url in [
      'http://example.com:8200',
      'http://user:password@127.0.0.1:8200',
      'http://127.0.0.1:8200/rpc',
      'http://127.0.0.1:8200?key=a',
    ]) {
      expect(() => IctrlClient.validateEndpoint(url), throwsFormatException);
    }
  });
  test(
    'pending local pairing stays single-flight and credentials are reused',
    () async {
      var pairCalls = 0;
      final pending = Completer<http.Response>();
      final secrets = <String, String>{};
      final client = IctrlClient(
        readSecret: (key) async => secrets[key],
        writeSecret: (key, value) async {
          if (value == null) {
            secrets.remove(key);
          } else {
            secrets[key] = value;
          }
        },
        client: MockClient((request) async {
          if (request.url.path == '/schema') {
            return http.Response(
              '{"server_version":"1.96.1","protocol_version":1}',
              200,
            );
          }
          if (request.url.path == '/pair') {
            pairCalls++;
            expect(
              (jsonDecode(request.body) as Map<String, dynamic>)['plain'],
              true,
            );
            return pending.future;
          }
          return http.Response('{"error":{"code":"ts_skew"}}', 401);
        }),
      );
      final screen = IctrlScreen(client: client);
      final first = screen.connect();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(screen.status, RemoteScreenStatus.pairing);
      final second = screen.refresh();
      expect(pairCalls, 1);
      final key = List.generate(32, (i) => i);
      pending.complete(
        http.Response(
          jsonEncode({
            'token': IctrlCrypto.hex(key),
            'tok': IctrlCrypto.tokenId(key),
          }),
          200,
        ),
      );
      await first;
      await second;
      expect(pairCalls, 1);
      expect(secrets.values, contains(IctrlCrypto.hex(key)));
      expect(screen.errorCode, 'ictrl_clock_skew');
      await screen.connect();
      expect(pairCalls, 1);
      screen.dispose();
    },
  );
  test(
    'denied pairing does not spawn another prompt on status refresh',
    () async {
      var pairs = 0;
      final client = IctrlClient(
        readSecret: (_) async => null,
        writeSecret: (_, _) async {},
        client: MockClient((request) async {
          if (request.url.path == '/schema') {
            return http.Response(
              '{"server_version":"1.96.1","protocol_version":1}',
              200,
            );
          }
          pairs++;
          return http.Response('{}', 403);
        }),
      );
      final screen = IctrlScreen(client: client);
      await screen.connect();
      expect(screen.status, RemoteScreenStatus.denied);
      await screen.connect();
      expect(pairs, 1);
      screen.dispose();
    },
  );
  test('explicit connect clears a saved disconnect', () async {
    final client = _DeviceClient()..secrets['ictrl.paused'] = 'true';
    final screen = IctrlScreen(client: client);
    await screen.refresh();
    expect(screen.status, RemoteScreenStatus.paused);
    await screen.connect(endpoint: screen.endpoint);
    expect(screen.status, RemoteScreenStatus.ready);
    expect(client.secrets['ictrl.paused'], isNull);
    screen.dispose();
  });
  test('scroll summaries cannot hide independently selectable child labels', () {
    final tree = parseIctrlTree(
      {
        'bundle_id': 'com.example.options',
        'source':
            "Application, {{0, 0}, {440, 956}}\n  ScrollView, label: 'Options Small Large', {{0, 100}, {440, 700}}\n    Other, label: 'Small', {{20, 200}, {80, 40}}\n    Other, label: 'Large', {{120, 200}, {80, 40}}",
      },
      token: 1,
      width: 440,
      height: 956,
    );
    final reading = ScreenReading.from(tree);
    expect(
      reading.elements.map((e) => e.label),
      containsAll(['Small', 'Large']),
    );
    expect(tree.nodes[1].scrollable, true);
    expect(tree.nodes[1].description, isNull);
  });
  test('multiline composers resolve without textfield-only filtering', () async {
    final client = _DeviceClient()
      ..source = {
        'bundle_id': 'com.example.chat',
        'source':
            "Application, {{0, 0}, {440, 956}}\n  TextView, label: 'Compose', {{30, 870}, {200, 39}}",
      };
    client.hit.addAll({'element_type': 'TextView', 'label': 'Compose'});
    final screen = IctrlScreen(client: client);
    await screen.connect();
    final tree = await screen.snapshot(
      screenshot: false,
      cancel: CancelToken(),
    );
    final target = await screen.resolveNode(tree.token, 1, CancelToken());
    expect(target.target!.editable, true);
    expect(client.calls.last.$2.containsKey('element_type'), false);
    screen.dispose();
  });
  test('native value and its label stay paired inside a labeled wrapper', () {
    final tree = parseIctrlTree(
      {
        'bundle_id': 'com.example.stats',
        'source':
            "Application, {{0, 0}, {440, 956}}\n  Other, label: 'Apps', value: '129 GB', {{20, 200}, {200, 40}}\n    StaticText, label: 'Apps', {{20, 200}, {100, 30}}\n  Other, label: 'Photos', value: '2 GB', {{20, 250}, {200, 40}}",
      },
      token: 1,
      width: 440,
      height: 956,
    );
    expect(ownLabel(tree.nodes[1]), '129 GB · Apps');
    expect(ownLabel(tree.nodes[3]), '2 GB · Photos');
    expect(ScreenReading.from(tree).toToolText(), contains('129 GB · Apps'));
  });
  test('literal multiline labels retain control types, frames and parents', () {
    final tree = parseIctrlTree(
      {
        'bundle_id': 'com.example.settings',
        'source':
            "Application, label: 'Example', {{0, 0}, {440, 956}}\n"
            "  ScrollView, label: 'Settings\nChoices', {{0, 100}, {440, 700}}\n"
            "    Switch, label: 'Full permissions\nRead and act', value: '1', {{20, 200}, {400, 80}}\n"
            "    Button, label: 'Show report\nTwo steps completed', id: 'report', {{20, 300}, {400, 80}}\n"
            "    StaticText, label: 'Quoted 'text'\nMore text', {{20, 400}, {400, 80}}",
      },
      token: 1,
      width: 440,
      height: 956,
    );
    expect(tree.nodes, hasLength(5));
    expect(tree.nodes[2].parent, 1);
    expect(tree.nodes[2].description, 'Full permissions\nRead and act');
    expect(tree.nodes[2].flags & ScreenFlags.checked, isNonZero);
    expect(tree.nodes[2].actionable, true);
    expect(tree.nodes[3].viewId, 'report');
    expect(tree.nodes[3].bounds.top, 300);
    expect(tree.nodes[4].text, "Quoted 'text'\nMore text");
    expect(ScreenReading.from(tree).toToolText(), contains('Two steps'));
  });
  test('multiline secure values remain private and do not become nodes', () {
    final tree = parseIctrlTree(
      {
        'bundle_id': 'com.example.login',
        'source':
            'Application, {{0, 0}, {440, 956}}\n'
            '  SecureTextField, label: \'API key\nPrivate\', value: \'SECRET\nSECOND LINE\', {{20, 200}, {400, 80}}\n'
            "  TextView, label: 'Compose', value: 'First line\nSecond line', {{20, 300}, {400, 80}}",
      },
      token: 1,
      width: 440,
      height: 956,
    );
    expect(tree.nodes, hasLength(3));
    expect(tree.nodes[1].password, true);
    expect(tree.nodes[1].text, isNull);
    expect(tree.nodes[2].editable, true);
    expect(tree.nodes[2].text, 'First line\nSecond line');
    final text = ScreenReading.from(tree).toToolText();
    expect(text, isNot(contains('SECRET')));
    expect(text, isNot(contains('SECOND LINE')));
  });
  test('clipped cells cannot redirect a tap into status bar', () async {
    final client = _DeviceClient()
      ..source = {
        'bundle_id': 'com.example.list',
        'source':
            "Application, {{0, 0}, {440, 956}}\n  Cell, {{224, -167}, {208, 354}}\n    StaticText, label: 'Candidate board', {{232, 48}, {192, 36}}",
      };
    final screen = IctrlScreen(client: client);
    await screen.connect();
    final tree = await screen.snapshot(
      screenshot: false,
      cancel: CancelToken(),
    );
    await expectLater(
      screen.resolveNode(tree.token, 1, CancelToken()),
      throwsA(
        isA<ScreenException>().having(
          (e) => e.code,
          'code',
          'element_offscreen_scroll_into_view',
        ),
      ),
    );
    expect(
      client.calls.where((c) => c.$1 == 'tap' || c.$1 == 'find_element'),
      isEmpty,
    );
    screen.dispose();
  });
  test('rich truncated AX skips OCR while sparse reads recover text', () async {
    final client = _DeviceClient()
      ..source = {
        'bundle_id': 'com.example.list',
        'truncated': true,
        'source':
            "Application, {{0, 0}, {440, 956}}\n${List.generate(6, (i) => "  Button, label: 'Item $i', {{20, ${100 + i * 50}}, {80, 40}}").join('\n')}",
      };
    final screen = IctrlScreen(client: client);
    await screen.connect();
    await screen.snapshot(screenshot: false, cancel: CancelToken());
    expect(client.calls.where((c) => c.$1 == 'screen_text'), isEmpty);
    client.source = {
      'bundle_id': 'com.example.list',
      'truncated': true,
      'source': 'Application, {{0, 0}, {440, 956}}',
    };
    client.ocrItems = [
      {'label': 'Custom control', 'x': 20, 'y': 200, 'width': 80, 'height': 30},
    ];
    final tree = await screen.snapshot(
      screenshot: false,
      cancel: CancelToken(),
    );
    expect(
      tree.nodes.where((n) => n.className == 'OCRText').single.text,
      'Custom control',
    );
    expect(client.calls.where((c) => c.$1 == 'screen_text'), hasLength(1));
    screen.dispose();
  });
  test(
    'timed inputs use bounded root guard and stop on geometry change',
    () async {
      final client = _DeviceClient();
      final screen = IctrlScreen(client: client);
      await screen.connect();
      await screen.snapshot(screenshot: false, cancel: CancelToken());
      screen.beginModelSession();
      await screen.timedGesture(
        const ScreenAction(action: 'tap', x: 50, y: 200),
        app: 'com.apple.calculator',
        width: 440,
        height: 956,
        cancel: CancelToken(),
      );
      expect(
        client.calls.where((c) => c.$1 == 'page_source').last.$2['max_depth'],
        1,
      );
      client.landscape = true;
      await expectLater(
        screen.timedGesture(
          const ScreenAction(action: 'tap', x: 50, y: 200),
          app: 'com.apple.calculator',
          width: 440,
          height: 956,
          cancel: CancelToken(),
        ),
        throwsA(isA<ScreenException>()),
      );
      expect(client.calls.where((c) => c.$1 == 'tap'), hasLength(1));
      screen.dispose();
    },
  );
  test(
    'remote sessions retain titles and end their native lifecycle once',
    () async {
      final changes = <bool>[];
      final screen = IctrlScreen(
        client: _DeviceClient(),
        sessionChanged: (active) async => changes.add(active),
      );
      screen.updateModelSession(title: 'Read Calculator');
      expect(screen.modelSession, isNull);
      expect(changes, isEmpty);
      await screen.connect();
      screen.updateModelSession(title: 'Read Calculator');
      final sessionId = screen.modelSession!.id;
      screen.updateModelSession(title: 'Calculate 7 + 8');
      expect(screen.modelSession!.id, sessionId);
      expect(screen.modelSession!.title, 'Calculate 7 + 8');
      expect(changes, [true]);
      await screen.disconnect();
      expect(screen.modelActive, false);
      expect(changes, [true, false]);
      screen.dispose();
      expect(changes, [true, false]);
    },
  );
  test('a live ref must retain its original label and element type', () async {
    final client = _DeviceClient();
    final screen = IctrlScreen(client: client);
    await screen.connect();
    final tree = await screen.snapshot(
      screenshot: false,
      cancel: CancelToken(),
    );
    client.hit['element_type'] = 'SecureTextField';
    await expectLater(
      screen.resolveNode(tree.token, 1, CancelToken()),
      throwsA(isA<ScreenException>()),
    );
    client.hit['element_type'] = 'Key';
    client.hit['label'] = 'Pay';
    await expectLater(
      screen.resolveNode(tree.token, 1, CancelToken()),
      throwsA(isA<ScreenException>()),
    );
    expect(client.calls.where((c) => c.$1 == 'tap'), isEmpty);
    screen.dispose();
  });
  test('new snapshots invalidate ids; fast taps skip settling', () async {
    final client = _DeviceClient();
    final screen = IctrlScreen(client: client);
    await screen.connect();
    final first = await screen.snapshot(
      screenshot: false,
      cancel: CancelToken(),
    );
    final second = await screen.snapshot(
      screenshot: false,
      cancel: CancelToken(),
    );
    await expectLater(
      screen.resolveNode(first.token, 1, CancelToken()),
      throwsA(isA<ScreenException>()),
    );
    await screen.resolveNode(second.token, 1, CancelToken());
    await screen.act(ScreenAction(action: 'tap', token: second.token, node: 1));
    expect(client.calls.last.$1, 'tap');
    expect(client.calls.last.$2, {
      'settle': false,
      'ref': 'live-ref',
      'fast': true,
    });
    expect(client.calls.where((c) => c.$1 == 'screenshot'), isEmpty);
    screen.dispose();
  });
  test('read-only locator failure uses a freshly matched point, once', () async {
    for (final failedLookup in [false, true]) {
      final client = _DeviceClient();
      final screen = IctrlScreen(client: client);
      await screen.connect();
      final tree = await screen.snapshot(
        screenshot: false,
        cancel: CancelToken(),
      );
      client.hit['exists'] = false;
      client.findFailure = failedLookup;
      client.source = {
        'bundle_id': 'com.apple.calculator',
        'source':
            "Application, label: 'Calculator', {{0, 0}, {440, 956}}\n  Key, label: '7', id: 'Seven', {{24, 184}, {60, 40}}",
      };
      await screen.resolveNode(tree.token, 1, CancelToken());
      await screen.act(ScreenAction(action: 'tap', token: tree.token, node: 1));
      final taps = client.calls.where((c) => c.$1 == 'tap');
      expect(taps, hasLength(1));
      expect(taps.single.$2['x'], 54);
      expect(taps.single.$2['y'], 204);
      expect(taps.single.$2, isNot(contains('ref')));
      expect(client.calls.where((c) => c.$1 == 'find_element'), hasLength(1));
      screen.dispose();
    }
  });
  test('locator fallback rejects a changed app or moved target', () async {
    for (final changedApp in [false, true]) {
      final client = _DeviceClient();
      final screen = IctrlScreen(client: client);
      await screen.connect();
      final tree = await screen.snapshot(
        screenshot: false,
        cancel: CancelToken(),
      );
      client.findFailure = true;
      client.source = {
        'bundle_id': changedApp ? 'com.example.other' : 'com.apple.calculator',
        'source':
            "Application, label: 'Calculator', {{0, 0}, {440, 956}}\n  Key, label: '7', id: 'Seven', {{20, ${changedApp ? 180 : 380}}, {60, 40}}",
      };
      await expectLater(
        screen.resolveNode(tree.token, 1, CancelToken()),
        throwsA(isA<ScreenException>()),
      );
      expect(client.calls.where((c) => c.$1 == 'tap'), isEmpty);
      screen.dispose();
    }
  });
  test(
    'iCTRL resolves real installed bundles and never launches ambiguous matches',
    () async {
      final client = _DeviceClient();
      final screen = IctrlScreen(client: client);
      await screen.connect();
      final tools = IctrlDeviceTools(
        screen: screen,
        native: const UnavailableDeviceTools(),
      );
      final resolved = await tools.invoke('resolve_app', {
        'name': 'Shopee',
      }, cancel: CancelToken());
      expect(resolved, {
        'apps': [
          {
            'name': 'Shopee',
            'package': 'com.beeasy.shopee.tw',
            'installed': true,
          },
        ],
      });
      expect(client.calls.where((c) => c.$1 == 'launch_app'), isEmpty);
      await tools.invoke('open_app', {'name': 'Shopee'}, cancel: CancelToken());
      expect(
        client.calls.where((c) => c.$1 == 'launch_app').single.$2['bundle_id'],
        'com.beeasy.shopee.tw',
      );
      expect(client.calls.where((c) => c.$1 == 'list_apps'), hasLength(1));
      client.apps.add({'name': 'Shopee Beta', 'bundle_id': 'com.example.beta'});
      final newTools = IctrlDeviceTools(
        screen: screen,
        native: const UnavailableDeviceTools(),
      );
      await expectLater(
        newTools.invoke('open_app', {
          'name': 'Shopee|Shopee Beta',
        }, cancel: CancelToken()),
        throwsA(isA<DeviceToolException>()),
      );
      expect(client.calls.where((c) => c.$1 == 'launch_app'), hasLength(1));
      screen.dispose();
    },
  );
  test(
    'a wrapper cannot shadow a labeled button during ref resolution',
    () async {
      final client = _DeviceClient()
        ..source = {
          'bundle_id': 'com.example.app',
          'source':
              "Application, label: 'App', {{0, 0}, {440, 956}}\n  Other, label: 'Next', {{0, 200}, {440, 100}}\n    Button, label: 'Next', {{20, 220}, {80, 40}}",
        }
        ..hit.addAll({
          'element_type': 'Button',
          'label': 'Next',
          'center_x': 60,
          'center_y': 240,
        });
      final screen = IctrlScreen(client: client);
      await screen.connect();
      final tree = await screen.snapshot(
        screenshot: false,
        cancel: CancelToken(),
      );
      await screen.resolveNode(tree.token, 2, CancelToken());
      await screen.act(ScreenAction(action: 'tap', token: tree.token, node: 2));
      expect(
        client.calls
            .where((c) => c.$1 == 'find_element')
            .single
            .$2['element_type'],
        'button',
      );
      expect(client.calls.last.$2['ref'], 'live-ref');
      screen.dispose();
    },
  );
  test(
    'landscape drag transforms both endpoints in the observed iCTRL frame',
    () async {
      final client = _DeviceClient()..landscape = true;
      final screen = IctrlScreen(client: client);
      await screen.connect();
      await screen.snapshot(screenshot: false, cancel: CancelToken());
      await screen.act(
        const ScreenAction(
          action: 'drag',
          x: 100,
          y: 120,
          toX: 200,
          toY: 240,
          duration: .3,
        ),
      );
      expect(client.calls.last.$2, {
        'settle': false,
        'from_x': 320.0,
        'from_y': 100.0,
        'to_x': 200.0,
        'to_y': 200.0,
        'duration': .3,
      });
      screen.dispose();
    },
  );
  test('static accessibility values include the displayed Calculator result', () {
    final tree = parseIctrlTree(
      {
        'bundle_id': 'com.apple.calculator',
        'source':
            "Application, label: 'Calculator', {{0, 0}, {440, 956}}\n  StaticText, label: 'Input', value: '15', {{50, 200}, {300, 80}}",
      },
      token: 1,
      width: 440,
      height: 956,
    );
    expect(tree.nodes[1].text, '15');
    expect(ScreenReading.from(tree).toToolText(), contains('15'));
  });
  test(
    'OCR duplicates match source and position; moved targets are rejected',
    () async {
      final client = _DeviceClient()
        ..source = {
          'bundle_id': 'com.apple.calculator',
          'source': "Application, label: 'Calculator', {{0, 0}, {440, 956}}",
          'channel': {'recommended': 'ocr'},
        }
        ..ocrItems = [
          {'label': 'Claim', 'x': 30, 'y': 200, 'width': 80, 'height': 30},
          {'label': 'Claim', 'x': 30, 'y': 500, 'width': 80, 'height': 30},
        ];
      final screen = IctrlScreen(client: client);
      await screen.connect();
      final tree = await screen.snapshot(
        screenshot: false,
        cancel: CancelToken(),
      );
      final info = await screen.resolveNode(tree.token, 1, CancelToken());
      expect(info.target?.bounds.top, 200);
      client.ocrItems[0]['y'] = 300;
      await expectLater(
        screen.resolveNode(tree.token, 1, CancelToken()),
        throwsA(isA<ScreenException>()),
      );
      expect(client.calls.where((c) => c.$1 == 'tap'), isEmpty);
      screen.dispose();
    },
  );
  test('OCR omits matching AX labels with whitespace differences', () {
    final tree = parseIctrlTree(
      {
        'bundle_id': 'com.apple.calculator',
        'source':
            "Application, {{0, 0}, {440, 956}}\n  Button, label: 'Claim  reward', {{30, 200}, {80, 30}}",
        'ocr_items': [
          {
            'label': 'Claim reward',
            'x': 31,
            'y': 201,
            'width': 78,
            'height': 28,
          },
        ],
      },
      token: 1,
      width: 440,
      height: 956,
    );
    expect(tree.nodes.where((n) => n.className == 'OCRText'), isEmpty);
    expect(
      ScreenReading.from(tree).elements.where((e) => e.label.contains('Claim')),
      hasLength(1),
    );
  });
  test(
    'OCR fragments inside named controls are omitted, custom text survives',
    () {
      final tree = parseIctrlTree(
        {
          'bundle_id': 'com.example.app',
          'source':
              "Application, {{0, 0}, {440, 956}}\n  Button, label: 'Project details', {{30, 200}, {200, 60}}",
          'ocr_items': [
            {'label': 'Pr0ject', 'x': 40, 'y': 210, 'width': 80, 'height': 20},
            {
              'label': 'Custom action',
              'x': 40,
              'y': 400,
              'width': 100,
              'height': 30,
            },
          ],
        },
        token: 1,
        width: 440,
        height: 956,
      );
      expect(
        tree.nodes.where((n) => n.className == 'OCRText').single.text,
        'Custom action',
      );
    },
  );
  test(
    'hierarchy preserves point bounds, landscape, fields and own-app exclusion',
    () {
      final tree = parseIctrlTree(
        {
          'bundle_id': 'com.apple.calculator',
          'source':
              "Application, label: 'Calculator', {{0, 0}, {956, 440}}\n  Window, {{0, 0}, {956, 440}}\n    Button, label: '7', id: 'Seven', {{16, 200}, {60, 40}}\n    SecureTextField, label: 'Password', value: 'SECRET', {{100, 200}, {200, 40}}",
        },
        token: 1,
        width: 440,
        height: 956,
      );
      expect(tree.width, 956);
      expect(tree.nodes[2].bounds.left, 16);
      expect(tree.nodes[3].text, isNull);
      expect(tree.nodes[3].password, true);
      final reading = ScreenReading.from(tree);
      expect(reading.toToolText(), isNot(contains('SECRET')));
      final own = parseIctrlTree(
        {
          'bundle_id': 'tw.avianjay.tako',
          'source': "Application, label: 'Tako', {{0, 0}, {440, 956}}",
        },
        token: 2,
        width: 440,
        height: 956,
      );
      expect(own.ownAppInFront, true);
      expect(own.nodes, isEmpty);
    },
  );
}

class _DeviceClient extends IctrlClient {
  factory _DeviceClient() {
    final secrets = {'ictrl.key.http://127.0.0.1:8200': '00' * 32};
    return _DeviceClient._(secrets);
  }
  _DeviceClient._(this.secrets)
    : super(
        readSecret: (key) async => secrets[key],
        writeSecret: (key, value) async {
          if (value == null) {
            secrets.remove(key);
          } else {
            secrets[key] = value;
          }
        },
      );
  final Map<String, String> secrets;
  final calls = <(String, Map<String, Object?>)>[];
  bool landscape = false;
  bool findFailure = false;
  final apps = <Map<String, Object?>>[
    {'name': 'Shopee', 'bundle_id': 'com.beeasy.shopee.tw'},
  ];
  Map<String, Object?>? source;
  List<Map<String, Object?>> sources = [];
  Map<String, Object?> actionReceipt = {};
  List<Map<String, Object?>> ocrItems = [];
  final hit = <String, Object?>{
    'exists': true,
    'hittable': true,
    'visibility': 'in_view',
    'element_type': 'Key',
    'label': '7',
    'ref': 'live-ref',
    'center_x': 50,
    'center_y': 200,
  };
  @override
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> params = const {},
    CancelToken? cancel,
  ]) async {
    calls.add((method, params));
    if (method == 'find_element' && findFailure) {
      throw const ScreenException('ictrl_rpc_failed_read_again');
    }
    if (method == 'page_source' && sources.isNotEmpty) {
      return sources.removeAt(0);
    }
    return switch (method) {
      'device_info' => {'point_width': 440, 'point_height': 956},
      'page_source' =>
        source ??
            {
              'bundle_id': 'com.apple.calculator',
              'source':
                  "Application, label: 'Calculator', {{0, 0}, {${landscape ? '956, 440' : '440, 956'}}}\n  Key, label: '7', id: 'Seven', {{20, 180}, {60, 40}}",
            },
      'screen_text' => {'items': ocrItems},
      'find_element' => hit,
      'tap' => actionReceipt,
      'resolve_app' => {'apps': apps},
      'list_apps' => {'apps': apps, 'source': 'opened_history'},
      _ => <String, Object?>{},
    };
  }
}

const requestVector =
    'LBWBVbibdCW0HNXl0ZoySDGyITO4zWNEeZftn9zQ5NohSRVhTnMrexYNVUnnbbsKOxt8H4cF/hL2EAA=';
const requestTag =
    '391271f359f0a5dfa2f70720fb3fcda7da039c145e7206cecccdfd43495c6ef2';
const responseVector =
    'LWcZwwj2XRJIwit1JHsuUgJxlfKQn7FMXU5BQkcw6Yo8vWPtRDu1cZH3okaD';
const responseTag =
    '2d17fb4458791311bacf5b2e3db2085fef89c0fc9f2283c653669c3c66a24336';
