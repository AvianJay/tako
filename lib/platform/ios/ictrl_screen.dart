import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../core/providers/cancel_token.dart';
import '../../core/screen/remote_screen.dart';
import '../../core/screen/screen_capability.dart';
import '../../core/screen/screen_reading.dart';
import 'ictrl_client.dart';
import 'ictrl_tree.dart';

/// iCTRL runs separately; Tako detects/pairs with its default loopback port.
class IctrlScreen extends RemoteScreen {
  IctrlScreen({
    required this.client,
    this.sessionChanged,
    this.progressChanged,
  });
  final IctrlClient client;
  final Future<void> Function(bool active)? sessionChanged;
  final Future<void> Function(String method, int count)? progressChanged;
  @override
  String get endpoint => client.endpoint;
  @override
  RemoteScreenStatus status = RemoteScreenStatus.offline;
  @override
  String? errorCode;
  @override
  Map<String, Object?> sessionDiagnostics = const {};
  void updateSessionDiagnostics(Map<String, Object?> values) {
    if (_disposed) return;
    sessionDiagnostics = Map.unmodifiable(
      values['build'] is String ? values : {...sessionDiagnostics, ...values},
    );
    notifyListeners();
  }

  @override
  bool get supported => true;
  @override
  bool get enabled => status == RemoteScreenStatus.ready;
  @override
  bool get screenshotsSupported => true;
  @override
  Set<ScreenObservationMode> get observationModes => const {
    ScreenObservationMode.elements,
    ScreenObservationMode.screenshot,
  };
  @override
  Set<String> get supportedKeys => const {'home'};
  @override
  bool get supportsDrag => true;
  @override
  bool get supportsFastActions => true;
  Future<void>? _connecting;
  Future<void>? _sessionStarting;
  DateTime? _lastProbe;
  bool _loaded = false;
  bool _autoPair = true;
  bool _paused = false;
  bool _disposed = false;
  int _epoch = 0;
  int _token = 0;
  int _actions = 0;
  int _pointWidth = 0;
  int _pointHeight = 0;
  ScreenTree? _latest;
  bool _observationPending = false;
  bool _sourceLoading = false;
  String? _launchedApp;

  /// A successful action may return before its UI transition starts. Only the
  /// next observation waits locally; fast sequences and game input never wait.
  void expectObservation({String? app}) {
    _observationPending = true;
    _launchedApp = app;
  }

  final _refs = <(int, int), String>{};
  final _points = <(int, int), (double, double)>{};
  void _status(RemoteScreenStatus value, [String? error]) {
    if (_disposed) return;
    status = value;
    errorCode = error;
    notifyListeners();
  }

  @override
  Future<void> refresh() async {
    if (_paused || _disposed || _connecting != null) return;
    if (_lastProbe != null &&
        DateTime.now().difference(_lastProbe!) < const Duration(seconds: 8)) {
      return;
    }
    await connect();
  }

  @override
  Future<void> connect({String? endpoint}) {
    if (_connecting != null) return _connecting!;
    _paused = false;
    if (endpoint != null) _autoPair = true;
    final operation = _connect(endpoint);
    _connecting = operation;
    return operation.whenComplete(() => _connecting = null);
  }

  Future<void> _connect(String? endpoint) async {
    final epoch = _epoch;
    _lastProbe = DateTime.now();
    try {
      if (!_loaded) {
        final saved = await client.readSecret('ictrl.endpoint');
        _paused = await client.readSecret('ictrl.paused') == 'true';
        if (saved != null) {
          await client.setEndpoint(saved);
        } else {
          await client.loadKey();
        }
        _loaded = true;
        if (_paused && endpoint == null) {
          _status(RemoteScreenStatus.paused);
          return;
        }
      }
      if (endpoint != null) {
        _paused = false;
        await client.setEndpoint(endpoint);
        await client.writeSecret('ictrl.endpoint', client.endpoint);
      }
      await client.writeSecret('ictrl.paused', null);
      _status(RemoteScreenStatus.connecting);
      // Cached keys avoid fetching 65 KB of schema on every model turn.
      if (!client.hasKey) {
        await client.discover();
        if (_disposed || epoch != _epoch) return;
        if (!_autoPair) {
          _status(RemoteScreenStatus.denied, 'ictrl_pair_required');
          return;
        }
        _autoPair = false;
        _status(RemoteScreenStatus.pairing);
        await client.pair();
      }
      if (_disposed || epoch != _epoch) return;
      final device = await client.call('device_info');
      _pointWidth = (device['point_width'] as num).round();
      _pointHeight = (device['point_height'] as num).round();
      if (_pointWidth <= 0 || _pointHeight <= 0) {
        throw const ScreenException('ictrl_invalid_geometry');
      }
      if (_disposed || epoch != _epoch) return;
      _status(RemoteScreenStatus.ready);
    } on ScreenException catch (error) {
      if (_disposed || epoch != _epoch) return;
      _status(
        error.code == 'ictrl_pair_denied'
            ? RemoteScreenStatus.denied
            : error.code == 'ictrl_offline'
            ? RemoteScreenStatus.offline
            : RemoteScreenStatus.failed,
        error.code,
      );
    } catch (_) {
      if (!_disposed && epoch == _epoch) {
        _status(RemoteScreenStatus.failed, 'ictrl_connection_failed');
      }
    }
  }

  @override
  Future<void> disconnect() async {
    _epoch++;
    _paused = true;
    _latest = null;
    _refs.clear();
    takeOver();
    await client.writeSecret('ictrl.paused', 'true');
    _status(RemoteScreenStatus.paused);
  }

  @override
  Future<void> openSettings() => connect(endpoint: endpoint);
  @override
  Future<void> openAppInfo() async {}
  Future<Map<String, Object?>> rpc(
    String method, [
    Map<String, Object?> params = const {},
    CancelToken? cancel,
  ]) async {
    if (!enabled || _disposed) {
      throw const ScreenException('screen_control_off');
    }
    try {
      return await client.call(method, params, cancel);
    } on ScreenException catch (e) {
      if (e.code == 'ictrl_pair_required' || e.code == 'ictrl_offline') {
        _status(RemoteScreenStatus.offline, e.code);
      }
      rethrow;
    }
  }

  Future<ScreenTree> _tree(CancelToken cancel) async {
    final source = await rpc('page_source', {
      'visible_only': true,
      'max_elements': 400,
      // Scientific keypads can exceed 50 direct children without the server
      // reporting truncation. Keep the read bounded while exposing their tail.
      'max_children': 100,
    }, cancel);
    _sourceLoading = source['loading'] == true;
    final parsed = parseIctrlTree(
      source,
      token: ++_token,
      width: _pointWidth,
      height: _pointHeight,
    );
    final usefulLabels = parsed.nodes
        .where(
          (n) =>
              n.className != 'Application' &&
              n.className != 'Window' &&
              (n.text?.isNotEmpty == true || n.description?.isNotEmpty == true),
        )
        .length;
    if (((source['channel'] as Map?)?['recommended'] == 'ocr' ||
            source['truncated'] == true && usefulLabels < 5 ||
            source['sparse_hint'] != null ||
            source['viewport_warning'] != null) &&
        (source['ocr_items'] as List?)?.isNotEmpty != true) {
      final ocr = await rpc('screen_text', const {}, cancel);
      source['ocr_items'] = ocr['items'];
    } else {
      return parsed;
    }
    return parseIctrlTree(
      source,
      token: parsed.token,
      width: _pointWidth,
      height: _pointHeight,
    );
  }

  bool _loading(ScreenTree tree) => tree.nodes.any(
    (n) =>
        const {
          'ActivityIndicator',
          'ProgressIndicator',
        }.contains(n.className) ||
        RegExp(
          r'^(?:loading|載入中|加载中|正在載入)(?:[.\s…]*)$',
          caseSensitive: false,
        ).hasMatch(ownLabel(n)),
  );

  String _screenState(ScreenTree tree) =>
      '${tree.packageName}|${tree.width}x${tree.height}|'
      '${tree.nodes.map((n) => '${n.className}:${ownLabel(n)}:${n.bounds.left},${n.bounds.top}').join('|')}';

  Future<ScreenTree> _observedTree(CancelToken cancel) async {
    final pending = _observationPending;
    final app = _launchedApp;
    _observationPending = false;
    _launchedApp = null;
    var tree = await _tree(cancel);
    if (!pending) return tree;
    final previous = _latest == null ? null : _screenState(_latest!);
    // Android waits for accessibility events to become quiet. iCTRL has no
    // event channel: bounded fresh reads handle unchanged/loading transitions
    // without a model round or any replay of the committed action.
    for (var retry = 0; retry < 3; retry++) {
      final waiting =
          _sourceLoading ||
          _loading(tree) ||
          tree.nodes.every((n) => ownLabel(n).isEmpty) ||
          app != null && tree.packageName != app;
      if (!waiting && (retry > 0 || previous != _screenState(tree))) break;
      await cancel.bind(
        Future<void>.delayed(Duration(milliseconds: retry == 0 ? 100 : 180)),
      );
      tree = await _tree(cancel);
    }
    return tree;
  }

  @override
  Future<ScreenTree> snapshot({
    required bool screenshot,
    required CancelToken cancel,
  }) async {
    final tree = await _observedTree(cancel);
    Uint8List? bytes;
    var iw = 0;
    var ih = 0;
    if (screenshot && !tree.ownAppInFront) {
      final shot = await rpc('screenshot', {
        // On phones one image pixel per point avoids coordinate conversion
        // mistakes. Tablets keep the smaller payload.
        'scale': tree.width <= 512 ? 1.0 : .75,
        'format': 'jpeg',
        'quality': .55,
      }, cancel);
      bytes = base64Decode(shot['data'] as String);
      iw = (shot['pixel_width'] as num).round();
      ih = (shot['pixel_height'] as num).round();
      // iCTRL 1.96 may stretch landscape content into portrait dimensions.
      // The session report verified resizing (not rotating) restores it.
      if (tree.width > tree.height && iw < ih) {
        final newWidth = (tree.width * .75).round();
        final newHeight = (tree.height * .75).round();
        bytes = await compute(resizeIctrlScreenshot, (
          bytes,
          newWidth,
          newHeight,
        ));
        iw = newWidth;
        ih = newHeight;
      }
    }
    _refs.clear();
    _points.clear();
    _latest = ScreenTree(
      token: tree.token,
      packageName: tree.packageName,
      appLabel: tree.appLabel,
      width: tree.width,
      height: tree.height,
      ownAppInFront: tree.ownAppInFront,
      windows: tree.windows,
      nodes: tree.nodes,
      truncated: tree.truncated,
      image: bytes,
      imageWidth: iw,
      imageHeight: ih,
    );
    return _latest!;
  }

  ScreenTargetInfo _info(ScreenTree tree, int index, {int? token, int? node}) {
    final target = index < 0 ? null : tree.nodes[index];
    final ancestors = <ScreenNode>[];
    for (
      var parent = target?.parent ?? -1;
      parent >= 0;
      parent = tree.nodes[parent].parent
    ) {
      ancestors.add(tree.nodes[parent]);
    }
    return ScreenTargetInfo(
      token: token ?? tree.token,
      node: node ?? index,
      window: tree.windows.first,
      appLabel: tree.appLabel,
      target: target,
      ancestors: ancestors,
      descendants: index < 0
          ? const []
          : tree.nodes.sublist(index + 1, subtreeEnds(tree.nodes)[index] + 1),
      actionText: target == null ? '' : ownLabel(target),
      windowText: tree.windows.first.type == 2
          ? tree.nodes.map(ownLabel).where((s) => s.isNotEmpty).join(' ')
          : '',
      width: tree.width,
      height: tree.height,
    );
  }

  @override
  Future<ScreenTargetInfo> resolveNode(
    int token,
    int node,
    CancelToken cancel,
  ) async {
    final previous = _latest;
    if (previous == null ||
        token != previous.token ||
        node < 0 ||
        node >= previous.nodes.length) {
      throw const ScreenException('unknown_id_read_again');
    }
    final before = previous.nodes[node];
    // A ref is an exact live selector, re-resolved by iCTRL on every action.
    // Repeated keys in one stable sequence can reuse it without an extra
    // find RPC. A new observation/app/orientation invalidates this cache.
    if (before.className == 'Key' && _refs.containsKey((token, node))) {
      return _info(previous, node);
    }
    // Visible-only AX can include clipped cells whose center is outside the
    // content area. Require the whole target in view before aiming at it.
    if (before.bounds.area <= 0 ||
        before.bounds.left < 0 ||
        before.bounds.top < 0 ||
        before.bounds.right > previous.width ||
        before.bounds.bottom > previous.height) {
      throw const ScreenException('element_offscreen_scroll_into_view');
    }
    final label = before.viewId ?? before.description ?? before.text ?? '';
    // OCR and unnamed/ambiguous elements require a fresh viewport read.
    final sameLabel = previous.nodes
        .where(
          (n) =>
              (n.viewId ?? n.description ?? n.text) == label &&
              n.className == before.className &&
              n.password == before.password,
        )
        .toList();
    if (before.className != 'OCRText' &&
        label.trim().isNotEmpty &&
        sameLabel.every(
          (n) =>
              (n.bounds.left - before.bounds.left).abs() < 4 &&
              (n.bounds.top - before.bounds.top).abs() < 4,
        )) {
      Map<String, Object?>? hit;
      try {
        hit = await rpc('find_element', {
          'element_id': label,
          'match': 'exact',
          if (ictrlFindType(before.className) case final String type)
            'element_type': type,
          'bundle_id': previous.packageName,
        }, cancel);
      } on ScreenException catch (error) {
        // Read-only AX lookup failure cannot commit a gesture. Some navigation
        // labels exist in page_source but iOS's locator cannot find them.
        if (error.code != 'ictrl_rpc_failed_read_again') rethrow;
      }
      if (hit != null && hit['exists'] != false && hit['ref'] is String) {
        if (hit['hittable'] == false ||
            hit['visibility'] != 'in_view' ||
            (hit['match_count'] as num? ?? 1) != 1 ||
            ictrlNodeClass(hit['element_type'] as String? ?? '') !=
                before.className ||
            (hit['element_type'] == 'SecureTextField') != before.password) {
          throw const ScreenException('element_changed_read_again');
        }
        final observed = hit['label'] as String? ?? label;
        if (before.description?.isNotEmpty == true &&
            observed != before.description) {
          throw const ScreenException('element_changed_read_again');
        }
        _refs[(token, node)] = hit['ref'] as String;
        if (hit['center_x'] is num && hit['center_y'] is num) {
          _points[(token, node)] = (
            (hit['center_x'] as num).toDouble(),
            (hit['center_y'] as num).toDouble(),
          );
        }
        return _info(previous, node);
      }
      // Fall through to a fresh tree and match exact identity plus geometry.
      // Never use the old point or repeat an action that may have committed.
    }
    final live = await _tree(cancel);
    if (live.packageName != previous.packageName ||
        live.width != previous.width ||
        live.height != previous.height) {
      throw const ScreenException('element_changed_read_again');
    }
    final matches = live.nodes.indexed.where((item) {
      final n = item.$2;
      // OCR can duplicate an AX label or appear twice on the same page.
      // Match its source and nearby geometry, not its label alone.
      return n.check == before.check &&
          n.className == before.className &&
          ((n.bounds.left + n.bounds.right) -
                      (before.bounds.left + before.bounds.right))
                  .abs() <
              48 &&
          ((n.bounds.top + n.bounds.bottom) -
                      (before.bounds.top + before.bounds.bottom))
                  .abs() <
              48;
    }).toList();
    if (matches.length != 1) {
      throw const ScreenException('element_changed_read_again');
    }
    final b = matches.single.$2.bounds;
    if (live.nodes[matches.single.$1].password != before.password ||
        live.nodes[matches.single.$1].className != before.className ||
        !live.nodes[matches.single.$1].enabled ||
        b.area <= 0 ||
        b.left < 0 ||
        b.top < 0 ||
        b.right > live.width ||
        b.bottom > live.height) {
      throw const ScreenException('element_changed_read_again');
    }
    _points[(token, node)] = ((b.left + b.right) / 2, (b.top + b.bottom) / 2);
    return _info(live, matches.single.$1, token: token, node: node);
  }

  @override
  Future<ScreenTargetInfo> resolvePoint(
    double x,
    double y,
    CancelToken cancel,
  ) async {
    final live = await _tree(cancel);
    if (_latest != null &&
        (live.width != _latest!.width ||
            live.height != _latest!.height ||
            live.packageName != _latest!.packageName)) {
      throw const ScreenException('screen_changed_read_again');
    }
    if (x < 0 || y < 0 || x >= live.width || y >= live.height) {
      throw const ScreenException('point_outside_screen');
    }
    var match = -1;
    var area = 1 << 60;
    for (var i = 0; i < live.nodes.length; i++) {
      final node = live.nodes[i];
      final b = node.bounds;
      if (node.actionable &&
          b.area > 0 &&
          b.area < area &&
          x >= b.left &&
          x < b.right &&
          y >= b.top &&
          y < b.bottom) {
        match = i;
        area = b.area;
      }
    }
    return _info(live, match);
  }

  @override
  Future<ScreenTargetInfo> resolveFocus(CancelToken cancel) async {
    // iCTRL does not expose reliable keyboard focus. Require a field id/point.
    throw const ScreenException('ios_type_requires_field_id_or_point');
  }

  (double, double) _point(double x, double y) {
    final tree = _latest;
    if (tree != null &&
        tree.width > tree.height &&
        _pointWidth < _pointHeight) {
      return (_pointWidth - y, x);
    }
    return (x, y);
  }

  @override
  Future<ScreenActionOutcome> act(ScreenAction action) async {
    final tree = _latest;
    if (tree?.ownAppInFront == true) throw const ScreenException('own_app');
    final ref = _refs[(action.token, action.node)];
    final node =
        tree != null && action.node >= 0 && action.node < tree.nodes.length
        ? tree.nodes[action.node]
        : null;
    final approved = _points.remove((action.token, action.node));
    final x =
        action.x ??
        approved?.$1 ??
        (node == null
            ? _pointWidth / 2
            : (node.bounds.left + node.bounds.right) / 2);
    final y =
        action.y ??
        approved?.$2 ??
        (node == null
            ? _pointHeight / 2
            : (node.bounds.top + node.bounds.bottom) / 2);
    final (px, py) = _point(x, y);
    final settle = action.settle == true && node?.className != 'Key';
    final params = <String, Object?>{
      'settle': settle,
      if (settle) 'settle_timeout': 1.2,
    };
    final String method;
    switch (action.action) {
      case 'key':
        if (action.key != 'home') {
          throw const ScreenException('unsupported_key');
        }
        method = 'home';
      case 'tap':
      case 'long_press':
        method = action.action;
        params.addAll(ref == null ? {'x': px, 'y': py} : {'ref': ref});
        params['fast'] = true;
        if (method == 'long_press') params['duration'] = action.duration ?? .6;
      case 'set_text':
        method = 'type';
        params.addAll({
          'text': action.text ?? '',
          'clear': true,
          'submit': action.submit,
          'x': px,
          'y': py,
        });
        if (ref != null) params['ref'] = ref;
      case 'scroll':
        if (action.direction == 'up' || action.direction == 'down') {
          method = 'page';
          params['direction'] = action.direction;
        } else {
          method = 'swipe';
          params.addAll({
            'x': px,
            'y': py,
            'direction': action.direction,
            'velocity': 'slow',
          });
        }
      case 'swipe':
        // Express both ends through the same orientation transform.
        final dx = action.direction == 'left'
            ? -.45 * (tree?.width ?? _pointWidth)
            : action.direction == 'right'
            ? .45 * (tree?.width ?? _pointWidth)
            : 0.0;
        final dy = action.direction == 'up'
            ? -.45 * (tree?.height ?? _pointHeight)
            : action.direction == 'down'
            ? .45 * (tree?.height ?? _pointHeight)
            : 0.0;
        final (tx, ty) = _point(
          (x + dx).clamp(1, (tree?.width ?? _pointWidth) - 1).toDouble(),
          (y + dy).clamp(1, (tree?.height ?? _pointHeight) - 1).toDouble(),
        );
        method = 'drag';
        params.addAll({
          'from_x': px,
          'from_y': py,
          'to_x': tx,
          'to_y': ty,
          'duration': .25,
        });
      case 'drag':
        final (tx, ty) = _point(action.toX!, action.toY!);
        method = 'drag';
        params.addAll({
          'from_x': px,
          'from_y': py,
          'to_x': tx,
          'to_y': ty,
          'duration': action.duration ?? .4,
        });
      default:
        throw const ScreenException('unsupported_action');
    }
    // No cancellation or retries after dispatch: retain the committed receipt.
    final receipt = await rpc(method, params);
    if ((receipt['settle'] as Map?)?['stable'] == true) {
      _observationPending = false;
      _launchedApp = null;
    } else {
      expectObservation();
    }
    _actions++;
    unawaited(progressChanged?.call(method, _actions));
    return ScreenActionOutcome(
      method: action.action == 'set_text' && action.submit
          ? 'set_text_submitted'
          : action.action,
      packageName: tree?.packageName ?? '',
      appLabel: tree?.appLabel ?? '',
      details: {
        'screen_changed': null,
        'untrusted_receipt': receipt,
        for (final key in const [
          'warning',
          'hit_warning',
          'hit_skipped',
          'page_check',
          'moved',
          'at_end',
          'keyboard_closed',
          'blocked_by',
        ])
          if (receipt[key] != null) key: receipt[key],
      },
    );
  }

  @override
  bool get supportsTimedGestures => true;
  @override
  Future<ScreenActionOutcome> timedGesture(
    ScreenAction action, {
    required String app,
    required int width,
    required int height,
    required CancelToken cancel,
  }) async {
    cancel.throwIfCancelled();
    if (!modelActive) throw const ScreenException('cancelled');
    // Inspect the Application root only; game frames do not need an expensive
    // accessibility/OCR walk on every note. The server still handles alerts and
    // blocks CAPTCHA gestures. Never replay into another app or orientation.
    final root = await rpc('page_source', {
      'visible_only': true,
      'max_depth': 1,
      'max_children': 1,
      'max_elements': 8,
    }, cancel);
    final live = parseIctrlTree(
      root,
      token: _token,
      width: _pointWidth,
      height: _pointHeight,
    );
    if (live.packageName != app ||
        live.ownAppInFront ||
        live.width != width ||
        live.height != height ||
        root['system_alert'] == true ||
        root['blocked_by'] != null) {
      throw const ScreenException('game_app_or_geometry_changed');
    }
    cancel.throwIfCancelled();
    return act(action);
  }

  @override
  void beginModelSession() {
    if (!isAvailable || modelActive) return;
    super.beginModelSession();
    _actions = 0;
    _sessionStarting = sessionChanged?.call(true);
  }

  /// Launching another app must not race the method-channel request that
  /// registers continued processing while Tako is still in the foreground.
  Future<void> prepareModelSession(CancelToken cancel) async {
    beginModelSession();
    if (_sessionStarting case final Future<void> starting) {
      await cancel.bind(starting);
    }
    cancel.throwIfCancelled();
  }

  @override
  void endModelSession() {
    if (!modelActive) return;
    super.endModelSession();
    _sessionStarting = null;
    unawaited(sessionChanged?.call(false));
  }

  @override
  void takeOver() {
    onTakeOver?.call();
    endModelSession();
  }

  @override
  Future<String?> showApproval(ScreenApproval approval) async => null;
  @override
  void hideApproval() {}
  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    endModelSession();
    client.close();
    super.dispose();
  }
}

Uint8List resizeIctrlScreenshot((Uint8List, int, int) input) {
  final decoded = img.decodeImage(input.$1);
  if (decoded == null) throw const FormatException('Invalid screenshot');
  return Uint8List.fromList(
    img.encodeJpg(
      img.copyResize(decoded, width: input.$2, height: input.$3),
      quality: 65,
    ),
  );
}
