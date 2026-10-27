import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/chat/agent_suspended.dart';
import 'package:tako/core/providers/cancel_token.dart';
import 'package:tako/platform/repl/quickjs_repl.dart';

void main() {
  late QuickJsRepl runtime;
  setUp(() => runtime = QuickJsRepl());
  tearDown(() => runtime.close());

  test(
    'a suspended host operation escapes JavaScript catch and stops later actions',
    () async {
      final calls = <String>[];
      await expectLater(
        runtime.evaluate(
          'try { await browser.read(); } catch (_) {} await browser.scroll({direction:"down"});',
          invoke: (method, _) async {
            calls.add(method);
            throw const AgentSuspended('approval');
          },
          cancel: CancelToken(),
        ),
        throwsA(isA<AgentSuspended>()),
      );
      expect(calls, ['browser.read']);
      final reset = await runtime.evaluate(
        '1 + 1',
        invoke: (_, _) async => {},
        cancel: CancelToken(),
      );
      expect(reset.value, 2);
    },
  );

  test(
    'top-level await, persistent var bindings and captured output',
    () async {
      final first = await runtime.evaluate(
        'var value = await Promise.resolve(40); console.log(value);',
        invoke: (_, _) async => {},
        cancel: CancelToken(),
      );
      expect(first.error, isNull);
      expect(first.output.trim(), '40');
      final second = await runtime.evaluate(
        'value += 2; value',
        invoke: (_, _) async => {},
        cancel: CancelToken(),
      );
      expect(second.value, 42);
    },
  );

  test(
    'host API awaits Futures and resumes the same JavaScript context',
    () async {
      final calls = <String>[];
      final result = await runtime.evaluate(
        'var page = await browser.read(); console.log(page.text); await browser.scroll({direction:"down"});',
        invoke: (method, args) async {
          calls.add(method);
          await Future<void>.delayed(Duration.zero);
          return {'text': 'observed page'};
        },
        cancel: CancelToken(),
      );
      expect(result.error, isNull);
      expect(calls, ['browser.read', 'browser.scroll']);
      expect(result.output.trim(), 'observed page');
    },
  );

  test('no filesystem, network, Node or module loader capabilities', () async {
    final result = await runtime.evaluate(
      '[typeof fetch,typeof process,typeof require,typeof std,typeof os].join(",")',
      invoke: (_, _) async => {},
      cancel: CancelToken(),
    );
    expect(result.value, 'undefined,undefined,undefined,undefined,undefined');
    final imported = await runtime.evaluate(
      'await import("fs")',
      invoke: (_, _) async => {},
      cancel: CancelToken(),
    );
    expect(imported.error, isNotNull);
    expect(imported.reset, isFalse);
  });

  test(
    'a failed host call keeps var bindings and carries its hint and details',
    () async {
      Future<Map<String, Object?>> missing(String _, List<Object?> _) async => {
        'error': 'app_not_found',
        'message': 'app_not_found: pass {package}',
        'details': {
          'similar': [
            {'name': '蝦皮購物', 'package': 'com.shopee.tw'},
          ],
        },
      };
      final failed = await runtime.evaluate(
        'var kept = 41; await phone.openApp({name: "Shopee"});',
        invoke: missing,
        cancel: CancelToken(),
      );
      expect(failed.error, 'Error: app_not_found: pass {package}');
      expect(failed.reset, isFalse);
      final caught = await runtime.evaluate(
        'var seen; try { await phone.openApp({name: "Shopee"}); } '
        'catch (e) { seen = (kept + 1) + ":" + e.code + ":" + e.details.similar[0].package; } seen',
        invoke: missing,
        cancel: CancelToken(),
      );
      expect(caught.error, isNull);
      expect(caught.value, '42:app_not_found:com.shopee.tw');
    },
  );

  test(
    'an infinite script is interrupted and the next call gets a fresh engine',
    () async {
      final timer = Stopwatch()..start();
      final result = await runtime.evaluate(
        'while(true) {}',
        invoke: (_, _) async => {},
        cancel: CancelToken(),
      );
      expect(result.error, contains('execution_limit'));
      expect(timer.elapsed, lessThan(const Duration(seconds: 2)));
      final recovered = await runtime.evaluate(
        '6 * 7',
        invoke: (_, _) async => {},
        cancel: CancelToken(),
      );
      expect(recovered.value, 42);
    },
  );

  test('unawaited host work never commits after the cell returns', () async {
    var calls = 0;
    final result = await runtime.evaluate(
      'phone.pressKey({key:"home"});',
      invoke: (_, _) async {
        calls++;
        return {};
      },
      cancel: CancelToken(),
    );
    expect(result.error, 'await_every_operation');
    expect(calls, 0);
  });

  test('a later await does not start an earlier detached action', () async {
    final calls = <String>[];
    final result = await runtime.evaluate(
      'phone.pressKey({key:"home"}); await phone.read();',
      invoke: (method, _) async {
        calls.add(method);
        return {};
      },
      cancel: CancelToken(),
    );
    expect(result.error, 'await_every_operation');
    expect(calls, ['phone.read']);
    expect(result.reset, isTrue);
  });

  test(
    'Stop during an in-flight host call waits for its eventual receipt',
    () async {
      final cancel = CancelToken();
      final started = Completer<void>();
      final finished = Completer<Map<String, Object?>>();
      final pending = runtime.evaluate(
        'await phone.pressKey({key:"home"});',
        invoke: (_, _) {
          started.complete();
          return finished.future;
        },
        cancel: cancel,
      );
      await started.future;
      cancel.cancel();
      finished.complete({'done': true});
      final result = await pending;
      expect(result.error, 'cancelled');
      expect(result.reset, isTrue);
    },
  );

  test(
    'output is bounded and unresolved promises cannot hang a task',
    () async {
      runtime.close();
      runtime = QuickJsRepl(maxOutputChars: 100);
      final logged = await runtime.evaluate(
        'console.log("a".repeat(1000));',
        invoke: (_, _) async => {},
        cancel: CancelToken(),
      );
      expect(logged.output.length, lessThanOrEqualTo(101));
      final result = await runtime.evaluate(
        'await new Promise(() => {});',
        invoke: (_, _) async => {},
        cancel: CancelToken(),
      );
      expect(result.error, 'unresolved_promise');
    },
  );
}
