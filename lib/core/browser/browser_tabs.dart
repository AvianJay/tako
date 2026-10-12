/// At most this many tabs; the least recently used one gives way.
const maxBrowserTabs = 8;

/// The result of opening a tab: the tab to show and the tabs that had to be
/// closed to stay within the limit (their native views must be released).
typedef OpenedTab<T> = ({T tab, List<T> removed});

/// Tab bookkeeping of the in-app browser, independent of the WebView: which
/// tab is shown, which one the model uses during a response, and which one
/// gives way at the limit. [T] holds the platform's per-tab state.
class BrowserTabs<T> {
  BrowserTabs({
    required T Function(int id) create,
    required bool Function(T tab) isBlank,
    this.limit = maxBrowserTabs,
  }) : _create = create,
       _isBlank = isBlank {
    _show(_add());
  }

  final T Function(int id) _create;
  final bool Function(T tab) _isBlank;
  final int limit;
  final _tabs = <int, T>{};
  final _lastUsed = <int, int>{};
  final _byModel = <int>{};
  var _clock = 0;
  var _nextId = 1;
  var _active = 0;
  int? _modelTab;

  int get activeId => _active;
  T get active => _tabs[_active] as T;
  List<int> get ids => List.unmodifiable(_tabs.keys);
  int get length => _tabs.length;
  T? operator [](int id) => _tabs[id];

  /// The model opened this tab, in this or an earlier response.
  bool openedByModel(int id) => _byModel.contains(id);

  int _add() {
    final id = _nextId++;
    _tabs[id] = _create(id);
    _lastUsed[id] = ++_clock;
    return id;
  }

  void _show(int id) {
    _active = id;
    _lastUsed[id] = ++_clock;
  }

  T _remove(int id) {
    _lastUsed.remove(id);
    _byModel.remove(id);
    if (_modelTab == id) _modelTab = null;
    return _tabs.remove(id) as T;
  }

  int _leastRecent() =>
      _lastUsed.entries.reduce((a, b) => a.value <= b.value ? a : b).key;

  OpenedTab<T> _openNew() {
    final removed = <T>[];
    while (_tabs.length >= limit) {
      removed.add(_remove(_leastRecent()));
    }
    final id = _add();
    _show(id);
    return (tab: _tabs[id] as T, removed: removed);
  }

  /// A tab for the user, e.g. a link from the chat. A blank tab in front is
  /// reused.
  OpenedTab<T> openForUser() =>
      _isBlank(active) ? (tab: active, removed: <T>[]) : _openNew();

  /// The model's tab in this response: the one it already opened, a blank
  /// tab in front, or a new one. A page the user is on is never navigated
  /// away by the model.
  OpenedTab<T> openForModel() {
    final current = _modelTab;
    if (current != null && _tabs.containsKey(current)) {
      _show(current);
      return (tab: _tabs[current] as T, removed: <T>[]);
    }
    final opened = _isBlank(active)
        ? (tab: active, removed: <T>[])
        : _openNew();
    _modelTab = _active;
    _byModel.add(_active);
    return opened;
  }

  /// The response ended: the model's next page opens a tab of its own again.
  void endResponse() => _modelTab = null;

  bool select(int id) {
    if (!_tabs.containsKey(id)) return false;
    _show(id);
    return true;
  }

  /// Closes [id] and shows the most recently used remaining tab. Closing the
  /// last tab leaves a blank one.
  T? close(int id) {
    if (!_tabs.containsKey(id)) return null;
    final closed = _remove(id);
    if (_tabs.isEmpty) {
      _show(_add());
    } else if (_active == id) {
      _show(_lastUsed.entries.reduce((a, b) => a.value >= b.value ? a : b).key);
    }
    return closed;
  }

  /// Clearing browsing data closes every tab and leaves one blank tab.
  List<T> reset() {
    final removed = _tabs.values.toList();
    _tabs.clear();
    _lastUsed.clear();
    _byModel.clear();
    _modelTab = null;
    _show(_add());
    return removed;
  }
}
