import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/providers/cancel_token.dart';
import 'package:tako/core/shortcuts/shortcuts_capability.dart';
import 'package:tako/core/tools/shortcut_tools.dart';
import 'package:tako/core/tools/tool.dart';
import 'package:tako/platform/ios/ios_api.g.dart';
import 'package:tako/platform/ios/ios_shortcuts.dart';

class _Api extends IosApi {
  final opened = <Uri>[];
  bool opens = true;
  @override
  Future<bool> openUrl(String url) async {
    opened.add(Uri.parse(url));
    return opens;
  }

  @override
  Future<void> excludeFromBackup(String path) async {}
}

Map<String, Object?> _json(String content) =>
    jsonDecode(content) as Map<String, Object?>;

ToolContext _context([CancelToken? cancel]) => ToolContext(
  conversationId: 'c',
  messageId: 'm',
  cancel: cancel ?? CancelToken(),
);

void main() {
  late _Api api;
  late IosShortcuts shortcuts;
  late Tool list;
  late Tool run;

  setUp(() {
    api = _Api();
    shortcuts = IosShortcuts(api: api, listen: false)
      ..names = ['Log water', 'Home & Away'];
    [list, run] = createShortcutTools(shortcuts);
  });

  /// Completes the run the Shortcuts app was asked for.
  Future<void> callBack(String status, {String? result}) async {
    while (api.opened.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final success = Uri.parse(api.opened.last.queryParameters['x-success']!);
    shortcuts.shortcutFinished(
      success.pathSegments.first,
      status,
      result,
      null,
    );
  }

  test('lists only what the user allowed; listing is safe', () async {
    expect(list.riskFor({}, _context()), RiskLevel.safe);
    final result = await list.run({}, _context());
    expect(_json(result.content), {
      'shortcuts': ['Log water', 'Home & Away'],
    });
    shortcuts.names = [];
    expect(
      _json((await list.run({}, _context())).content)['note'],
      contains('Settings'),
    );
  });

  test('a run always asks, and unknown names never open Shortcuts', () async {
    expect(run.riskFor({'name': 'Log water'}, _context()), RiskLevel.high);
    final result = await run.run({'name': 'Delete all'}, _context());
    expect(result.isError, isTrue);
    expect(_json(result.content)['error'], 'unknown_shortcut');
    expect(api.opened, isEmpty);
  });

  test('runs through the x-callback URL and returns its output', () async {
    final pending = run.run({
      'name': 'Home & Away',
      'input': 'a b+c',
    }, _context());
    await callBack('success', result: '8 glasses');
    final result = await pending;
    expect(_json(result.content), {'status': 'success', 'output': '8 glasses'});
    expect(result.sideEffects.single.kind, 'shortcut_run');
    final url = api.opened.single;
    expect(
      url.toString(),
      startsWith('shortcuts://x-callback-url/run-shortcut'),
    );
    // Percent-encoded: Shortcuts does not read + as a space.
    expect(url.toString(), contains('name=Home%20%26%20Away'));
    expect(url.toString(), contains('text=a%20b%2Bc'));
    expect(url.queryParameters['input'], 'text');
    final id = Uri.parse(url.queryParameters['x-success']!).pathSegments.first;
    expect(url.queryParameters['x-success'], 'tako://shortcut/$id/success');
    expect(url.queryParameters['x-cancel'], 'tako://shortcut/$id/cancel');
  });

  test('a cancelled or failed Shortcut is an error for the model', () async {
    final pending = run.run({'name': 'Log water'}, _context());
    await callBack('cancel');
    final result = await pending;
    expect(result.isError, isTrue);
    expect(_json(result.content)['status'], 'cancel');
  });

  test(
    'Shortcuts that cannot open, or never call back, are reported',
    () async {
      api.opens = false;
      final closed = await run.run({'name': 'Log water'}, _context());
      expect(_json(closed.content)['error'], 'shortcuts_not_opened');
      expect(closed.sideEffects, isEmpty);

      api.opens = true;
      await expectLater(
        shortcuts.run(
          'Log water',
          timeout: const Duration(milliseconds: 10),
          cancel: CancelToken(),
        ),
        throwsA(
          isA<ShortcutException>().having((e) => e.code, 'code', 'timeout'),
        ),
      );
    },
  );

  test('Stop ends the wait', () async {
    final cancel = CancelToken();
    final pending = shortcuts.run(
      'Log water',
      timeout: const Duration(minutes: 2),
      cancel: cancel,
    );
    while (api.opened.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    cancel.cancel();
    await expectLater(pending, throwsA(isA<RequestCancelled>()));
    // A late callback is ignored.
    final id = Uri.parse(
      api.opened.single.queryParameters['x-success']!,
    ).pathSegments.first;
    shortcuts.shortcutFinished(id, 'success', 'late', null);
  });
}
