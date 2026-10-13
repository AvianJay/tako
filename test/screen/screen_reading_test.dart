import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/screen/screen_capability.dart';
import 'package:tako/core/screen/screen_reading.dart';
import 'package:tako/core/tools/device_tools.dart';

const _click = ScreenFlags.enabled | ScreenFlags.clickable;
const _field =
    ScreenFlags.enabled | ScreenFlags.editable | ScreenFlags.clickable;

ScreenTree _tree(List<ScreenNode> nodes, {List<ScreenWindow>? windows}) =>
    ScreenTree(
      token: 1,
      packageName: 'com.example',
      appLabel: 'Example',
      width: 1080,
      height: 2400,
      windows:
          windows ?? const [ScreenWindow(id: 1, packageName: 'com.example')],
      nodes: nodes,
    );

void main() {
  test('visible unnamed image IDs are discoverable without a screenshot', () {
    final reading = ScreenReading.from(
      _tree(const [
        ScreenNode(
          className: 'Image',
          viewId: 'ic_search_cart',
          bounds: ScreenBounds(360, 70, 384, 94),
        ),
        ScreenNode(
          className: 'android.widget.ImageView',
          viewId: 'send_icon',
          bounds: ScreenBounds(50, 500, 90, 540),
        ),
        ScreenNode(
          className: 'Image',
          viewId: 'clipped',
          bounds: ScreenBounds(-10, 70, 14, 94),
        ),
        ScreenNode(
          className: 'Image',
          viewId: 'empty',
          bounds: ScreenBounds(0, 0, 0, 0),
        ),
        ScreenNode(
          className: 'Other',
          viewId: 'whole_page',
          bounds: ScreenBounds(0, 0, 1080, 2400),
        ),
        ScreenNode(
          className: 'Image',
          description: 'Logo',
          viewId: 'logo',
          bounds: ScreenBounds(0, 0, 40, 40),
        ),
        ScreenNode(className: 'Button', description: 'Send', flags: _click),
        ScreenNode(
          className: 'Image',
          parent: 6,
          viewId: 'send_image',
          bounds: ScreenBounds(100, 100, 140, 140),
        ),
      ]),
    );
    expect(reading.elements.map((e) => e.node), [0, 1, 5, 6]);
    expect(
      reading.elements.first.describe(),
      '[1] Image "ic search cart" view_id="ic_search_cart"',
    );
    expect(reading.elements[1].viewId, 'send_icon');
    expect(reading.elements.last.viewId, isNull);
    expect(reading.hasImage, false);
  });
  test('view ids read as words', () {
    expect(humanizeViewId('com.whatsapp:id/send_btn'), 'send btn');
    expect(humanizeViewId('com.app:id/sendButton'), 'send button');
    expect(humanizeViewId('fab-compose.icon'), 'fab compose icon');
    expect(humanizeViewId(null), '');
  });

  test('fields show their value but never a password or a hint as text', () {
    final reading = ScreenReading.from(
      _tree(const [
        ScreenNode(className: 'android.widget.LinearLayout'),
        ScreenNode(
          parent: 0,
          className: 'android.widget.EditText',
          text: 'taipei 101',
          hint: 'Search',
          flags: _field | ScreenFlags.focused,
        ),
        // An empty field reports its hint as its text.
        ScreenNode(
          parent: 0,
          className: 'android.widget.EditText',
          text: 'Email',
          hint: 'Email',
          flags: _field,
        ),
        ScreenNode(
          parent: 0,
          className: 'android.widget.EditText',
          text: '••••',
          hint: 'Password',
          flags: _field | ScreenFlags.password,
        ),
      ]),
    );
    expect(reading.elements.map((element) => element.describe()), [
      '[1] Field "Search" = "taipei 101" (focused)',
      '[2] Field "Email"',
      '[3] Field "Password" (password)',
    ]);
  });

  test('long screens keep element ids within the output budget', () {
    final reading = ScreenReading.from(
      _tree([
        const ScreenNode(
          className: 'androidx.recyclerview.widget.RecyclerView',
          flags: ScreenFlags.enabled | ScreenFlags.scrollable,
        ),
        for (var i = 1; i <= 400; i++)
          ScreenNode(
            parent: 0,
            className: 'android.widget.TextView',
            text: 'Item $i with a fairly long description',
            flags: _click,
          ),
      ]),
    );
    expect(reading.elements, hasLength(150));
    expect(reading.elementsTruncated, isTrue);
    final text = reading.toToolText(maxChars: 1500);
    expect(text.length, lessThanOrEqualTo(1500));
    expect(text, contains('[1] List (scroll)'));
    expect(
      text,
      contains('[2] Button "Item 1 with a fairly long description"'),
    );
    expect(text, endsWith('[more elements: scroll and read again]'));
  });

  test('a target names what the tap reaches, including dialog text', () {
    const dialog = ScreenWindow(
      id: 7,
      packageName: 'com.example',
      bounds: ScreenBounds(100, 900, 980, 1500),
    );
    final ok = ScreenTarget.resolve(
      const ScreenTargetInfo(
        token: 1,
        node: 3,
        window: dialog,
        appLabel: 'Example',
        target: ScreenNode(
          className: 'android.widget.Button',
          text: 'OK',
          flags: _click,
        ),
        windowText: 'Remove 3 photos? Cancel OK',
      ),
    );
    expect(ok.label, 'OK');
    expect(ok.riskLabel, contains('Remove 3 photos?'));
    final icon = ScreenTarget.resolve(
      const ScreenTargetInfo(
        token: 1,
        node: -1,
        window: ScreenWindow(id: 2, packageName: 'com.example'),
        appLabel: 'Example',
        target: ScreenNode(className: 'android.widget.ImageView'),
        ancestors: [
          ScreenNode(className: 'android.widget.FrameLayout', flags: _click),
        ],
        actionText: 'Post',
      ),
      x: 10,
      y: 20,
    );
    expect(icon.label, 'Post');
    expect(icon.type, 'Button');
    expect(icon.details(), {
      'element': 'Button “Post”',
      'point': '(10, 20)',
      'app': 'Example',
    });
  });

  test('secret fields are recognized without a password flag', () {
    ScreenTarget field(String hint) => ScreenTarget.resolve(
      ScreenTargetInfo(
        token: 1,
        node: 0,
        window: const ScreenWindow(id: 1, packageName: 'com.example'),
        appLabel: 'Example',
        target: ScreenNode(
          className: 'android.widget.EditText',
          hint: hint,
          flags: _field,
        ),
      ),
    );
    for (final hint in [
      'Verification code',
      'Enter PIN',
      '驗證碼',
      'Card number',
      'CVV',
    ]) {
      expect(field(hint).password, isTrue, reason: hint);
    }
    for (final hint in [
      'Shopping list',
      'Spinner speed',
      'Message',
      'Opinion',
    ]) {
      expect(field(hint).password, isFalse, reason: hint);
    }
    expect(field('Search places').searchField, isTrue);
    expect(field('搜尋').searchField, isTrue);
  });

  test('app names match exactly, then by prefix, then by part', () {
    const apps = [
      (label: 'Settings', packageName: 'com.android.settings'),
      (label: 'Messages', packageName: 'com.google.android.apps.messaging'),
      (label: 'Messenger', packageName: 'com.facebook.orca'),
      (label: '設定助理', packageName: 'com.example.helper'),
    ];
    expect(
      matchApps('settings', apps).single.packageName,
      'com.android.settings',
    );
    expect(matchApps('Messages', apps).single.label, 'Messages');
    expect(matchApps('mess', apps), hasLength(2));
    expect(matchApps('com.facebook.orca', apps).single.label, 'Messenger');
    expect(matchApps('Calendar', apps), isEmpty);
    expect(similarApps('設定', apps).single.label, '設定助理');
  });
}
