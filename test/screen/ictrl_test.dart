import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tako/core/providers/cancel_token.dart';
import 'package:tako/core/screen/remote_screen.dart';
import 'package:tako/core/screen/screen_capability.dart';
import 'package:tako/core/screen/screen_reading.dart';
import 'package:tako/platform/ios/ictrl_client.dart';
import 'package:tako/platform/ios/ictrl_crypto.dart';
import 'package:tako/platform/ios/ictrl_screen.dart';
import 'package:tako/platform/ios/ictrl_tree.dart';

void main() {
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
  Map<String, Object?>? source;
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
