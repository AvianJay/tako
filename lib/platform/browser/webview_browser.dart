import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

import '../../core/browser/browser_capability.dart';
import '../../core/browser/browser_scripts.dart';
import '../../core/browser/browser_tabs.dart';
import '../../core/chat/content_block.dart';
import '../../core/files/workspace.dart';
import '../../core/providers/cancel_token.dart';
import '../../core/util/json.dart';

/// One tab: a kept-alive native WebView and the page state shown for it.
class _Tab {
  _Tab(this.id);
  final int id;
  InAppWebViewKeepAlive keepAlive = InAppWebViewKeepAlive();
  int generation = 0;
  InAppWebViewController? controller;
  Completer<void>? attached;
  String? pendingUrl;
  ({String token, int revision})? snapshot;
  final loadWaiters = <Completer<String?>>[];
  int loadSerial = 0;
  String url = '';
  String title = '';
  bool loading = false;
  double progress = 0;
  bool canGoBack = false;
  bool canGoForward = false;

  bool get blank => url.isEmpty && pendingUrl == null && !loading;
}

/// Android WebViews kept alive per tab and shared by the user and the model.
/// The native views survive leaving the browser screen; the model acts only
/// on the tab in front while a surface is mounted, so it requests the screen
/// and the user can watch.
class WebViewBrowser extends BrowserCapability {
  WebViewBrowser({
    required this.workspace,
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final WorkspaceCapability workspace;
  final http.Client Function() _clientFactory;
  static const maxDownloadBytes = 20 * 1024 * 1024;
  static final _random = Random.secure();

  late final _tabs = BrowserTabs<_Tab>(
    create: _Tab.new,
    isBlank: (tab) => tab.blank,
  );
  int _mountedViews = 0;
  String _key = _newSecret();
  String _secret = _newSecret();
  bool _disposed = false;
  bool _modelActive = false;

  _Tab get _active => _tabs.active;

  @override
  bool get isAvailable => true;
  @override
  String get url => _active.url;
  @override
  String get title => _active.title;
  @override
  bool get loading => _active.loading;
  @override
  double get progress => _active.progress;
  @override
  bool get canGoBack => _active.canGoBack;
  @override
  bool get canGoForward => _active.canGoForward;
  @override
  bool get modelActive => _modelActive;
  @override
  bool get viewMounted => _mountedViews > 0;
  @override
  List<BrowserTabInfo> get tabs => [
    for (final id in _tabs.ids)
      if (_tabs[id] case final tab?)
        BrowserTabInfo(
          id: id,
          url: tab.url.isEmpty ? (tab.pendingUrl ?? '') : tab.url,
          title: tab.title,
          loading: tab.loading,
          openedByModel: _tabs.openedByModel(id),
        ),
  ];
  @override
  int get activeTabId => _tabs.activeId;

  static String _newSecret() =>
      '__tako_${List.generate(4, (_) => _random.nextInt(1 << 32).toRadixString(36)).join()}';

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  Widget buildSurface(BuildContext context) {
    final tab = _active;
    return _BrowserSurface(
      key: ValueKey('${tab.id}:${tab.generation}'),
      browser: this,
      tab: tab,
    );
  }

  InAppWebViewSettings get _settings => InAppWebViewSettings(
    javaScriptEnabled: true,
    javaScriptCanOpenWindowsAutomatically: false,
    supportMultipleWindows: false,
    mediaPlaybackRequiresUserGesture: true,
    allowFileAccess: false,
    allowContentAccess: false,
    allowFileAccessFromFileURLs: false,
    allowUniversalAccessFromFileURLs: false,
    geolocationEnabled: false,
    thirdPartyCookiesEnabled: false,
    safeBrowsingEnabled: true,
    useShouldOverrideUrlLoading: true,
    useOnDownloadStart: true,
    useOnRenderProcessGone: true,
    supportZoom: true,
    builtInZoomControls: true,
    displayZoomControls: false,
    isInspectable: kDebugMode,
  );

  void _mount() => _mountedViews++;

  /// Called while the tree is being finalized: no listeners are notified.
  void _unmount(_Tab tab, InAppWebViewController? controller) {
    _mountedViews--;
    if (identical(tab.controller, controller)) tab.controller = null;
  }

  void _onCreated(_Tab tab, InAppWebViewController controller) {
    tab.controller = controller;
    tab.attached?.complete();
    tab.attached = null;
    final pending = tab.pendingUrl;
    if (pending != null) {
      unawaited(_load(controller, pending));
    } else {
      unawaited(_refresh(tab, controller));
    }
  }

  Future<void> _load(InAppWebViewController controller, String url) =>
      controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));

  Future<void> _refresh(_Tab tab, InAppWebViewController controller) async {
    try {
      final values = await (
        controller.getUrl(),
        controller.getTitle(),
        controller.canGoBack(),
        controller.canGoForward(),
      ).wait;
      if (!identical(tab.controller, controller)) return;
      tab.url = values.$1?.toString() ?? tab.url;
      tab.title = values.$2 ?? tab.title;
      tab.canGoBack = values.$3;
      tab.canGoForward = values.$4;
      _changed();
    } catch (_) {
      // The view may have been detached while these calls were in flight.
    }
  }

  void _completeLoads(_Tab tab, String? error) {
    for (final waiter in tab.loadWaiters.toList()) {
      if (!waiter.isCompleted) waiter.complete(error);
    }
    tab.loadWaiters.clear();
  }

  /// Waits for the tab's main-frame load. Returns an error code, or null.
  Future<String?> _waitForLoad(
    _Tab tab,
    CancelToken cancel,
    Duration timeout,
  ) async {
    if (!tab.loading) return null;
    final waiter = Completer<String?>();
    tab.loadWaiters.add(waiter);
    try {
      return await cancel.bind(
        waiter.future.timeout(timeout, onTimeout: () => 'still_loading'),
      );
    } finally {
      tab.loadWaiters.remove(waiter);
    }
  }

  /// After a click, submit or back: wait briefly for a navigation to start,
  /// then for it to finish. SPA route changes only update the URL. The action
  /// has already happened, so Stop ends the wait but keeps the receipt.
  Future<JsonMap> _settle(
    _Tab tab,
    CancelToken cancel,
    int serialBefore,
  ) async {
    String? error;
    var stopped = false;
    try {
      await cancel.bind(
        Future<void>.delayed(const Duration(milliseconds: 450)),
      );
      if (tab.loadSerial != serialBefore) {
        error = await _waitForLoad(tab, cancel, const Duration(seconds: 20));
      }
    } on RequestCancelled {
      stopped = true;
    }
    return {
      'navigated': tab.loadSerial != serialBefore,
      'url': tab.url,
      'title': tab.title,
      if (error == 'load_failed') 'load_error': true,
      if (error == 'still_loading') 'still_loading': true,
      if (stopped) 'stopped': true,
    };
  }

  /// The tab in front and its view, opening the browser screen if needed.
  /// [expected] fails the call when the user switched tabs meanwhile.
  Future<(_Tab, InAppWebViewController)> _surface(
    CancelToken cancel, {
    _Tab? expected,
  }) async {
    cancel.throwIfCancelled();
    final tab = expected ?? _active;
    if (!identical(tab, _active)) {
      throw const BrowserException('tab_changed_read_again');
    }
    if (tab.controller case final controller?) return (tab, controller);
    final ready = tab.attached ??= Completer<void>();
    // At most one widget may use a keep-alive token: never request a second
    // surface while one is still mounted, even during a closing animation.
    if (_mountedViews == 0) {
      final open = onRequestOpen;
      if (open == null) throw const BrowserException('browser_unavailable');
      open();
    }
    try {
      await cancel.bind(ready.future.timeout(const Duration(seconds: 15)));
    } on TimeoutException {
      throw const BrowserException('browser_unavailable');
    }
    if (!identical(tab, _active)) {
      throw const BrowserException('tab_changed_read_again');
    }
    return (
      tab,
      tab.controller ?? (throw const BrowserException('browser_closed')),
    );
  }

  void _markModel() {
    if (_modelActive) return;
    _modelActive = true;
    _changed();
  }

  /// [commits] marks a call that changes the page: once it starts it is not
  /// raced against Stop, so a completed click or entry always has a receipt.
  Future<(_Tab, JsonMap)> _call(
    String operation,
    CancelToken cancel, [
    JsonMap arguments = const {},
    bool commits = false,
  ]) async {
    final (tab, controller) = await _surface(cancel);
    _markModel();
    cancel.throwIfCancelled();
    final evaluation = controller
        .evaluateJavascript(
          source: browserScript(
            key: _key,
            secret: _secret,
            operation: operation,
            arguments: arguments,
          ),
        )
        .timeout(const Duration(seconds: 10));
    Object? value;
    try {
      value = await (commits ? evaluation : cancel.bind(evaluation));
    } on TimeoutException {
      throw const BrowserException('page_not_responding');
    }
    // The plugin decodes JSON once; the script itself returns a JSON string.
    for (var i = 0; i < 2 && value is String; i++) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        break;
      }
    }
    if (value == null && !identical(tab.controller, controller)) {
      throw const BrowserException('browser_closed');
    }
    return (
      tab,
      asMap(value) ?? (throw const BrowserException('script_error')),
    );
  }

  @override
  Future<void> navigate(String url) async {
    if (!isBrowserUrl(url)) throw const BrowserException('invalid_url');
    final tab = _active;
    final controller = tab.controller;
    if (controller == null) {
      tab.pendingUrl = url;
      _changed();
    } else {
      await _load(controller, url);
    }
  }

  @override
  Future<void> newTab({String? url}) async {
    if (url != null && !isBrowserUrl(url)) {
      throw const BrowserException('invalid_url');
    }
    _release(_tabs.openForUser().removed);
    _changed();
    if (url != null) await navigate(url);
  }

  @override
  void selectTab(int id) {
    if (_tabs.select(id)) _changed();
  }

  @override
  Future<void> closeTab(int id) async {
    final closed = _tabs.close(id);
    if (closed == null) return;
    _release([closed]);
    _changed();
  }

  /// Releases closed tabs' native views once their surfaces left the tree.
  void _release(List<_Tab> tabs) {
    if (tabs.isEmpty) return;
    for (final tab in tabs) {
      tab.controller = null;
      tab.snapshot = null;
      _completeLoads(tab, 'browser_closed');
    }
    unawaited(() async {
      await WidgetsBinding.instance.endOfFrame;
      for (final tab in tabs) {
        try {
          await InAppWebViewController.disposeKeepAlive(tab.keepAlive);
        } catch (_) {
          // Already released, or never created natively.
        }
      }
    }());
  }

  @override
  Future<void> goBack() async => _active.controller?.goBack();
  @override
  Future<void> goForward() async => _active.controller?.goForward();
  @override
  Future<void> reload() async => _active.controller?.reload();

  @override
  void takeOver() {
    _modelActive = false;
    _tabs.endResponse();
    _changed();
    onTakeOver?.call();
  }

  @override
  void endModelSession() {
    _tabs.endResponse();
    if (!_modelActive) return;
    _modelActive = false;
    _changed();
  }

  @override
  Future<void> clearBrowsingData() async {
    await (
      CookieManager.instance().deleteAllCookies(),
      WebStorageManager.instance().deleteAllData(),
      InAppWebViewController.clearAllCache(),
      HttpAuthCredentialDatabase.instance().clearAllAuthCredentials(),
    ).wait;
    // Fresh native views also drop history, form data and page state.
    _release(_tabs.reset());
    _key = _newSecret();
    _secret = _newSecret();
    _changed();
  }

  /// Replaces a tab's native view after its renderer process died.
  Future<void> _recreate(_Tab tab) async {
    final previous = tab.keepAlive;
    tab.keepAlive = InAppWebViewKeepAlive();
    tab.generation++;
    tab.snapshot = null;
    tab.controller = null;
    _completeLoads(tab, 'browser_closed');
    _changed();
    // The rebuilt surface replaces the old one in the next frame; release
    // the old native view only after it has left the tree.
    await WidgetsBinding.instance.endOfFrame;
    try {
      await InAppWebViewController.disposeKeepAlive(previous);
    } catch (_) {
      // Already released, or never created natively.
    }
  }

  @override
  Future<JsonMap> open(String url, CancelToken cancel) async {
    if (!isBrowserUrl(url)) throw const BrowserException('invalid_url');
    cancel.throwIfCancelled();
    // The model's own tab: the user's pages are never navigated away.
    final opened = _tabs.openForModel();
    _release(opened.removed);
    _changed();
    final (tab, controller) = await _surface(cancel, expected: opened.tab);
    _markModel();
    final serial = tab.loadSerial;
    await _load(controller, url);
    // loadUrl returns before onLoadStart; give the navigation time to begin.
    final started = DateTime.now();
    while (tab.loadSerial == serial &&
        DateTime.now().difference(started) < const Duration(seconds: 3)) {
      await cancel.bind(Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    final error = await _waitForLoad(tab, cancel, const Duration(seconds: 25));
    if (error == 'load_failed') throw const BrowserException('load_failed');
    return {
      'opened': tab.url.isEmpty ? url : tab.url,
      'title': tab.title,
      if (error == 'still_loading') 'still_loading': true,
    };
  }

  @override
  Future<BrowserSnapshot> read(CancelToken cancel) async {
    final (tab, _) = await _surface(cancel);
    if (tab.loading) {
      await _waitForLoad(tab, cancel, const Duration(seconds: 8));
    }
    final (readTab, result) = await _call('read', cancel, {'maxText': 12000});
    if (result['error'] case final String code) throw BrowserException(code);
    final token = asString(result['token']);
    final revision = asInt(result['revision']);
    if (token == null || revision == null) {
      throw const BrowserException('script_error');
    }
    readTab.snapshot = (token: token, revision: revision);
    return BrowserSnapshot.fromJson(result);
  }

  JsonMap _targetArguments(int id) {
    final snapshot = _active.snapshot;
    if (snapshot == null) throw const BrowserException('read_page_first');
    return {'token': snapshot.token, 'revision': snapshot.revision, 'id': id};
  }

  @override
  Future<BrowserTarget> resolve(int id, CancelToken cancel) async {
    final arguments = _targetArguments(id);
    final (_, result) = await _call('target', cancel, arguments);
    if (result['error'] case final String code) throw BrowserException(code);
    return BrowserTarget.fromJson(result);
  }

  @override
  Future<JsonMap> click(BrowserTarget target, CancelToken cancel) async {
    final serial = _active.loadSerial;
    final (tab, result) = await _call('click', cancel, {
      ..._targetArguments(target.id),
      'check': target.check,
    }, true);
    if (result.containsKey('error')) return result;
    return {...result, ...await _settle(tab, cancel, serial)};
  }

  @override
  Future<JsonMap> type(
    BrowserTarget target,
    String text, {
    required bool submit,
    required CancelToken cancel,
  }) async {
    final serial = _active.loadSerial;
    final (tab, result) = await _call('type', cancel, {
      ..._targetArguments(target.id),
      'check': target.check,
      'text': text,
      'submit': submit,
    }, true);
    if (result.containsKey('error') || !submit) return result;
    return {...result, ...await _settle(tab, cancel, serial)};
  }

  @override
  Future<JsonMap> scroll(String direction, CancelToken cancel) async =>
      (await _call('scroll', cancel, {'direction': direction})).$2;

  @override
  Future<JsonMap> back(CancelToken cancel) async {
    final (tab, controller) = await _surface(cancel);
    if (!await controller.canGoBack()) {
      throw const BrowserException('no_previous_page');
    }
    _markModel();
    final serial = tab.loadSerial;
    await controller.goBack();
    return _settle(tab, cancel, serial);
  }

  // WebView callbacks, per tab.

  void _onLoadStart(_Tab tab, WebUri? url) {
    tab.loadSerial++;
    tab.loading = true;
    tab.progress = 0;
    tab.pendingUrl = null;
    // A new document invalidates every id; the script also checks this.
    tab.snapshot = null;
    tab.url = url?.toString() ?? tab.url;
    _changed();
  }

  void _onLoadStop(_Tab tab, InAppWebViewController controller, WebUri? url) {
    tab.loading = false;
    tab.progress = 1;
    tab.url = url?.toString() ?? tab.url;
    _completeLoads(tab, null);
    unawaited(_refresh(tab, controller));
    _changed();
  }

  void _onLoadError(
    _Tab tab,
    WebResourceRequest request,
    WebResourceError error,
  ) {
    if (request.isForMainFrame == false) return;
    // Cancelled navigations, e.g. blocked app links, are not page failures.
    if (error.type == WebResourceErrorType.CANCELLED) return;
    tab.loading = false;
    tab.pendingUrl = null;
    _completeLoads(tab, 'load_failed');
    _changed();
  }

  Future<NavigationActionPolicy> _shouldLoad(
    InAppWebViewController controller,
    NavigationAction action,
  ) async {
    final scheme = action.request.url?.scheme.toLowerCase() ?? '';
    // Only web content: intent:, market:, file:, content: and app links
    // never leave the browser or reach local files.
    return const {'http', 'https', 'about', 'data', 'blob'}.contains(scheme)
        ? NavigationActionPolicy.ALLOW
        : NavigationActionPolicy.CANCEL;
  }

  Future<void> _onDownload(DownloadStartRequest request) async {
    final confirm = onConfirmDownload;
    final url = Uri.tryParse(request.url.toString());
    if (confirm == null || url == null) return;
    final download = BrowserDownload(
      url: url,
      fileName: request.suggestedFilename,
      mimeType: request.mimeType,
      contentLength: request.contentLength > 0 ? request.contentLength : null,
    );
    if (!await confirm(download)) return;
    try {
      final block = await _download(download, request.userAgent);
      onDownloadFinished?.call(switch (block) {
        ImageBlock(:final path) || FileBlock(:final path) => path,
        _ => null,
      }, null);
    } on BrowserException catch (error) {
      onDownloadFinished?.call(null, error.code);
    } catch (_) {
      onDownloadFinished?.call(null, 'download_failed');
    }
  }

  /// Saves a confirmed download as an attachment. Cookies are recomputed per
  /// redirect hop, so one site's cookies are never sent to another host.
  Future<ContentBlock> _download(
    BrowserDownload download,
    String? userAgent,
  ) async {
    if ((download.contentLength ?? 0) > maxDownloadBytes) {
      throw const BrowserException('download_too_large');
    }
    var url = download.url;
    final client = _clientFactory();
    try {
      for (var hop = 0; hop < 5; hop++) {
        if (!isBrowserUrl(url.toString())) {
          throw const BrowserException('unsupported_download');
        }
        final cookies = await CookieManager.instance().getCookies(
          url: WebUri(url.toString()),
        );
        final request = http.Request('GET', url)
          ..followRedirects = false
          ..headers.addAll({
            if (userAgent != null && userAgent.isNotEmpty)
              'User-Agent': userAgent,
            if (cookies.isNotEmpty)
              'Cookie': [
                for (final cookie in cookies) '${cookie.name}=${cookie.value}',
              ].join('; '),
          });
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 30));
        if (response.isRedirect || response.statusCode ~/ 100 == 3) {
          final location = response.headers['location'];
          await response.stream.drain<void>();
          if (location == null) break;
          url = url.resolve(location);
          continue;
        }
        if (response.statusCode != 200) {
          await response.stream.drain<void>();
          throw const BrowserException('download_failed');
        }
        if ((response.contentLength ?? 0) > maxDownloadBytes) {
          throw const BrowserException('download_too_large');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 30),
        )) {
          bytes.add(chunk);
          if (bytes.length > maxDownloadBytes) {
            throw const BrowserException('download_too_large');
          }
        }
        final name = _fileName(download, url);
        return workspace.importBytes(name, bytes.takeBytes());
      }
      throw const BrowserException('download_failed');
    } finally {
      client.close();
    }
  }

  static String _fileName(BrowserDownload download, Uri url) {
    final suggested = download.fileName?.trim() ?? '';
    if (suggested.isNotEmpty) return suggested;
    final segment = url.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
    return segment == null || segment.isEmpty ? 'download' : segment;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final id in _tabs.ids) {
      final tab = _tabs[id];
      if (tab == null) continue;
      _completeLoads(tab, 'browser_closed');
      unawaited(
        InAppWebViewController.disposeKeepAlive(
          tab.keepAlive,
        ).catchError((Object _) {}),
      );
    }
    super.dispose();
  }
}

class _BrowserSurface extends StatefulWidget {
  const _BrowserSurface({required this.browser, required this.tab, super.key});
  final WebViewBrowser browser;
  final _Tab tab;
  @override
  State<_BrowserSurface> createState() => _BrowserSurfaceState();
}

class _BrowserSurfaceState extends State<_BrowserSurface> {
  InAppWebViewController? _controller;

  @override
  void initState() {
    super.initState();
    widget.browser._mount();
  }

  @override
  void dispose() {
    widget.browser._unmount(widget.tab, _controller);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final browser = widget.browser;
    final tab = widget.tab;
    return InAppWebView(
      keepAlive: tab.keepAlive,
      initialSettings: browser._settings,
      onWebViewCreated: (controller) {
        _controller = controller;
        browser._onCreated(tab, controller);
      },
      onLoadStart: (_, url) => browser._onLoadStart(tab, url),
      onLoadStop: (controller, url) =>
          browser._onLoadStop(tab, controller, url),
      onReceivedError: (_, request, error) =>
          browser._onLoadError(tab, request, error),
      onProgressChanged: (_, progress) {
        tab.progress = progress / 100;
        browser._changed();
      },
      onTitleChanged: (_, title) {
        tab.title = title ?? '';
        browser._changed();
      },
      onUpdateVisitedHistory: (controller, url, _) {
        tab.url = url?.toString() ?? tab.url;
        unawaited(browser._refresh(tab, controller));
      },
      shouldOverrideUrlLoading: browser._shouldLoad,
      onCreateWindow: (controller, action) async {
        final url = action.request.url?.toString();
        if (url != null && isBrowserUrl(url)) {
          unawaited(browser._load(controller, url));
        }
        return false;
      },
      onDownloadStartRequest: (_, request) =>
          unawaited(browser._onDownload(request)),
      onPermissionRequest: (_, request) async => PermissionResponse(
        resources: request.resources,
        action: PermissionResponseAction.DENY,
      ),
      onGeolocationPermissionsShowPrompt: (_, origin) async =>
          GeolocationPermissionShowPromptResponse(
            origin: origin,
            allow: false,
            retain: false,
          ),
      onRenderProcessGone: (_, _) => unawaited(browser._recreate(tab)),
    );
  }
}
