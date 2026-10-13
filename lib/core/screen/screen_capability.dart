import 'package:flutter/foundation.dart';

import '../../platform/capabilities.dart';
import '../providers/cancel_token.dart';
import '../util/ids.dart';

class ScreenException implements Exception {
  const ScreenException(this.code, {this.detail});
  final String code;
  final String? detail;
  @override
  String toString() => code;
}

/// How a screen backend lets the model observe the screen. Android
/// reports an element tree; an iOS automation service reports screenshots.
enum ScreenObservationMode { elements, screenshot }

/// Node flags reported by the platform. Mirrors `ScreenFlags` in Kotlin.
abstract final class ScreenFlags {
  static const clickable = 1;
  static const longClickable = 2;
  static const editable = 4;
  static const scrollable = 8;
  static const checkable = 16;
  static const checked = 32;
  static const enabled = 64;
  static const focused = 128;
  static const selected = 256;
  static const password = 512;
  static const focusable = 1024;
  static const heading = 2048;
  static const imeEnter = 4096;
  static const multiLine = 8192;
}

/// Physical screen pixels.
class ScreenBounds {
  const ScreenBounds(this.left, this.top, this.right, this.bottom);
  final int left;
  final int top;
  final int right;
  final int bottom;
  int get width => right - left;
  int get height => bottom - top;
  int get area => width <= 0 || height <= 0 ? 0 : width * height;
}

/// One visible node. [parent] indexes the same list (-1 for a window root);
/// nodes are in preorder, so a subtree is a contiguous range.
class ScreenNode {
  const ScreenNode({
    this.parent = -1,
    this.window = 0,
    this.className = '',
    this.text,
    this.description,
    this.hint,
    this.viewId,
    this.state,
    this.flags = ScreenFlags.enabled,
    this.bounds = const ScreenBounds(0, 0, 0, 0),
    this.check = '',
  });

  final int parent;
  final int window;
  final String className;
  final String? text;
  final String? description;
  final String? hint;
  final String? viewId;
  final String? state;
  final int flags;
  final ScreenBounds bounds;

  /// The platform's fingerprint of the node and its subtree's text.
  final String check;

  bool _has(int flag) => flags & flag != 0;
  bool get clickable => _has(ScreenFlags.clickable);
  bool get longClickable => _has(ScreenFlags.longClickable);
  bool get editable => _has(ScreenFlags.editable);
  bool get scrollable => _has(ScreenFlags.scrollable);
  bool get checkable => _has(ScreenFlags.checkable);
  bool get checked => _has(ScreenFlags.checked);
  bool get enabled => _has(ScreenFlags.enabled);
  bool get focused => _has(ScreenFlags.focused);
  bool get selected => _has(ScreenFlags.selected);
  bool get password => _has(ScreenFlags.password);
  bool get heading => _has(ScreenFlags.heading);
  bool get actionable =>
      clickable || longClickable || editable || scrollable || checkable;
}

class ScreenWindow {
  const ScreenWindow({
    required this.id,
    required this.packageName,
    this.title,
    this.type = 1,
    this.own = false,
    this.bounds = const ScreenBounds(0, 0, 0, 0),
  });
  final int id;
  final String packageName;
  final String? title;

  /// Android `AccessibilityWindowInfo` type; 1 is an application window.
  final int type;
  final bool own;
  final ScreenBounds bounds;
}

/// The raw result of one screen read, before elements are chosen.
class ScreenTree {
  const ScreenTree({
    required this.token,
    required this.packageName,
    required this.appLabel,
    required this.width,
    required this.height,
    this.ownAppInFront = false,
    this.windows = const [],
    this.nodes = const [],
    this.truncated = false,
    this.image,
    this.imageWidth = 0,
    this.imageHeight = 0,
  });

  /// Identifies the platform's node map; ids from other reads are stale.
  final int token;
  final String packageName;
  final String appLabel;
  final int width;
  final int height;
  final bool ownAppInFront;
  final List<ScreenWindow> windows;
  final List<ScreenNode> nodes;
  final bool truncated;

  /// JPEG screenshot, when one was requested and available.
  final Uint8List? image;
  final int imageWidth;
  final int imageHeight;
}

/// A target re-read from the live screen before permission is asked: the
/// node, its ancestors (nearest first) and its subtree. Descendant parents
/// index the list `[target, ...descendants]`.
class ScreenTargetInfo {
  const ScreenTargetInfo({
    required this.token,
    required this.node,
    required this.window,
    required this.appLabel,
    this.target,
    this.ancestors = const [],
    this.descendants = const [],
    this.actionText = '',
    this.windowText = '',
    this.width = 0,
    this.height = 0,
  });
  final int token;
  final int node;
  final ScreenWindow window;
  final String appLabel;
  final ScreenNode? target;
  final List<ScreenNode> ancestors;
  final List<ScreenNode> descendants;

  /// Text of the clickable ancestor a tap on [target] reaches.
  final String actionText;

  /// Text of a dialog-sized window; empty for full-screen windows.
  final String windowText;
  final int width;
  final int height;
}

/// [action]: tap, long_press, set_text, scroll, swipe or key.
class ScreenAction {
  const ScreenAction({
    required this.action,
    this.token = -1,
    this.node = -1,
    this.check = '',
    this.x,
    this.y,
    this.windowId = -1,
    this.text,
    this.submit = false,
    this.direction,
    this.key,
    this.toX,
    this.toY,
    this.duration,
  });
  final String action;
  final int token;
  final int node;
  final String check;
  final double? x;
  final double? y;
  final int windowId;
  final String? text;
  final bool submit;
  final String? direction;
  final String? key;
  final double? toX;
  final double? toY;
  final double? duration;
}

class ScreenActionOutcome {
  const ScreenActionOutcome({
    required this.method,
    this.packageName = '',
    this.appLabel = '',
    this.changed = false,
    this.details = const {},
  });
  final String method;
  final String packageName;
  final String appLabel;
  final bool changed;
  final Map<String, Object?> details;
}

/// A localized approval prompt drawn over other apps.
class ScreenApproval {
  const ScreenApproval({
    required this.title,
    required this.subtitle,
    required this.details,
    required this.note,
    required this.arguments,
    required this.choices,
    required this.denyId,
    this.highRisk = false,
    this.highlight,
  });
  final String title;
  final String subtitle;
  final List<(String, String)> details;
  final String note;
  final String arguments;

  /// (id, label) pairs in display order.
  final List<(String, String)> choices;
  final String denyId;
  final bool highRisk;
  final ScreenBounds? highlight;
}

enum ScreenSessionPhase { acting, thinking, waitingApproval }

class ScreenSession {
  const ScreenSession({
    required this.id,
    required this.title,
    required this.phase,
  });
  final String id;
  final String title;
  final ScreenSessionPhase phase;
}

/// Localized status drawn by the native accessibility service.
class ScreenControlOverlay {
  const ScreenControlOverlay({
    required this.sessionId,
    required this.label,
    required this.title,
    required this.stop,
    required this.phase,
  });
  final String sessionId;
  final String label;
  final String title;
  final String stop;
  final ScreenSessionPhase phase;
}

/// Screen control. Reads happen only inside tools, after the
/// permission gate; status checks never read the screen.
abstract class ScreenCapability extends ChangeNotifier implements Capability {
  /// This build includes screen control (the Play build does not).
  bool get supported;

  /// The user enabled the accessibility service.
  bool get enabled;
  bool get screenshotsSupported;
  Set<ScreenObservationMode> get observationModes;
  Set<String> get supportedKeys => const {
    'back',
    'home',
    'recents',
    'notifications',
  };
  bool get supportsDrag => false;
  bool get supportsFastActions => false;

  @override
  bool get isAvailable => supported && enabled;

  Future<void> refresh();
  Future<void> openSettings();
  Future<void> openAppInfo();

  Future<ScreenTree> snapshot({
    required bool screenshot,
    required CancelToken cancel,
  });
  Future<ScreenTargetInfo> resolveNode(int token, int node, CancelToken cancel);
  Future<ScreenTargetInfo> resolvePoint(double x, double y, CancelToken cancel);
  Future<ScreenTargetInfo> resolveFocus(CancelToken cancel);

  /// Not bound to cancellation: once sent, an action is committed and its
  /// receipt must be kept, as with browser clicks.
  Future<ScreenActionOutcome> act(ScreenAction action);

  /// The model is acting on the screen in the current response.
  ScreenSession? _modelSession;
  ScreenSession? get modelSession => _modelSession;
  bool get modelActive => _modelSession != null;

  /// Stop from the "controlling the screen" notification.
  VoidCallback? onTakeOver;
  void beginModelSession() {
    if (!isAvailable || modelActive) return;
    _modelSession = ScreenSession(
      id: newId(),
      title: '',
      phase: ScreenSessionPhase.acting,
    );
    notifyListeners();
  }

  void updateModelSession({
    String? title,
    ScreenSessionPhase phase = ScreenSessionPhase.acting,
  }) {
    beginModelSession();
    final session = _modelSession;
    if (session == null) return;
    final text = title ?? session.title;
    if (text == session.title && phase == session.phase) return;
    _modelSession = ScreenSession(id: session.id, title: text, phase: phase);
    notifyListeners();
  }

  void endModelSession() {
    if (_modelSession == null) return;
    _modelSession = null;
    notifyListeners();
  }

  void takeOver() {
    endModelSession();
    onTakeOver?.call();
  }

  Future<void> showControlOverlay(ScreenControlOverlay overlay) async {}
  void hideControlOverlay({String? sessionId, bool endSession = false}) {}

  /// Shows [approval] over other apps; completes with the chosen id, or null.
  Future<String?> showApproval(ScreenApproval approval);
  void hideApproval();
}

/// Platforms without screen control, and tests.
class UnavailableScreen extends ScreenCapability {
  @override
  bool get supported => false;
  @override
  bool get enabled => false;
  @override
  bool get screenshotsSupported => false;
  @override
  Set<ScreenObservationMode> get observationModes => const {};
  @override
  Future<void> refresh() async {}
  @override
  Future<void> openSettings() async {}
  @override
  Future<void> openAppInfo() async {}
  @override
  Future<ScreenTree> snapshot({
    required bool screenshot,
    required CancelToken cancel,
  }) async => throw const ScreenException('screen_control_off');
  @override
  Future<ScreenTargetInfo> resolveNode(
    int token,
    int node,
    CancelToken cancel,
  ) async => throw const ScreenException('screen_control_off');
  @override
  Future<ScreenTargetInfo> resolvePoint(
    double x,
    double y,
    CancelToken cancel,
  ) async => throw const ScreenException('screen_control_off');
  @override
  Future<ScreenTargetInfo> resolveFocus(CancelToken cancel) async =>
      throw const ScreenException('screen_control_off');
  @override
  Future<ScreenActionOutcome> act(ScreenAction action) async =>
      throw const ScreenException('screen_control_off');
  @override
  bool get modelActive => false;
  @override
  void beginModelSession() {}
  @override
  void endModelSession() {}
  @override
  void takeOver() => onTakeOver?.call();
  @override
  Future<String?> showApproval(ScreenApproval approval) async => null;
  @override
  void hideApproval() {}
}
