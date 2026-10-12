import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'tako',
    dartOut: 'lib/platform/android/control_api.g.dart',
    kotlinOut: 'android/app/src/main/kotlin/tw/avianjay/tako/ControlApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'tw.avianjay.tako',
      errorClassName: 'ControlError',
    ),
  ),
)
/// Whether this build includes screen control and the user enabled it.
class ScreenStatusData {
  ScreenStatusData({
    required this.supported,
    required this.enabled,
    required this.screenshots,
  });
  bool supported;
  bool enabled;
  bool screenshots;
}

/// A window on screen. Coordinates are physical screen pixels.
class ScreenWindowData {
  ScreenWindowData({
    required this.id,
    required this.packageName,
    this.title,
    required this.type,
    required this.own,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });
  int id;
  String packageName;
  String? title;
  int type;
  bool own;
  int left;
  int top;
  int right;
  int bottom;
}

/// One visible accessibility node. [parent] indexes the same list (-1 for a
/// window root); [check] fingerprints the node's identity and visible text.
class ScreenNodeData {
  ScreenNodeData({
    required this.parent,
    required this.window,
    required this.className,
    this.text,
    this.description,
    this.hint,
    this.viewId,
    this.state,
    required this.flags,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.check,
  });
  int parent;
  int window;
  String className;
  String? text;
  String? description;
  String? hint;
  String? viewId;
  String? state;
  int flags;
  int left;
  int top;
  int right;
  int bottom;
  String check;
}

class ScreenSnapshotData {
  ScreenSnapshotData({
    required this.token,
    required this.packageName,
    required this.appLabel,
    required this.width,
    required this.height,
    required this.ownAppInFront,
    required this.windows,
    required this.nodes,
    required this.truncated,
    this.image,
    required this.imageWidth,
    required this.imageHeight,
  });
  int token;
  String packageName;
  String appLabel;
  int width;
  int height;
  bool ownAppInFront;
  List<ScreenWindowData> windows;
  List<ScreenNodeData> nodes;
  bool truncated;
  Uint8List? image;
  int imageWidth;
  int imageHeight;
}

/// A target re-read from the live screen before permission is asked.
/// [descendants] parents index the list [target, ...descendants];
/// [actionText] is the text of the clickable ancestor a tap would reach.
class ScreenTargetData {
  ScreenTargetData({
    required this.token,
    required this.node,
    required this.window,
    required this.appLabel,
    this.target,
    required this.ancestors,
    required this.descendants,
    required this.actionText,
    required this.windowText,
    required this.width,
    required this.height,
  });
  int token;
  int node;
  ScreenWindowData window;
  String appLabel;
  ScreenNodeData? target;
  List<ScreenNodeData> ancestors;
  List<ScreenNodeData> descendants;
  String actionText;
  String windowText;
  int width;
  int height;
}

/// [action]: tap, long_press, set_text, scroll, swipe or key. Node actions
/// carry the snapshot token, node index and the fingerprint approved by the
/// user; point actions carry the window resolved before approval.
class ScreenActionData {
  ScreenActionData({
    required this.action,
    required this.token,
    required this.node,
    required this.check,
    this.x,
    this.y,
    required this.windowId,
    this.text,
    required this.submit,
    this.direction,
    this.key,
  });
  String action;
  int token;
  int node;
  String check;
  double? x;
  double? y;
  int windowId;
  String? text;
  bool submit;
  String? direction;
  String? key;
}

class ScreenActionResultData {
  ScreenActionResultData({
    required this.method,
    required this.packageName,
    required this.appLabel,
    required this.changed,
  });
  String method;
  String packageName;
  String appLabel;
  bool changed;
}

/// Localized approval prompt drawn over other apps while Tako is hidden.
class ApprovalOverlayData {
  ApprovalOverlayData({
    required this.title,
    required this.subtitle,
    required this.detailLabels,
    required this.detailValues,
    required this.note,
    required this.arguments,
    required this.choiceIds,
    required this.choiceLabels,
    required this.denyId,
    required this.highRisk,
    this.left,
    this.top,
    this.right,
    this.bottom,
  });
  String title;
  String subtitle;
  List<String> detailLabels;
  List<String> detailValues;
  String note;
  String arguments;
  List<String> choiceIds;
  List<String> choiceLabels;
  String denyId;
  bool highRisk;
  int? left;
  int? top;
  int? right;
  int? bottom;
}

@HostApi()
abstract class ScreenApi {
  ScreenStatusData status();
  void openSettings();
  void openAppInfo();
  @async
  ScreenSnapshotData snapshot(bool screenshot, int maxNodes);
  @async
  ScreenTargetData resolveNode(int token, int node);
  @async
  ScreenTargetData resolvePoint(double x, double y);

  /// The focused text field, for type_text without an id or point.
  @async
  ScreenTargetData resolveFocus();
  @async
  ScreenActionResultData act(ScreenActionData action);

  /// Returns the chosen choice ID, or null when hidden without a choice.
  @async
  String? showApproval(ApprovalOverlayData data);
  void hideApproval();
}

class NotificationStatusData {
  NotificationStatusData({required this.access, required this.canPost});
  bool access;
  bool canPost;
}

class DeviceNotificationData {
  DeviceNotificationData({
    required this.packageName,
    required this.appLabel,
    this.title,
    this.text,
    required this.lines,
    required this.postedAt,
    required this.ongoing,
    this.category,
  });
  String packageName;
  String appLabel;
  String? title;
  String? text;
  List<String> lines;
  int postedAt;
  bool ongoing;
  String? category;
}

@HostApi()
abstract class NotificationApi {
  NotificationStatusData status();
  void openAccessSettings();
  @async
  bool requestPostPermission();
  @async
  List<DeviceNotificationData> list(int limit);

  /// The ongoing "controlling the screen" notification with a Stop action.
  void showSession(String title, String body, String stop, String channel);
  void clearSession();

  /// [kind] is `approval` or `reply`; tapping opens the app.
  void showAlert(String kind, String title, String body, String channel);
  void cancelAlert(String kind);
}

class ShellStatusData {
  ShellStatusData({required this.installed, required this.permission});
  bool installed;
  bool permission;
}

class ShellResultData {
  ShellResultData({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.stdoutLength,
    required this.stderrLength,
    this.error,
    this.errorMessage,
  });
  int exitCode;
  String stdout;
  String stderr;
  int stdoutLength;
  int stderrLength;
  String? error;
  String? errorMessage;
}

@HostApi()
abstract class ShellApi {
  ShellStatusData status();
  @async
  bool requestPermission();
  bool openTermux();
  @async
  ShellResultData run(String operationId, String command, int timeoutMillis);
  void cancel(String operationId);
}

/// Native signals delivered to Dart on the main thread.
@FlutterApi()
abstract class ControlEvents {
  void stopRequested();
  void statusChanged();
}
