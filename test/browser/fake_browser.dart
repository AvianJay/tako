import 'package:flutter/widgets.dart';
import 'package:tako/core/browser/browser_capability.dart';
import 'package:tako/core/browser/browser_tabs.dart';
import 'package:tako/core/providers/cancel_token.dart';
import 'package:tako/core/util/json.dart';

class FakeElement {
  const FakeElement(
    this.tag,
    this.label, {
    this.type = '',
    this.sensitive = false,
    this.submits = false,
    this.formMethod = '',
    this.submitLabels = '',
    this.download = false,
    this.click,
    this.submit,
  });
  final String tag;
  final String label;
  final String type;
  final bool sensitive;
  final bool submits;
  final String formMethod;
  final String submitLabels;
  final bool download;

  /// URL to navigate to when clicked.
  final String? click;

  /// URL to navigate to when text is typed with submit=true.
  final String Function(String text)? submit;
}

class FakePage {
  const FakePage(this.title, this.text, this.elements);
  final String title;
  final String text;
  final List<FakeElement> elements;
}

class _FakeTab {
  _FakeTab(this.id);
  final int id;
  String url = '';
  final history = <String>[];
  int? readRevision;
}

/// A scripted site standing in for the WebView. Ids are numbered per read and
/// become stale after navigation or a newer read, like the injected runtime.
/// Tabs follow the real policy (BrowserTabs).
class FakeBrowser extends BrowserCapability {
  FakeBrowser(this.site, {this.available = true});
  final Map<String, FakePage> site;
  final bool available;
  final log = <String>[];
  int openRequests = 0;
  int _revision = 0;
  bool _active = false;
  bool _mounted = false;
  bool _requested = false;
  bool silent = false;
  late final _tabs = BrowserTabs<_FakeTab>(
    create: _FakeTab.new,
    isBlank: (tab) => tab.url.isEmpty,
  );

  _FakeTab get _tab => _tabs.active;
  String get _url => _tab.url;
  set _url(String value) => _tab.url = value;
  int? get _readRevision => _tab.readRevision;
  set _readRevision(int? value) => _tab.readRevision = value;

  /// The history of the tab in front.
  List<String> get history => _tab.history;
  FakePage? get page => site[_url];

  @override
  bool get isAvailable => available;
  @override
  String get url => _url;
  @override
  String get title => page?.title ?? '';
  @override
  bool get loading => false;
  @override
  double get progress => 1;
  @override
  bool get canGoBack => history.length > 1;
  @override
  bool get canGoForward => false;
  @override
  bool get modelActive => _active;
  @override
  bool get viewMounted => _mounted;
  @override
  List<BrowserTabInfo> get tabs => [
    for (final id in _tabs.ids)
      BrowserTabInfo(
        id: id,
        url: _tabs[id]!.url,
        title: site[_tabs[id]!.url]?.title ?? '',
        openedByModel: _tabs.openedByModel(id),
      ),
  ];
  @override
  int get activeTabId => _tabs.activeId;

  @override
  Future<void> newTab({String? url}) async {
    _tabs.openForUser();
    log.add('new tab');
    notifyListeners();
    if (url != null) _go(url);
  }

  @override
  void selectTab(int id) {
    if (_tabs.select(id)) notifyListeners();
  }

  @override
  Future<void> closeTab(int id) async {
    if (_tabs.close(id) != null) notifyListeners();
  }

  void _act() {
    // Like the WebView browser, ask for the screen once until it is shown.
    if (!silent && !_mounted && !_requested) {
      openRequests++;
      _requested = true;
      onRequestOpen?.call();
    }
    if (!_active) {
      _active = true;
      notifyListeners();
    }
  }

  void _go(String address) {
    // A bare origin loads its root page, as a WebView would.
    final url = site.containsKey(address) ? address : '$address/';
    if (!site.containsKey(url)) throw const BrowserException('load_failed');
    history.add(url);
    _url = url;
    _readRevision = null;
    log.add('load $url');
    notifyListeners();
  }

  @override
  Widget buildSurface(BuildContext context) => _FakeSurface(browser: this);

  @override
  Future<void> navigate(String url) async => _go(url);
  @override
  Future<void> goBack() async {
    if (history.length < 2) return;
    history.removeLast();
    _url = history.last;
    _readRevision = null;
    notifyListeners();
  }

  @override
  Future<void> goForward() async {}
  @override
  Future<void> reload() async {}
  @override
  void takeOver() {
    silent = false;
    _active = false;
    _tabs.endResponse();
    notifyListeners();
    onTakeOver?.call();
  }

  @override
  void endModelSession() {
    silent = false;
    _active = false;
    _tabs.endResponse();
    notifyListeners();
  }

  @override
  Future<void> clearBrowsingData() async => log.add('clear');

  @override
  Future<JsonMap> startSession({
    required bool silent,
    required CancelToken cancel,
  }) async {
    cancel.throwIfCancelled();
    this.silent = silent;
    _tabs.openForModel();
    _act();
    return {'started': true, 'silent': silent, 'tab_id': activeTabId};
  }

  @override
  Future<JsonMap> open(String url, CancelToken cancel) async {
    cancel.throwIfCancelled();
    // The model's own tab, as in the WebView browser.
    _tabs.openForModel();
    _act();
    _go(url);
    return {'opened': url, 'title': title};
  }

  @override
  Future<BrowserSnapshot> read(CancelToken cancel) async {
    cancel.throwIfCancelled();
    _act();
    final current = page;
    if (current == null) {
      return const BrowserSnapshot(
        url: 'about:blank',
        title: '',
        text: '',
        elements: [],
      );
    }
    _readRevision = ++_revision;
    log.add('read $_url');
    return BrowserSnapshot(
      url: _url,
      title: current.title,
      text: current.text,
      elements: [
        for (final (index, element) in current.elements.indexed)
          BrowserElement(
            id: index + 1,
            tag: element.tag,
            type: element.type,
            label: element.label,
            flags: [if (element.sensitive) 'sensitive'],
          ),
      ],
    );
  }

  FakeElement _element(int id) {
    final elements = page?.elements ?? const [];
    if (id < 1 || id > elements.length) {
      throw const BrowserException('unknown_id');
    }
    return elements[id - 1];
  }

  @override
  Future<BrowserTarget> resolve(int id, CancelToken cancel) async {
    cancel.throwIfCancelled();
    _act();
    final revision = _readRevision;
    if (revision == null) throw const BrowserException('read_page_first');
    final element = _element(id);
    return BrowserTarget(
      id: id,
      tag: element.tag,
      type: element.type,
      label: element.label,
      check: '$revision:$id',
      pageUrl: _url,
      isSensitive: element.sensitive,
      isEditable: element.tag == 'input',
      submitsForm: element.submits,
      formMethod: element.formMethod,
      submitLabels: element.submitLabels,
      isDownload: element.download,
    );
  }

  @override
  Future<JsonMap> click(BrowserTarget target, CancelToken cancel) async {
    cancel.throwIfCancelled();
    if (target.check != '$_readRevision:${target.id}') {
      return {'error': 'element_changed_read_again'};
    }
    final element = _element(target.id);
    log.add('click ${element.label}');
    if (element.click case final next?) _go(next);
    return {'clicked': element.label, 'navigated': element.click != null};
  }

  @override
  Future<JsonMap> type(
    BrowserTarget target,
    String text, {
    required bool submit,
    required CancelToken cancel,
  }) async {
    cancel.throwIfCancelled();
    if (target.check != '$_readRevision:${target.id}') {
      return {'error': 'element_changed_read_again'};
    }
    final element = _element(target.id);
    if (element.sensitive) return {'error': 'password_entry_blocked'};
    log.add('type ${element.label}=$text${submit ? ' ⏎' : ''}');
    if (submit && element.submit != null) _go(element.submit!(text));
    return {'typed': true, 'submitted': submit};
  }

  @override
  Future<JsonMap> scroll(String direction, CancelToken cancel) async {
    log.add('scroll $direction');
    return {'scrolled': true};
  }

  @override
  Future<JsonMap> back(CancelToken cancel) async {
    if (!canGoBack) throw const BrowserException('no_previous_page');
    await goBack();
    return {'url': _url};
  }
}

class _FakeSurface extends StatefulWidget {
  const _FakeSurface({required this.browser});
  final FakeBrowser browser;
  @override
  State<_FakeSurface> createState() => _FakeSurfaceState();
}

class _FakeSurfaceState extends State<_FakeSurface> {
  @override
  void initState() {
    super.initState();
    widget.browser
      .._mounted = true
      .._requested = false;
  }

  @override
  void dispose() {
    widget.browser._mounted = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand(key: ValueKey('fake-browser-surface'));
}

/// A small shop: search, results with a harmless and a high-risk button.
FakeBrowser shopBrowser() => FakeBrowser({
  'https://shop.example.com/': FakePage('Shop', 'Welcome to the shop.', [
    FakeElement(
      'input',
      'Search products',
      type: 'search',
      submitLabels: 'Search',
      formMethod: 'get',
      submit: (text) => 'https://shop.example.com/search?q=$text',
    ),
    const FakeElement('a', 'Sign in', click: 'https://shop.example.com/login'),
  ]),
  'https://shop.example.com/search?q=tea':
      const FakePage('Results for tea', 'Green tea 12 USD. Oolong 15 USD.', [
        FakeElement('a', 'Green tea'),
        FakeElement(
          'button',
          'Add to cart',
          click: 'https://shop.example.com/cart',
        ),
        FakeElement('button', 'Send as gift'),
        FakeElement(
          'button',
          'Continue',
          submits: true,
          formMethod: 'post',
          click: 'https://shop.example.com/cart',
        ),
      ]),
  'https://shop.example.com/login': const FakePage('Sign in', 'Sign in.', [
    FakeElement('input', 'Email', type: 'email'),
    FakeElement('input', 'Password', type: 'password', sensitive: true),
    FakeElement(
      'input',
      'Promo code',
      type: 'text',
      submitLabels: 'Pay now',
      formMethod: 'get',
    ),
    FakeElement(
      'textarea',
      'Comment',
      submitLabels: 'Save',
      formMethod: 'post',
    ),
  ]),
  'https://shop.example.com/cart': const FakePage(
    'Cart',
    'Cart: Green tea x1.',
    [FakeElement('a', 'Checkout')],
  ),
});
