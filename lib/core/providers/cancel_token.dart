import 'dart:async';

class RequestCancelled implements Exception {
  const RequestCancelled();
  @override
  String toString() => 'Request cancelled';
}

class CancelToken {
  final _cancelled = Completer<void>();
  final _listeners = <void Function()>{};
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (isCancelled) return;
    _cancelled.complete();
    for (final listener in _listeners.toList()) {
      listener();
    }
    _listeners.clear();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const RequestCancelled();
  }

  void addListener(void Function() listener) {
    if (isCancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void removeListener(void Function() listener) => _listeners.remove(listener);

  Future<T> bind<T>(Future<T> future) {
    throwIfCancelled();
    return Future.any([
      future,
      whenCancelled.then<T>((_) => throw const RequestCancelled()),
    ]);
  }
}
