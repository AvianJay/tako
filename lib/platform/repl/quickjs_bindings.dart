import 'dart:ffi';

import 'package:ffi/ffi.dart';

const _asset = 'package:tako/quickjs.dart';

@Native<Pointer<Void> Function(Int64)>(
  symbol: 'tako_qjs_create',
  assetId: _asset,
)
external Pointer<Void> _create(int memoryLimit);
@Native<Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32)>(
  symbol: 'tako_qjs_eval',
  assetId: _asset,
)
external int _eval(Pointer<Void> runtime, Pointer<Utf8> source, int budget);
@Native<Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32)>(
  symbol: 'tako_qjs_begin',
  assetId: _asset,
)
external int _begin(Pointer<Void> runtime, Pointer<Utf8> source, int budget);
@Native<Pointer<Utf8> Function(Pointer<Void>, Int32, Int32)>(
  symbol: 'tako_qjs_poll',
  assetId: _asset,
)
external Pointer<Utf8> _poll(Pointer<Void> runtime, int jobs, int budget);
@Native<Pointer<Utf8> Function(Pointer<Void>)>(
  symbol: 'tako_qjs_take_message',
  assetId: _asset,
)
external Pointer<Utf8> _takeMessage(Pointer<Void> runtime);
@Native<Void Function(Pointer<Void>)>(symbol: 'tako_qjs_free', assetId: _asset)
external void _free(Pointer<Void> pointer);
@Native<Void Function(Pointer<Void>)>(symbol: 'tako_qjs_close', assetId: _asset)
external void _close(Pointer<Void> runtime);

/// A bare language engine. No native IO globals or module loader are installed.
class QuickJsBindings {
  QuickJsBindings({int memoryLimit = 32 * 1024 * 1024})
    : _runtime = _create(memoryLimit) {
    if (_runtime == nullptr) throw StateError('javascript_memory_limit');
  }
  Pointer<Void> _runtime;
  bool eval(String source, {int budgetMs = 20}) =>
      _source(source, (value) => _eval(_runtime, value, budgetMs) != 0);
  bool begin(String source, {int budgetMs = 20}) =>
      _source(source, (value) => _begin(_runtime, value, budgetMs) != 0);
  String poll({int jobs = 16, int budgetMs = 10}) =>
      _text(_poll(_runtime, jobs, budgetMs))!;
  String? takeMessage() => _text(_takeMessage(_runtime));
  T _source<T>(String source, T Function(Pointer<Utf8>) action) {
    final value = source.toNativeUtf8();
    try {
      return action(value);
    } finally {
      malloc.free(value);
    }
  }

  String? _text(Pointer<Utf8> value) {
    if (value == nullptr) return null;
    try {
      return value.toDartString();
    } finally {
      _free(value.cast());
    }
  }

  void close() {
    if (_runtime == nullptr) return;
    _close(_runtime);
    _runtime = nullptr;
  }
}
