import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/browser/browser_tabs.dart';

class _Tab {
  _Tab(this.id);
  final int id;
  String url = '';
}

BrowserTabs<_Tab> _tabs({int limit = maxBrowserTabs}) => BrowserTabs<_Tab>(
  create: _Tab.new,
  isBlank: (tab) => tab.url.isEmpty,
  limit: limit,
);

void main() {
  test('starts with one blank tab, which the first page reuses', () {
    final tabs = _tabs();
    expect(tabs.ids, [1]);
    final opened = tabs.openForUser();
    expect(opened.tab.id, 1);
    expect(opened.removed, isEmpty);
    opened.tab.url = 'https://a.example/';
    expect(tabs.openForUser().tab.id, 2);
    expect(tabs.activeId, 2);
  });

  test('the model never navigates a page the user is on', () {
    final tabs = _tabs();
    tabs.active.url = 'https://user.example/';
    final first = tabs.openForModel().tab..url = 'https://model.example/';
    expect(first.id, isNot(1));
    expect(tabs.activeId, first.id);
    expect(tabs.openedByModel(first.id), isTrue);
    expect(tabs.openedByModel(1), isFalse);
    // Later pages of the same response reuse the model's tab, even after the
    // user looked at another one.
    tabs.select(1);
    expect(tabs.openForModel().tab.id, first.id);
    expect(tabs.activeId, first.id);
    // The next response gets a tab of its own.
    tabs.endResponse();
    expect(tabs.openForModel().tab.id, isNot(first.id));
    expect(tabs.length, 3);
  });

  test('a blank tab in front is the model\'s tab', () {
    final tabs = _tabs();
    expect(tabs.openForModel().tab.id, 1);
    expect(tabs.openedByModel(1), isTrue);
    expect(tabs.length, 1);
  });

  test('the least recently used tab gives way at the limit', () {
    final tabs = _tabs(limit: 3);
    for (var i = 0; i < 3; i++) {
      tabs.openForUser().tab.url = 'https://$i.example/';
    }
    expect(tabs.ids, [1, 2, 3]);
    tabs.select(1);
    final opened = tabs.openForUser();
    expect(opened.removed.single.id, 2);
    expect(tabs.ids, [1, 3, 4]);
    expect(tabs.activeId, 4);
  });

  test('closing shows the most recent tab; the last one leaves a blank', () {
    final tabs = _tabs();
    tabs.active.url = 'https://a.example/';
    tabs.openForUser().tab.url = 'https://b.example/';
    tabs.openForUser().tab.url = 'https://c.example/';
    tabs.select(1);
    tabs.select(3);
    expect(tabs.close(3)?.id, 3);
    expect(tabs.activeId, 1);
    expect(tabs.close(99), isNull);
    tabs
      ..close(1)
      ..close(2);
    expect(tabs.length, 1);
    expect(tabs.active.url, isEmpty);
  });

  test('closing the model\'s tab ends its reuse; reset leaves one blank', () {
    final tabs = _tabs();
    tabs.active.url = 'https://user.example/';
    final model = tabs.openForModel().tab..url = 'https://m.example/';
    tabs.close(model.id);
    final next = tabs.openForModel().tab;
    expect(next.id, isNot(model.id));
    final removed = tabs.reset();
    expect(removed, hasLength(2));
    expect(tabs.length, 1);
    expect(tabs.openedByModel(tabs.activeId), isFalse);
  });
}
