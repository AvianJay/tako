import 'dart:async';
import 'dart:convert';

import '../../core/providers/cancel_token.dart';
import '../../core/repl/repl_runtime.dart';
import 'quickjs_bindings.dart';

/// One lazy, memory-bounded task runtime. Only the host's audited API is exposed.
class QuickJsRepl implements ReplRuntime {
  QuickJsRepl({this.maxOutputChars = 6000});
  final int maxOutputChars;
  QuickJsBindings? _engine;
  bool _running = false;

  @override
  Future<ReplEvaluation> evaluate(
    String code, {
    required ReplInvoke invoke,
    required CancelToken cancel,
  }) async {
    if (_running) return const ReplEvaluation(error: 'repl_busy');
    _running = true;
    final output = StringBuffer();
    final cpu = Stopwatch();
    final idle = Stopwatch()..start();
    final scheduled = <String>{};
    var calls = 0;
    try {
      cancel.throwIfCancelled();
      final engine = _engine ??= QuickJsBindings();
      if (!engine.eval(_bootstrap)) {
        throw StateError('repl_initialization_failed');
      }
      cpu.start();
      engine.begin(code);
      var status = jsonDecode(engine.poll(jobs: 0)) as Map<String, dynamic>;
      cpu.stop();
      while (true) {
        cancel.throwIfCancelled();
        String? message;
        while ((message = engine.takeMessage()) != null) {
          final packet = jsonDecode(message!) as Map<String, dynamic>;
          if (packet['kind'] == 'scheduled' && packet['id'] is String) {
            scheduled.add(packet['id'] as String);
            continue;
          }
          if (packet['kind'] == 'log') {
            final text = packet['text'];
            if (text is String && output.length < maxOutputChars) {
              final room = maxOutputChars - output.length;
              output.writeln(
                text.length > room ? text.substring(0, room) : text,
              );
            }
            continue;
          }
          if (packet['kind'] != 'call' ||
              packet['method'] is! String ||
              packet['args'] is! List) {
            throw StateError('invalid_repl_request');
          }
          // Reject detached work before any host action starts. A caller must await it.
          if (status['done'] == true) throw StateError('await_every_operation');
          if (!scheduled.remove(packet['id'])) {
            throw StateError('invalid_repl_request');
          }
          if (++calls > 64) throw StateError('repl_call_limit');
          Map<String, Object?> response;
          try {
            response = await invoke(
              packet['method'] as String,
              (packet['args'] as List).cast<Object?>(),
            );
          } catch (_) {
            response = const {'error': 'operation_failed'};
          }
          cancel.throwIfCancelled();
          final error = response['error'];
          final source =
              '__takoResolve(${jsonEncode(packet['id'])},${error == null},${jsonEncode(error ?? response)});';
          cpu.start();
          if (!engine.eval(source)) throw StateError('javascript_error');
          cpu.stop();
          idle.reset();
        }
        if (status['error'] case final String error) {
          close();
          return ReplEvaluation(
            output: output.toString(),
            error: _short(error),
            reset: true,
          );
        }
        if (status['done'] == true) {
          if (status['jobs'] == true || scheduled.isNotEmpty) {
            throw StateError('await_every_operation');
          }
          return ReplEvaluation(
            value: status['value'],
            output: output.toString(),
          );
        }
        if (cpu.elapsedMilliseconds > 1000) {
          throw StateError('javascript_cpu_limit');
        }
        if (idle.elapsedMilliseconds > 1500) {
          throw StateError('unresolved_promise');
        }
        await Future<void>.delayed(const Duration(milliseconds: 1));
        cpu.start();
        status = jsonDecode(engine.poll()) as Map<String, dynamic>;
        cpu.stop();
      }
    } on RequestCancelled {
      close();
      return ReplEvaluation(
        output: output.toString(),
        error: 'cancelled',
        reset: true,
      );
    } catch (error) {
      close();
      return ReplEvaluation(
        output: output.toString(),
        error: error is StateError ? _short(error.message) : 'javascript_error',
        reset: true,
      );
    } finally {
      _running = false;
    }
  }

  String _short(String text) =>
      text.length > 300 ? '${text.substring(0, 300)}…' : text;
  @override
  void close() {
    _engine?.close();
    _engine = null;
  }
}

// Captured intrinsics keep host responses independent from user modifications.
// No timers, Node globals, filesystem or network/module loader are provided.
const _bootstrap = r'''
(() => {
  if (globalThis.__takoReady) return;
  const queue = __takoQueue, stringify = JSON.stringify, pending = new Map();
  const freeze = Object.freeze, PromiseClass = Promise, then = Promise.prototype.then;
  let next = 0;
  // Start host work only when the returned awaitable is consumed. A detached
  // call must not execute merely because a later operation keeps the cell alive.
  const call = (method, args) => {
    const id = String(++next);
    queue(stringify({kind: 'scheduled', id}));
    let promise;
    const start = () => promise ??= new PromiseClass((resolve, reject) => {
      pending.set(id, {resolve, reject});
      try { queue(stringify({kind: 'call', id, method, args})); }
      catch (error) { pending.delete(id); reject(error); }
    });
    return freeze({then: (resolve, reject) => then.call(start(), resolve, reject)});
  };
  Object.defineProperty(globalThis, '__takoResolve', {value: (id, ok, value) => {
    const entry = pending.get(id);
    if (!entry) return;
    pending.delete(id);
    if (ok) entry.resolve(value); else entry.reject(new Error(String(value)));
  }});
  const api = (group, methods) => Object.freeze(Object.fromEntries(
    methods.map(method => [method, (...args) => call(group + '.' + method, args)])));
  Object.defineProperty(globalThis, 'browser', {value: api('browser',
    ['open', 'read', 'click', 'type', 'scroll', 'back'])});
  Object.defineProperty(globalThis, 'phone', {value: api('phone',
    ['openApp', 'read', 'tap', 'longPress', 'type', 'scroll', 'swipe', 'pressKey',
     'drag', 'openUrl', 'resolveApp', 'sequence', 'workflow', 'replay'])});
  const log = (...args) => queue(stringify({kind: 'log', text: args.map(value => {
    if (typeof value === 'string') return value;
    try { return stringify(value); } catch (_) { return '[unserializable]'; }
  }).join(' ')}));
  Object.defineProperty(globalThis, 'console', {value: Object.freeze({log, info: log, warn: log, error: log})});
  Object.defineProperty(globalThis, '__takoReady', {value: true});
})()
''';
