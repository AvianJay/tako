import 'dart:async';
import 'dart:typed_data';

import 'package:tako/core/providers/cancel_token.dart';
import 'package:tako/core/screen/screen_capability.dart';

const _enabled = ScreenFlags.enabled;
const _tappable = ScreenFlags.enabled | ScreenFlags.clickable;

/// A node of a fake app screen. [opens] names the view a tap shows;
/// [submits] the view shown after typing with submit.
class FakeNode {
  FakeNode(
    this.className, {
    this.text,
    this.description,
    this.hint,
    this.viewId,
    this.flags = _enabled,
    this.children = const [],
    this.opens,
    this.submits,
    this.bounds,
  });
  final String className;
  String? text;
  String? description;
  final String? hint;
  final String? viewId;
  int flags;
  final List<FakeNode> children;
  final String? opens;
  final String? submits;
  final ScreenBounds? bounds;
}

FakeNode box(List<FakeNode> children, {String? viewId}) =>
    FakeNode('android.widget.LinearLayout', children: children, viewId: viewId);
FakeNode row(List<FakeNode> children, {String? opens, ScreenBounds? bounds}) =>
    FakeNode(
      'android.widget.LinearLayout',
      flags: _tappable,
      children: children,
      opens: opens,
      bounds: bounds,
    );
FakeNode label(String text, {ScreenBounds? bounds}) =>
    FakeNode('android.widget.TextView', text: text, bounds: bounds);
FakeNode button(String text, {String? opens}) => FakeNode(
  'android.widget.Button',
  text: text,
  flags: _tappable,
  opens: opens,
);
FakeNode icon({
  String? description,
  String? viewId,
  String? opens,
  bool clickable = true,
  ScreenBounds? bounds,
}) => FakeNode(
  clickable ? 'android.widget.ImageButton' : 'android.widget.ImageView',
  description: description,
  viewId: viewId,
  flags: clickable ? _tappable : _enabled,
  opens: opens,
  bounds: bounds,
);
FakeNode toggle(String text, {bool on = false}) => FakeNode(
  'android.widget.Switch',
  text: text,
  flags: _tappable | ScreenFlags.checkable | (on ? ScreenFlags.checked : 0),
);
FakeNode field({
  String? hint,
  String? description,
  String? text,
  bool password = false,
  String? submits,
  String? viewId,
}) => FakeNode(
  'android.widget.EditText',
  hint: hint,
  description: description,
  text: text,
  viewId: viewId,
  submits: submits,
  flags:
      _tappable |
      ScreenFlags.editable |
      ScreenFlags.focusable |
      (password ? ScreenFlags.password : 0),
);
FakeNode list(List<FakeNode> children) => FakeNode(
  'androidx.recyclerview.widget.RecyclerView',
  flags: _enabled | ScreenFlags.scrollable,
  children: children,
);

class FakeWindow {
  FakeWindow(
    this.root, {
    this.title,
    this.bounds = const ScreenBounds(0, 0, 1080, 2400),
    this.packageName,
  });
  final FakeNode root;
  final String? title;
  final ScreenBounds bounds;

  /// Defaults to the view's package.
  final String? packageName;
}

/// One state of the screen: the front app and its windows, top first.
class FakeView {
  FakeView(this.packageName, this.appLabel, this.windows);
  final String packageName;
  final String appLabel;
  final List<FakeWindow> windows;
}

class _Flat {
  _Flat(this.node, this.parent, this.window);
  final FakeNode node;
  final int parent;
  final int window;
}

/// Screen control over scripted views. Reads and actions follow the real
/// contract: ids are per read, nodes are re-checked before acting.
class FakeScreen extends ScreenCapability {
  FakeScreen(this.views, {required String start, this.screenshots = false})
    : _current = start;

  final Map<String, FakeView> views;
  final bool screenshots;
  String _current;
  final _back = <String>[];
  int _token = 0;
  List<_Flat> _flat = [];
  bool enabledValue = true;
  final actions = <ScreenAction>[];
  final approvals = <ScreenApproval>[];
  Completer<String?>? _approval;
  int sessions = 0;
  int refreshes = 0;
  final controlOverlays = <ScreenControlOverlay>[];
  final hiddenControlSessions = <(String?, bool)>[];

  String get current => _current;
  FakeView get view => views[_current]!;

  /// The view the app [packageName] shows when launched.
  void launch(String packageName) {
    final key = views.entries
        .firstWhere((entry) => entry.value.packageName == packageName)
        .key;
    _back.add(_current);
    _current = key;
  }

  void show(String key) {
    _back.add(_current);
    _current = key;
  }

  /// Completes the pending over-app approval.
  void answerApproval(String? id) => _approval?.complete(id);

  @override
  bool get supported => true;
  @override
  bool get enabled => enabledValue;
  @override
  bool get screenshotsSupported => screenshots;
  @override
  Set<ScreenObservationMode> get observationModes => {
    ScreenObservationMode.elements,
    if (screenshots) ScreenObservationMode.screenshot,
  };
  @override
  Future<void> refresh() async => refreshes++;
  @override
  Future<void> openSettings() async {}
  @override
  Future<void> openAppInfo() async {}

  static String _check(List<_Flat> flat, int index) {
    final node = flat[index].node;
    final texts = <String>[];
    void walk(FakeNode current) {
      for (final child in current.children) {
        final text = child.text ?? child.description;
        if (text != null && texts.length < 30) texts.add(text);
        walk(child);
      }
    }

    walk(node);
    const identity =
        ScreenFlags.clickable |
        ScreenFlags.editable |
        ScreenFlags.password |
        ScreenFlags.checkable;
    return [
      node.className,
      node.viewId,
      node.text,
      node.description,
      node.hint,
      node.flags & identity,
      ...texts,
    ].join('|');
  }

  List<_Flat> _flatten() {
    final flat = <_Flat>[];
    final windows = view.windows;
    for (var window = 0; window < windows.length; window++) {
      void walk(FakeNode node, int parent) {
        final index = flat.length;
        flat.add(_Flat(node, parent, window));
        for (final child in node.children) {
          walk(child, index);
        }
      }

      walk(windows[window].root, -1);
    }
    return flat;
  }

  ScreenBounds _bounds(_Flat flat, int index) =>
      flat.node.bounds ??
      ScreenBounds(0, 100 + index * 80, 1080, 180 + index * 80);

  ScreenNode _node(List<_Flat> flat, int index, {int parentOffset = 0}) {
    final item = flat[index];
    return ScreenNode(
      parent: item.parent < 0 ? -1 : item.parent - parentOffset,
      window: item.window,
      className: item.node.className,
      text: item.node.text,
      description: item.node.description,
      hint: item.node.hint,
      viewId: item.node.viewId,
      flags: item.node.flags,
      bounds: _bounds(item, index),
      check: _check(flat, index),
    );
  }

  ScreenWindow _window(int index) {
    final window = view.windows[index];
    return ScreenWindow(
      id: index + 1,
      packageName: window.packageName ?? view.packageName,
      title: window.title,
      bounds: window.bounds,
      own: (window.packageName ?? view.packageName) == ownPackage,
    );
  }

  static const ownPackage = 'tw.avianjay.tako';

  @override
  Future<ScreenTree> snapshot({
    required bool screenshot,
    required CancelToken cancel,
  }) async {
    cancel.throwIfCancelled();
    if (!enabledValue) throw const ScreenException('screen_control_off');
    final own = view.packageName == ownPackage;
    _flat = own ? [] : _flatten();
    _token++;
    return ScreenTree(
      token: _token,
      packageName: view.packageName,
      appLabel: view.appLabel,
      width: 1080,
      height: 2400,
      ownAppInFront: own,
      windows: own
          ? const []
          : [for (var i = 0; i < view.windows.length; i++) _window(i)],
      nodes: [for (var i = 0; i < _flat.length; i++) _node(_flat, i)],
      image: screenshot && screenshots ? Uint8List.fromList([1, 2, 3]) : null,
      imageWidth: screenshot && screenshots ? 540 : 0,
      imageHeight: screenshot && screenshots ? 1200 : 0,
    );
  }

  /// The live index of a node read under [token], or an error code.
  int _live(int token, int index) {
    if (token != _token) throw const ScreenException('stale_ids_read_again');
    if (index < 0 || index >= _flat.length) {
      throw const ScreenException('unknown_id');
    }
    final live = _flatten();
    final at = live.indexWhere(
      (item) => identical(item.node, _flat[index].node),
    );
    if (at < 0) throw const ScreenException('element_gone_read_again');
    return at;
  }

  ScreenTargetInfo _describe(List<_Flat> live, int at, {int node = -1}) {
    final end = _subtreeEnd(live, at);
    final ancestors = <ScreenNode>[];
    for (
      var parent = live[at].parent;
      parent >= 0;
      parent = live[parent].parent
    ) {
      ancestors.add(_node(live, parent));
    }
    var reach = at;
    while (reach >= 0 && live[reach].node.flags & ScreenFlags.clickable == 0) {
      reach = live[reach].parent;
    }
    final actionText = reach >= 0 && reach != at
        ? _texts(live, reach, _subtreeEnd(live, reach))
        : '';
    final window = view.windows[live[at].window];
    final small = window.bounds.area < 1080 * 2400 * 9 ~/ 10;
    final windowStart = live.indexWhere(
      (item) => item.window == live[at].window,
    );
    return ScreenTargetInfo(
      token: _token,
      node: node,
      window: _window(live[at].window),
      appLabel: view.appLabel,
      target: _node(live, at, parentOffset: at),
      ancestors: ancestors,
      descendants: [
        for (var i = at + 1; i <= end; i++) _node(live, i, parentOffset: at),
      ],
      actionText: actionText,
      windowText: small
          ? _texts(live, windowStart, _subtreeEnd(live, windowStart))
          : '',
      width: 1080,
      height: 2400,
    );
  }

  static int _subtreeEnd(List<_Flat> flat, int index) {
    var end = index;
    for (var i = index + 1; i < flat.length; i++) {
      var parent = flat[i].parent;
      while (parent > index) {
        parent = flat[parent].parent;
      }
      if (parent != index) break;
      end = i;
    }
    return end;
  }

  static String _texts(List<_Flat> flat, int start, int end) => [
    for (var i = start; i <= end; i++)
      ?(flat[i].node.text ?? flat[i].node.description),
  ].join(' ');

  @override
  Future<ScreenTargetInfo> resolveNode(
    int token,
    int node,
    CancelToken cancel,
  ) async {
    final at = _live(token, node);
    return _describe(_flatten(), at, node: node);
  }

  int _hit(double x, double y) {
    final live = _flatten();
    for (var window = 0; window < view.windows.length; window++) {
      final bounds = view.windows[window].bounds;
      if (x < bounds.left ||
          x >= bounds.right ||
          y < bounds.top ||
          y >= bounds.bottom) {
        continue;
      }
      var hit = -1;
      for (var i = 0; i < live.length; i++) {
        if (live[i].window != window) continue;
        final box = _bounds(live[i], i);
        if (x >= box.left && x < box.right && y >= box.top && y < box.bottom) {
          hit = i;
        }
      }
      if (hit >= 0) return hit;
    }
    throw const ScreenException('point_outside_screen');
  }

  @override
  Future<ScreenTargetInfo> resolvePoint(
    double x,
    double y,
    CancelToken cancel,
  ) async => _describe(_flatten(), _hit(x, y));

  @override
  Future<ScreenTargetInfo> resolveFocus(CancelToken cancel) async {
    final live = _flatten();
    final at = live.indexWhere(
      (item) => item.node.flags & ScreenFlags.editable != 0,
    );
    if (at < 0) throw const ScreenException('no_focused_field');
    return _describe(live, at);
  }

  @override
  Future<ScreenActionOutcome> act(ScreenAction action) async {
    actions.add(action);
    final live = _flatten();
    int? at;
    if (action.node >= 0) {
      at = _live(action.token, action.node);
    } else if (action.x != null && action.y != null) {
      at = _hit(action.x!, action.y!);
    } else if (action.action == 'set_text') {
      at = live.indexWhere(
        (item) => item.node.flags & ScreenFlags.editable != 0,
      );
    }
    if (at != null && at >= 0 && _check(live, at) != action.check) {
      throw const ScreenException('element_changed_read_again');
    }
    switch (action.action) {
      case 'tap':
      case 'long_press':
        var reach = at!;
        while (reach >= 0 && live[reach].node.opens == null) {
          reach = live[reach].parent;
        }
        if (reach >= 0) show(live[reach].node.opens!);
      case 'set_text':
        final node = live[at!].node;
        if (node.flags & ScreenFlags.password != 0) {
          throw const ScreenException('password_entry_blocked');
        }
        node.text = action.text;
        if (action.submit && node.submits != null) show(node.submits!);
      case 'key':
        if (action.key == 'back' && _back.isNotEmpty) {
          _current = _back.removeLast();
        } else if (action.key == 'home') {
          show(views.keys.first);
        }
    }
    return ScreenActionOutcome(
      method: action.action == 'set_text'
          ? (action.submit ? 'set_text_submitted' : 'set_text')
          : 'click',
      packageName: view.packageName,
      appLabel: view.appLabel,
      changed: true,
    );
  }

  @override
  void beginModelSession() {
    if (modelActive || !isAvailable) return;
    sessions++;
    super.beginModelSession();
  }

  @override
  Future<void> showControlOverlay(ScreenControlOverlay overlay) async {
    controlOverlays.add(overlay);
  }

  @override
  void hideControlOverlay({String? sessionId, bool endSession = false}) {
    hiddenControlSessions.add((sessionId, endSession));
  }

  @override
  Future<String?> showApproval(ScreenApproval approval) {
    approvals.add(approval);
    _approval = Completer<String?>();
    return _approval!.future;
  }

  @override
  void hideApproval() {
    final pending = _approval;
    _approval = null;
    if (pending != null && !pending.isCompleted) pending.complete(null);
  }
}

/// Settings → About phone → Android version; a messaging app with a
/// compose box and a Send button; a delete dialog; Tako itself.
FakeScreen phoneScreen({bool screenshots = false}) => FakeScreen(
  {
    'launcher': FakeView('com.android.launcher3', 'Launcher', [
      FakeWindow(box([label('Settings'), label('Messages')])),
    ]),
    'settings': FakeView('com.android.settings', 'Settings', [
      FakeWindow(
        box([
          FakeNode(
            'android.widget.TextView',
            text: 'Settings',
            flags: _enabled | ScreenFlags.heading,
          ),
          list([
            row([
              label('Network & internet'),
              label('Wi-Fi, mobile'),
            ], opens: 'settings/network'),
            row([
              label('About phone'),
              label('Pixel fixture'),
            ], opens: 'settings/about'),
          ]),
        ]),
        title: 'Settings',
      ),
    ]),
    'settings/network': FakeView('com.android.settings', 'Settings', [
      FakeWindow(
        box([
          toggle('Wi-Fi', on: true),
          row([label('Mobile network')]),
        ]),
        title: 'Network & internet',
      ),
    ]),
    'settings/about': FakeView('com.android.settings', 'Settings', [
      FakeWindow(
        box([
          row([label('Device name'), label('Pixel fixture')]),
          row([
            label('Android version'),
            label('15'),
          ], opens: 'settings/version'),
        ]),
        title: 'About phone',
      ),
    ]),
    'settings/version': FakeView('com.android.settings', 'Settings', [
      FakeWindow(
        box([
          label('Android version'),
          label('15'),
          label('Security update'),
          label('October 5, 2026'),
        ]),
        title: 'Android version',
      ),
    ]),
    'messages': FakeView('com.example.messages', 'Messages', [
      FakeWindow(
        box([
          label('Alex'),
          label('See you at 7?'),
          field(hint: 'Message', submits: 'messages/sent'),
          // A clickable container whose only text is in a child; the
          // unlabeled icon inside it is what a point tap would hit.
          row(
            [
              icon(
                clickable: false,
                viewId: 'com.example:id/plane',
                bounds: const ScreenBounds(900, 2210, 1000, 2290),
              ),
              label('Send', bounds: const ScreenBounds(100, 2210, 800, 2290)),
            ],
            opens: 'messages/sent',
            bounds: const ScreenBounds(0, 2200, 1080, 2300),
          ),
          icon(description: 'Send message', opens: 'messages/sent'),
          icon(viewId: 'com.example:id/send_button', opens: 'messages/sent'),
          icon(description: 'Attach', opens: 'messages'),
          field(hint: 'Search messages', submits: 'messages/search'),
          field(hint: 'Password', password: true),
          field(description: 'PIN code'),
          button('Delete chat', opens: 'messages/delete'),
        ]),
        title: 'Alex',
      ),
    ]),
    'messages/sent': FakeView('com.example.messages', 'Messages', [
      FakeWindow(box([label('Sent')]), title: 'Alex'),
    ]),
    'messages/search': FakeView('com.example.messages', 'Messages', [
      FakeWindow(box([label('No results')]), title: 'Search'),
    ]),
    'messages/delete': FakeView('com.example.messages', 'Messages', [
      FakeWindow(
        box([
          label('Delete this conversation?'),
          button('Cancel', opens: 'messages'),
          button('OK', opens: 'messages/sent'),
        ]),
        title: 'Delete',
        bounds: const ScreenBounds(100, 900, 980, 1500),
      ),
      FakeWindow(box([label('Alex')]), title: 'Alex'),
    ]),
    'shade': FakeView('com.android.systemui', 'System UI', [
      FakeWindow(box([toggle('Bluetooth'), label('2 notifications')])),
    ]),
    'tako': FakeView(FakeScreen.ownPackage, 'Tako', [
      FakeWindow(box([label('Chat')])),
    ]),
  },
  start: 'tako',
  screenshots: screenshots,
);
