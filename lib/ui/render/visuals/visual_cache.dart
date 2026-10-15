/// A small least-recently-used map. Streaming re-renders a message on every
/// network chunk, and the chat list drops off-screen state; unchanged
/// visuals reuse their parse and layout from here.
class LruCache<K, V extends Object> {
  LruCache(this.capacity, {this.onEvict});

  final int capacity;
  final void Function(V value)? onEvict;
  final _entries = <K, V>{};

  int get length => _entries.length;

  V putIfAbsent(K key, V Function() create) {
    final value = _entries.remove(key) ?? create();
    _entries[key] = value;
    while (_entries.length > capacity) {
      final oldest = _entries.keys.first;
      onEvict?.call(_entries.remove(oldest)!);
    }
    return value;
  }

  void clear() {
    if (onEvict case final evict?) _entries.values.forEach(evict);
    _entries.clear();
  }
}
