import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/files/workspace.dart';
import 'package:tako/core/providers/cancel_token.dart';
import 'package:tako/platform/browser/webview_browser.dart';

class _Workspace implements WorkspaceCapability {
  @override
  bool get isAvailable => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Platform extends InAppWebViewPlatform {
  final headless = <_Headless>[];
  final inline = <_Inline>[];
  bool deferCreation = false;

  @override
  PlatformHeadlessInAppWebView createPlatformHeadlessInAppWebView(
    PlatformHeadlessInAppWebViewCreationParams params,
  ) {
    final view = _Headless(params, deferCreation: deferCreation);
    headless.add(view);
    return view;
  }

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    final view = _Inline(params);
    inline.add(view);
    return view;
  }

  @override
  PlatformInAppWebViewController createPlatformInAppWebViewControllerStatic() =>
      _Controller(null);

  @override
  PlatformInAppWebViewController createPlatformInAppWebViewController(
    PlatformInAppWebViewControllerCreationParams params,
  ) => _Controller(
    params.webviewParams,
    page: headless
        .firstWhere((view) => view.controller.id == params.id)
        .controller
        .page,
  );
}

class _Page {
  static int nextId = 0;
  final int id = nextId++;
  WebUri url = WebUri('about:blank');
  int loads = 0;
}

class _Controller extends PlatformInAppWebViewController {
  factory _Controller(
    PlatformWebViewCreationParams<dynamic>? callbacks, {
    _Page? page,
  }) => _Controller._(callbacks, page ?? _Page());

  _Controller._(this.callbacks, this.page)
    : super.implementation(
        PlatformInAppWebViewControllerCreationParams(
          id: page.id,
          webviewParams: callbacks,
        ),
      );
  final _Page page;
  PlatformWebViewCreationParams<dynamic>? callbacks;
  WebUri get url => page.url;
  int get loads => page.loads;
  bool disposed = false;

  @override
  Future<WebUri?> getUrl() async => url;
  @override
  Future<String?> getTitle() async => 'Example';
  @override
  Future<bool> canGoBack() async => false;
  @override
  Future<bool> canGoForward() async => false;

  @override
  Future<void> loadUrl({
    required URLRequest urlRequest,
    Uri? iosAllowingReadAccessTo,
    WebUri? allowingReadAccessTo,
  }) async {
    page.loads++;
    page.url = urlRequest.url!;
    final controller = InAppWebViewController.fromPlatform(platform: this);
    callbacks?.onLoadStart?.call(controller, url);
    callbacks?.onLoadStop?.call(controller, url);
  }

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    if (disposed) throw StateError('The widget disposed this channel');
    return {
      'url': url.toString(),
      'title': 'Example',
      'text': 'Page content',
      'elements': [],
      'token': 'document',
      'revision': 1,
    };
  }

  @override
  dynamic getViewId() => id;

  @override
  void dispose({bool isKeepAlive = false}) => disposed = true;

  @override
  Future<void> disposeKeepAlive(InAppWebViewKeepAlive keepAlive) async {}
}

class _Headless extends PlatformHeadlessInAppWebView {
  _Headless(super.params, {this.deferCreation = false})
    : super.implementation();
  final bool deferCreation;
  late final controller = _Controller(params);
  bool running = false;
  bool disposed = false;
  @override
  String get id => 'headless-test';
  @override
  PlatformInAppWebViewController get webViewController => controller;
  @override
  bool isRunning() => running;
  @override
  Future<void> run() async {
    running = true;
    if (!deferCreation) created();
  }

  void created() {
    params.onWebViewCreated?.call(
      InAppWebViewController.fromPlatform(platform: controller),
    );
  }

  @override
  Future<void> dispose() async {
    running = false;
    disposed = true;
  }
}

class _Inline extends PlatformInAppWebViewWidget {
  _Inline(super.params) : super.implementation();
  bool created = false;
  _Controller? controller;

  @override
  Widget build(BuildContext context) {
    if (!created) {
      created = true;
      final headless = params.headlessWebView as _Headless?;
      final controller = headless?.controller ?? _Controller(params);
      this.controller = controller;
      controller.callbacks = params;
      if (headless != null) headless.running = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        params.onWebViewCreated?.call(
          InAppWebViewController.fromPlatform(platform: controller),
        );
      });
    }
    return const SizedBox.expand();
  }

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      InAppWebViewController.fromPlatform(platform: controller) as T;
  @override
  void dispose() => controller?.dispose(isKeepAlive: true);
}

void main() {
  late _Platform platform;
  late WebViewBrowser browser;
  InAppWebViewPlatform? previous;
  setUp(() {
    previous = InAppWebViewPlatform.instance;
    InAppWebViewPlatform.instance = platform = _Platform();
    browser = WebViewBrowser(workspace: _Workspace());
  });
  tearDown(() {
    if (previous != null) InAppWebViewPlatform.instance = previous;
  });

  testWidgets('silent sessions navigate and read without opening a surface', (
    tester,
  ) async {
    var requests = 0;
    browser.onRequestOpen = () => requests++;
    final cancel = CancelToken();
    final session = await browser.startSession(silent: true, cancel: cancel);
    await browser.open('https://example.com/', cancel);
    final page = await browser.read(cancel);
    expect(session['silent'], true);
    expect(page.text, 'Page content');
    expect(page.url, 'https://example.com/');
    expect(requests, 0);
    expect(browser.viewMounted, false);
    expect(platform.headless, hasLength(1));
    browser.dispose();
    await tester.pump();
    expect(platform.headless.single.disposed, true);
  });

  testWidgets('opening a silent tab keeps its page and offscreen control', (
    tester,
  ) async {
    final cancel = CancelToken();
    await browser.startSession(silent: true, cancel: cancel);
    await browser.open('https://example.com/', cancel);
    final headless = platform.headless.single;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(builder: browser.buildSurface),
      ),
    );
    await tester.pump();
    expect(platform.inline, hasLength(1));
    expect(platform.inline.single.params.headlessWebView, same(headless));
    expect(headless.controller.loads, 1);
    expect((await browser.read(cancel)).url, 'https://example.com/');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(browser.viewMounted, false);
    expect((await browser.read(cancel)).text, 'Page content');
    expect(headless.controller.loads, 1);
    browser.dispose();
    await tester.pump();
  });

  testWidgets('delayed headless creation never opens the browser screen', (
    tester,
  ) async {
    platform.deferCreation = true;
    var requests = 0;
    browser.onRequestOpen = () => requests++;
    final started = browser.startSession(silent: true, cancel: CancelToken());
    await tester.pump();
    expect(requests, 0);
    platform.headless.single.created();
    await started;
    browser.dispose();
    await tester.pump();
  });

  testWidgets('closing a silent tab releases its headless WebView', (
    tester,
  ) async {
    await browser.startSession(silent: true, cancel: CancelToken());
    final headless = platform.headless.single;
    await browser.closeTab(browser.activeTabId);
    await tester.pump();
    expect(headless.disposed, true);
    browser.dispose();
    await tester.pump();
  });
}
