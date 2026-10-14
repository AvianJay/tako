import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/files/workspace.dart';
import 'package:tako/core/permissions/permission_gate.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/core/screen/remote_control_agent.dart';
import 'package:tako/core/screen/screen_capability.dart';
import 'package:tako/core/screen/screen_reading.dart';
import 'package:tako/core/tools/device_tools.dart';
import 'package:tako/core/tools/screen_tools.dart';
import 'package:tako/core/tools/screen_workflow_tool.dart';
import 'package:tako/core/tools/tool.dart';
import 'package:tako/core/tools/tool_executor.dart';
import 'package:tako/core/tools/tool_registry.dart';
import 'package:tako/core/util/json.dart';
import 'package:tako/data/audit_repository.dart';
import 'package:tako/data/database.dart';
import 'package:tako/platform/device_tools_capability.dart';
import 'package:tako/platform/repl/quickjs_repl.dart';

import 'fake_screen.dart';

class _Workspace implements WorkspaceCapability {
  @override
  bool get isAvailable => true;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Worker must not persist screenshots');
}

class _Adapter implements ProviderAdapter {
  _Adapter(this.turns);
  final List<List<ProviderEvent>> turns;
  final requests = <ChatRequest>[];
  @override
  Future<List<ModelInfo>> listModels({CancelToken? cancel}) async => [];
  @override
  Stream<ProviderEvent> send(
    ChatRequest request, {
    required CancelToken cancel,
  }) async* {
    final index = requests.length;
    requests.add(request);
    for (final event in turns[index]) {
      yield event;
    }
  }
}

List<ProviderEvent> call(String tool, Map<String, Object?> args) => [
  ToolCallStart('action', tool),
  ToolCallArgsDelta('action', jsonEncode(args)),
  const ToolCallEnd('action'),
  const Done('tool_use'),
];

class _Launch implements DeviceToolsCapability {
  _Launch(this.screen);
  final FakeScreen screen;
  @override
  bool get isAvailable => true;
  @override
  bool supports(String tool) => tool == 'open_app';
  @override
  Future<Map<String, Object?>> invoke(
    String tool,
    Map<String, Object?> arguments, {
    required CancelToken cancel,
  }) async {
    screen.launch(arguments['package'] as String? ?? 'com.example.fixture');
    return {'launched': true};
  }
}

class _BusyScreen extends FakeScreen {
  _BusyScreen(super.views) : super(start: 'start');
  int reads = 0;
  bool busyInitially = false;
  @override
  Future<ScreenTree> snapshot({
    required bool screenshot,
    required CancelToken cancel,
  }) {
    reads++;
    if (busyInitially) {
      throw const ScreenException(
        'ictrl_rpc_failed_read_again',
        detail:
            'page_source exceeded 15s and may still be running on the device.',
      );
    }
    return super.snapshot(screenshot: screenshot, cancel: cancel);
  }

  @override
  Future<ScreenActionOutcome> act(ScreenAction action) async {
    actions.add(action);
    throw const ScreenException(
      'ictrl_rpc_failed_read_again',
      detail: 'tap exceeded 15s and may still be running on the device.',
    );
  }
}

class _SparseScreen extends FakeScreen {
  _SparseScreen(super.views) : super(start: 'start', screenshots: true) {
    fastActions = true;
  }
  final imageAccess = <bool>[];
  @override
  Future<ScreenTree> snapshotForModel({
    required bool screenshot,
    required bool automaticScreenshot,
    required CancelToken cancel,
  }) {
    imageAccess.add(automaticScreenshot);
    return snapshot(
      screenshot: screenshot || automaticScreenshot,
      cancel: cancel,
    );
  }
}

class _PagedScreen extends FakeScreen {
  _PagedScreen(super.views) : super(start: 'start', screenshots: true) {
    fastActions = true;
  }
  final routes = <String, String>{};
  Map<String, Object?> details = {};
  void Function()? afterScroll;
  bool busy = false;
  bool targetedScroll = true;
  int reads = 0;
  @override
  bool get supportsTargetedScroll => targetedScroll;

  @override
  Future<ScreenTree> snapshot({
    required bool screenshot,
    required CancelToken cancel,
  }) {
    reads++;
    return super.snapshot(screenshot: screenshot, cancel: cancel);
  }

  @override
  Future<ScreenActionOutcome> act(ScreenAction action) async {
    if (action.action != 'scroll') return super.act(action);
    actions.add(action);
    if (busy) {
      throw const ScreenException(
        'ictrl_rpc_failed_read_again',
        detail: 'page exceeded 15s and may still be running on the device.',
      );
    }
    final next = routes[current];
    if (next != null) show(next);
    afterScroll?.call();
    return ScreenActionOutcome(
      method: 'page',
      packageName: view.packageName,
      appLabel: view.appLabel,
      changed: next != null,
      details: details,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late FakeScreen screen;
  late PermissionGate gate;
  late _Adapter adapter;
  late RemoteControlAgent agent;
  late ToolExecutor executor;
  var disabled = <String>{};
  var limit = 20;
  var repl = false;
  final token = CancelToken();
  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    screen = FakeScreen(
      {
        'start': FakeView('com.example.fixture', 'Fixture', [
          FakeWindow(box([button('Start', opens: 'done'), button('Later')])),
        ]),
        'done': FakeView('com.example.fixture', 'Fixture', [
          FakeWindow(box([label('Done'), label('Unrelated private text')])),
        ]),
        'own': FakeView(FakeScreen.ownPackage, 'Tako', [
          FakeWindow(box([label('Private main chat')])),
        ]),
      },
      start: 'start',
      screenshots: true,
    )..fastActions = true;
    gate = PermissionGate(
      policy: const PermissionPolicy(fullPermissions: true),
    );
    disabled = {};
    limit = 20;
    repl = false;
    adapter = _Adapter([
      call('tap', {'title': 'Start', 'id': 1, 'screenshot': true}),
    ]);
  });
  void build() {
    final audit = AuditRepository(database);
    agent = RemoteControlAgent(
      screen: screen,
      workspace: _Workspace(),
      deviceTools: (observer) =>
          createDeviceTools(_Launch(screen), observer: observer),
      permissions: gate,
      audit: audit,
      available: () => true,
      backend: () async => (
        config: ProviderConfig(
          id: 'worker',
          displayName: 'Worker',
          apiType: ApiType.messages,
          baseUrl: 'https://example.com',
          model: 'claude-haiku-5-5',
          capabilities: const ProviderCapabilities(tools: true, vision: true),
        ),
        adapter: adapter,
      ),
      screenshots: () => true,
      disabledTools: () => disabled,
      stepLimit: () => limit,
      useRepl: (_) => repl,
      runtimeFactory: QuickJsRepl.new,
    );
    executor = ToolExecutor(
      registry: ToolRegistry(agent.tools),
      permissions: gate,
      audit: audit,
    );
  }

  Future<ToolResultBlock> run({
    List<String> expected = const ['Done'],
    String? app,
    String? query,
    String? resultKind,
    int? minResults,
    List<Map<String, Object?>>? workflow,
    CancelToken? cancel,
  }) async => (await executor.execute(
    ToolCallBlock(
      id: 'delegate',
      name: 'remote_control',
      arguments: jsonEncode({
        'title': 'Start task',
        'task': 'Start and finish',
        'success_criteria': 'Done must be visible',
        'expected_text': expected,
        'expected_app': ?app,
        'result_contains': ?query,
        'result_kind': ?resultKind,
        'min_results': ?minResults,
        'workflow': ?workflow,
      }),
    ),
    ToolContext(
      conversationId: 'chat',
      messageId: 'main-response',
      cancel: cancel ?? CancelToken(),
    ),
  )).result;
  tearDown(() async {
    screen.dispose();
    await database.close();
  });

  test(
    'a remote worker uses guided REPL while native verification and budgets stay outside JS',
    () async {
      repl = true;
      adapter = _Adapter([
        call('read_skill', {'skill': 'phone'}),
        call('js_repl', {
          'title': 'Start',
          'code':
              'var s = await phone.read(); await phone.tap(s.elements.find(e => e.label === "Start"));',
        }),
        [const TextDelta('Done.'), const Done('stop')],
      ]);
      build();
      final result = await run();
      expect(result.isError, isFalse, reason: result.content);
      expect(tryDecodeObject(result.content)?['verified'], true);
      expect(screen.current, 'done');
      expect(
        adapter.requests.first.tools.map((tool) => tool.name),
        containsAll(['read_skill', 'js_repl']),
      );
      expect(
        adapter.requests.first.tools.map((tool) => tool.name),
        isNot(contains('tap')),
      );
      expect(
        result.sideEffects.where((effect) => effect.kind == 'screen_tapped'),
        hasLength(1),
      );
    },
  );

  test(
    'bad final-text shape is corrected before contacting the worker',
    () async {
      build();
      final invalid = (await executor.execute(
        ToolCallBlock(
          id: 'bad-delegate',
          name: 'remote_control',
          arguments: jsonEncode({
            'title': 'Start task',
            'task': 'Start and finish',
            'success_criteria': 'Done must be visible',
            'expected_text': 'Done',
          }),
        ),
        ToolContext(
          conversationId: 'chat',
          messageId: 'main-response',
          cancel: CancelToken(),
        ),
      )).result;
      final error = jsonDecode(invalid.content) as Map;
      expect(error['error'], 'invalid_arguments');
      expect(error['path'], r'$.expected_text');
      expect(error['expected'], 'array');
      expect(adapter.requests, isEmpty);
      expect(screen.actions, isEmpty);
      final corrected = await run();
      final receipt = jsonDecode(corrected.content) as Map<String, Object?>;
      expect(receipt['status'], 'verified');
      expect(adapter.requests, hasLength(1));
    },
  );
  for (final fieldName in ['Search', '搜尋', 'Find products']) {
    test(
      'local search opens entry and submits $fieldName in one round',
      () async {
        screen.views['start'] = FakeView('com.example.fixture', 'Fixture', [
          FakeWindow(box([button('Search', opens: 'search')])),
        ]);
        screen.views['search'] = FakeView('com.example.fixture', 'Fixture', [
          FakeWindow(box([field(description: fieldName, submits: 'done')])),
        ]);
        adapter = _Adapter([
          call('screen_workflow', {
            'title': 'Find a stand',
            'steps': [
              {
                'tool': 'search',
                'expect_app': 'com.example.fixture',
                'text': 'foldable stand',
              },
            ],
          }),
        ]);
        build();
        final receipt = jsonDecode((await run()).content) as Map;
        expect(receipt['status'], 'verified');
        expect(adapter.requests, hasLength(1));
        expect(screen.actions.map((a) => a.action), ['tap', 'set_text']);
        expect(screen.actions.last.text, 'foldable stand');
        expect(screen.actions.last.submit, true);
      },
    );
  }
  test('local search refuses ambiguous fields without typing', () async {
    screen.views['start'] = FakeView('com.example.fixture', 'Fixture', [
      FakeWindow(
        box([field(description: 'Search A'), field(description: 'Search B')]),
      ),
    ]);
    adapter = _Adapter([
      call('screen_workflow', {
        'title': 'Search',
        'steps': [
          {
            'tool': 'search',
            'expect_app': 'com.example.fixture',
            'text': 'query',
          },
        ],
      }),
      [
        const TextDelta('Cannot finish: search fields are ambiguous.'),
        const Done('end_turn'),
      ],
      [
        const TextDelta('Not completed: search fields remain ambiguous.'),
        const Done('end_turn'),
      ],
    ]);
    build();
    final result = await run();
    expect(result.isError, true);
    expect(screen.actions, isEmpty);
    expect(
      (await AuditRepository(database).list()).any(
        (r) => r.resultSummary.contains('workflow_search_missing_or_ambiguous'),
      ),
      true,
    );
  });
  test('local search honors type deny after authorized entry tap', () async {
    screen.views['start'] = FakeView('com.example.fixture', 'Fixture', [
      FakeWindow(box([button('Search', opens: 'search')])),
    ]);
    screen.views['search'] = FakeView('com.example.fixture', 'Fixture', [
      FakeWindow(box([field(description: 'Search', submits: 'done')])),
    ]);
    gate.policy = const PermissionPolicy(
      fullPermissions: true,
      overrides: {'type_text': ToolPermission.deny},
    );
    adapter = _Adapter([
      call('screen_workflow', {
        'title': 'Search',
        'steps': [
          {
            'tool': 'search',
            'expect_app': 'com.example.fixture',
            'text': 'query',
          },
        ],
      }),
    ]);
    build();
    final result = await run();
    expect(result.isError, true);
    expect(screen.actions.map((a) => a.action), ['tap']);
    expect(adapter.requests, hasLength(1));
  });

  group('local list scan', () {
    late _PagedScreen paged;
    setUp(() {
      FakeView page(List<FakeNode> items) =>
          FakeView('com.example.fixture', 'Fixture', [
            FakeWindow(
              FakeNode(
                'androidx.recyclerview.widget.RecyclerView',
                flags: ScreenFlags.enabled | ScreenFlags.scrollable,
                bounds: const ScreenBounds(0, 0, 1080, 2400),
                children: [label('List header'), ...items],
              ),
            ),
          ]);
      paged = _PagedScreen({
        'start': page([label('Server Alpha')]),
        'page2': page([
          label('Server Beta'),
          row([label('64GB card'), label(r'NT$402')]),
        ]),
        'page3': page([button('Done', opens: 'finish')]),
        'finish': page([label('Finished')]),
      });
      paged.routes.addAll({'start': 'page2', 'page2': 'page3'});
      screen = paged;
    });

    Map<String, Object?> scan([Map<String, Object?> args = const {}]) => {
      'tool': 'scan',
      'expect_app': 'com.example.fixture',
      'direction': 'down',
      ...args,
    };
    ToolResultBlock scanResult(ChatRequest request) => request.messages
        .expand((m) => m.content)
        .whereType<ToolResultBlock>()
        .firstWhere((r) => r.toolName == 'screen_workflow');
    void configure(Map<String, Object?> step) {
      adapter = _Adapter([
        call('screen_workflow', {
          'title': 'Read the list',
          'steps': [step],
        }),
        [const TextDelta('Read several list pages.'), const Done('end_turn')],
      ]);
      build();
    }

    test('finds a later label in one worker round with native proof', () async {
      configure(scan({'until_label': 'Done', 'max_scrolls': 6}));
      final receipt = tryDecodeObject((await run()).content)!;
      expect(receipt['status'], 'verified');
      expect(receipt['model_rounds'], 1);
      expect(adapter.requests, hasLength(1));
      expect(paged.actions.map((a) => a.action), ['scroll', 'scroll']);
      expect(paged.actions.map((a) => a.direction), ['down', 'down']);
      expect(paged.actions.map((a) => a.token).toSet(), hasLength(2));
      final audits = await AuditRepository(database).list();
      expect(audits.where((a) => a.toolName == 'scroll'), hasLength(2));
    });

    test('keeps text notes and only final targets across apps', () async {
      configure(scan({'max_scrolls': 2}));
      final receipt = tryDecodeObject((await run(expected: [])).content)!;
      expect(receipt['verified'], false);
      expect(receipt['semantic_review_needed'], true);
      expect(adapter.requests, hasLength(2));
      final result = tryDecodeObject(scanResult(adapter.requests[1]).content)!;
      final scanned = (result['scan_results'] as List).single as Map;
      expect(result['completed'], true);
      expect(scanned['pages_read'], 3);
      expect(scanned['stop_reason'], 'max_scrolls');
      final notes = jsonEncode(scanned['untrusted_pages']);
      expect(notes, contains('Server Alpha'));
      expect(notes, contains('Server Beta'));
      expect(notes, contains('64GB card'));
      expect(notes, contains(r'NT$402'));
      expect(RegExp('List header').allMatches(notes), hasLength(1));
      expect(notes, isNot(contains('view_id')));
      expect(notes, isNot(contains('[1]')));
      expect(result['final_screen'], contains('Done'));
      expect(result['final_screen'], isNot(contains('Server Alpha')));
      expect(result['scan_note'], contains('exact variant'));
    });

    test(
      'keeps two row prices equal without losing their associations',
      () async {
        paged.views['start'] = FakeView('com.example.fixture', 'Fixture', [
          FakeWindow(
            list([
              row([label('Card Alpha'), label(r'NT$402')]),
            ]),
          ),
        ]);
        paged.views['page2'] = FakeView('com.example.fixture', 'Fixture', [
          FakeWindow(
            list([
              row([label('Card Beta'), label(r'NT$402')]),
            ]),
          ),
        ]);
        configure(scan({'max_scrolls': 1}));
        await run(expected: []);
        final result = tryDecodeObject(
          scanResult(adapter.requests[1]).content,
        )!;
        final pages =
            ((result['scan_results'] as List).single as Map)['untrusted_pages']
                as List;
        final first = ((pages[0] as Map)['new_text'] as List).single as String;
        final second = ((pages[1] as Map)['new_text'] as List).single as String;
        expect(first, contains('Card Alpha'));
        expect(first, contains(r'NT$402'));
        expect(second, contains('Card Beta'));
        expect(second, contains(r'NT$402'));
      },
    );

    for (final fast in [false, true]) {
      test('uses fresh native list targets with fastActions=$fast', () async {
        paged.fastActions = fast;
        configure(scan({'until_label': 'Done'}));
        final receipt = tryDecodeObject((await run()).content)!;
        expect(receipt['verified'], true);
        expect(adapter.requests, hasLength(1));
        expect(paged.actions, hasLength(2));
        expect(paged.actions.every((a) => a.node >= 0), true);
      });
    }

    test('iCTRL viewport paging omits ignored container ids', () async {
      paged.targetedScroll = false;
      configure(scan({'until_label': 'Done'}));
      final receipt = tryDecodeObject((await run()).content)!;
      expect(receipt['verified'], true);
      expect(adapter.requests, hasLength(1));
      final records = await AuditRepository(database).list();
      expect(
        records
            .where((a) => a.toolName == 'scroll')
            .every((a) => !tryDecodeObject(a.arguments)!.containsKey('id')),
        true,
      );
    });

    test('iCTRL rejects targeted paging before any scroll', () async {
      paged.targetedScroll = false;
      configure(scan({'view_id': 'only-this-list'}));
      await run(expected: []);
      expect(
        scanResult(adapter.requests[1]).content,
        contains('workflow_scan_targeted_scroll_unavailable'),
      );
      expect(paged.actions, isEmpty);
    });

    test('a missing scan target prevents the following planned tap', () async {
      adapter = _Adapter([
        call('screen_workflow', {
          'title': 'Find a missing target',
          'steps': [
            scan({'until_label': 'Absent', 'max_scrolls': 2}),
            {
              'tool': 'tap',
              'expect_app': 'com.example.fixture',
              'label': 'Done',
            },
          ],
        }),
        [
          const TextDelta('Read several pages; target is absent.'),
          const Done('end_turn'),
        ],
      ]);
      build();
      await run(expected: []);
      final result = tryDecodeObject(scanResult(adapter.requests[1]).content)!;
      expect(result['error'], 'workflow_scan_target_not_found');
      expect(result['completed_steps'], 0);
      expect(paged.actions.map((a) => a.action), ['scroll', 'scroll']);
    });

    test('can tap a matched target only from its fresh final screen', () async {
      adapter = _Adapter([
        call('screen_workflow', {
          'title': 'Find and open',
          'steps': [
            scan({'until_label': 'Done'}),
            {
              'tool': 'tap',
              'expect_app': 'com.example.fixture',
              'label': 'Done',
            },
          ],
        }),
      ]);
      build();
      final receipt = tryDecodeObject(
        (await run(expected: ['Finished'])).content,
      )!;
      expect(receipt['verified'], true);
      expect(adapter.requests, hasLength(1));
      expect(paged.actions.map((a) => a.action), ['scroll', 'scroll', 'tap']);
    });

    for (final selector in [
      {'until_label': 'Done'},
      {'until_contains': 'Don'},
      {'until_view_id': 'finish_button'},
    ]) {
      test('known target $selector stops before any extra scroll', () async {
        paged.views['page2'] = FakeView('com.example.fixture', 'Fixture', [
          FakeWindow(
            list([icon(description: 'Done', viewId: 'finish_button')]),
          ),
        ]);
        configure(scan(selector));
        final receipt = tryDecodeObject((await run()).content)!;
        expect(receipt['verified'], true);
        expect(paged.actions, hasLength(1));
      });
    }

    test('does not scroll when a target is already visible', () async {
      configure(scan({'until_label': 'Server Alpha'}));
      final receipt = tryDecodeObject(
        (await run(expected: ['Server Alpha'])).content,
      )!;
      expect(receipt['verified'], true);
      expect(adapter.requests, hasLength(1));
      expect(paged.actions, isEmpty);
    });

    for (final maximum in [null, 6]) {
      test(
        'enforces ${maximum ?? 'default'} scroll bound on a long list',
        () async {
          for (var page = 1; page <= 7; page++) {
            final key = 'long$page';
            paged.views[key] = FakeView('com.example.fixture', 'Fixture', [
              FakeWindow(list([label('List row $page')])),
            ]);
            paged.routes[page == 1 ? 'start' : 'long${page - 1}'] = key;
          }
          configure(scan({'max_scrolls': ?maximum}));
          await run(expected: []);
          final result = tryDecodeObject(
            scanResult(adapter.requests[1]).content,
          )!;
          final scanned = (result['scan_results'] as List).single as Map;
          expect(scanned['stop_reason'], 'max_scrolls');
          expect(paged.actions, hasLength(maximum ?? 3));
          expect(scanned['pages_read'], (maximum ?? 3) + 1);
        },
      );
    }

    test('never verifies the final screen with historical notes', () async {
      adapter = _Adapter([
        call('screen_workflow', {
          'title': 'Read the list',
          'steps': [
            scan({'max_scrolls': 2}),
          ],
        }),
        [
          const TextDelta('Device unavailable: stop here.'),
          const Done('end_turn'),
        ],
      ]);
      build();
      final receipt = tryDecodeObject(
        (await run(expected: ['Server Alpha'])).content,
      )!;
      expect(receipt['verified'], false);
      expect(receipt['missing_text'], ['Server Alpha']);
      expect(paged.actions, hasLength(2));
    });

    for (final kind in ['unchanged', 'loop', 'end', 'not_moved']) {
      test('stops without repeating on $kind', () async {
        if (kind == 'loop') {
          paged.routes['page2'] = 'start';
        } else if (kind == 'end') {
          paged.details = {'at_end': true};
        } else if (kind == 'not_moved') {
          paged.details = {'moved': false};
        } else {
          paged.routes.clear();
        }
        configure(scan({'max_scrolls': 6}));
        await run(expected: []);
        final result = tryDecodeObject(
          scanResult(adapter.requests[1]).content,
        )!;
        final scanned = (result['scan_results'] as List).single as Map;
        expect(
          scanned['stop_reason'],
          {'end', 'not_moved'}.contains(kind) ? 'end' : 'no_progress',
        );
        expect(paged.actions, hasLength(kind == 'loop' ? 2 : 1));
      });
    }

    test('honors explicit scroll denial inside a workflow', () async {
      gate.policy = const PermissionPolicy(
        fullPermissions: true,
        overrides: {'scroll': ToolPermission.deny},
      );
      configure(scan());
      final receipt = tryDecodeObject((await run(expected: [])).content)!;
      expect(receipt['reason'], 'worker_action_denied');
      expect(adapter.requests, hasLength(1));
      expect(paged.actions, isEmpty);
    });

    test('refreshes disabled tools before each internal scroll', () async {
      paged.afterScroll = () => disabled.add('scroll');
      configure(scan());
      await run(expected: []);
      expect(paged.actions, hasLength(1));
      final result = scanResult(adapter.requests[1]);
      expect(result.isError, true);
      expect(result.content, contains('tool_unavailable'));
    });

    test(
      'stops when the app changes instead of scanning the new app',
      () async {
        paged.views['page2'] = FakeView('com.example.other', 'Other', [
          FakeWindow(list([label('Another app private content')])),
        ]);
        configure(scan());
        await run(expected: []);
        final result = tryDecodeObject(
          scanResult(adapter.requests[1]).content,
        )!;
        expect(result['error'], 'workflow_app_changed');
        expect(
          jsonEncode(result['scan_results']),
          isNot(contains('Another app private content')),
        );
        expect(paged.actions, hasLength(1));
      },
    );

    test('stops on a dialog before a second scroll', () async {
      paged.views['page2'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(FakeNode('Alert', children: [button('Allow')])),
      ]);
      configure(scan());
      await run(expected: []);
      final result = tryDecodeObject(scanResult(adapter.requests[1]).content)!;
      expect(result['error'], 'workflow_scan_dialog_read_before_replanning');
      expect(paged.actions, hasLength(1));
    });

    test('rejects ambiguous targets without scrolling or tapping', () async {
      paged.views['start'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(list([button('Done'), button('Done')])),
      ]);
      configure(scan({'until_label': 'Done'}));
      await run(expected: []);
      expect(
        scanResult(adapter.requests[1]).content,
        contains('workflow_scan_target_ambiguous'),
      );
      expect(paged.actions, isEmpty);
    });

    test('rejects separate list containers rather than guessing', () async {
      paged.views['start'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(
          box([
            list([label('Left')]),
            list([label('Right')]),
          ]),
        ),
      ]);
      configure(scan());
      await run(expected: []);
      expect(
        scanResult(adapter.requests[1]).content,
        contains('workflow_scan_container_missing_or_ambiguous'),
      );
      expect(paged.actions, isEmpty);
    });

    for (final warning in [
      {'warning': 'UI changed'},
      {
        'untrusted_receipt': {'hit_warning': 'Intercepted'},
      },
      {
        'page_check': {'same_page': false},
      },
    ]) {
      test('returns warning $warning before continuing', () async {
        paged.details = warning;
        configure(scan());
        await run(expected: []);
        final result = scanResult(adapter.requests[1]);
        expect(
          result.content,
          contains('workflow_warning_read_before_replanning'),
        );
        expect(paged.actions, hasLength(1));
      });
    }

    test('reserves final proof and respects the worker step limit', () async {
      limit = 3;
      configure(scan({'max_scrolls': 6}));
      final receipt = tryDecodeObject((await run(expected: [])).content)!;
      expect(receipt['verified'], false);
      expect(receipt['reason'], 'worker_step_limit');
      expect(paged.actions, hasLength(1));
      expect(adapter.requests, hasLength(1));
    });

    test('cancellation after a committed scroll prevents later work', () async {
      final cancel = CancelToken();
      paged.afterScroll = cancel.cancel;
      configure(scan());
      final receipt = tryDecodeObject(
        (await run(expected: [], cancel: cancel)).content,
      )!;
      expect(receipt['verified'], false);
      expect(paged.actions, hasLength(1));
      expect(adapter.requests, hasLength(1));
      expect(paged.reads, 1);
      final records = await AuditRepository(database).list();
      final workflow = records.firstWhere(
        (a) => a.toolName == 'screen_workflow',
      );
      expect(workflow.resultSummary, contains('cancelled'));
      expect(workflow.resultSummary, contains('"attempted":1'));
    });

    test('a UI timeout never queues another scroll or final read', () async {
      paged.busy = true;
      configure(scan());
      final receipt = tryDecodeObject((await run(expected: [])).content)!;
      expect(receipt['reason'], 'device_ui_busy');
      expect(paged.actions, hasLength(1));
      expect(paged.reads, 1);
      expect(adapter.requests, hasLength(1));
    });

    test('bounds notes and excludes password fields', () async {
      paged.views['start'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(
          list([
            field(
              description: 'Password',
              text: 'never expose',
              password: true,
            ),
            FakeNode(
              'SecureContainer',
              flags: ScreenFlags.password | ScreenFlags.enabled,
              children: [label('nested secret')],
            ),
            for (var i = 0; i < 80; i++)
              label(
                'Row $i with enough visible information to fill the note budget',
              ),
          ]),
        ),
      ]);
      configure(scan());
      await run(expected: []);
      final result = tryDecodeObject(scanResult(adapter.requests[1]).content)!;
      final scanned = (result['scan_results'] as List).single as Map;
      expect(scanned['notes_truncated'], true);
      expect(scanned['stop_reason'], 'content_limit');
      expect(
        jsonEncode(scanned['untrusted_pages']),
        isNot(contains('never expose')),
      );
      expect(
        jsonEncode(scanned['untrusted_pages']),
        isNot(contains('nested secret')),
      );
      expect(jsonEncode(scanned['untrusted_pages']).length, lessThan(3600));
      expect(paged.actions, isEmpty);
    });

    test(
      'validates all scan arguments before earlier workflow actions',
      () async {
        configure(scan({'max_scrolls': 7}));
        adapter = _Adapter([
          call('screen_workflow', {
            'title': 'Invalid plan',
            'steps': [
              {'tool': 'open_app', 'package': 'com.example.fixture'},
              scan({'max_scrolls': 7}),
            ],
          }),
          [
            const TextDelta('Cannot finish: invalid plan.'),
            const Done('end_turn'),
          ],
          [
            const TextDelta('Not completed: invalid plan.'),
            const Done('end_turn'),
          ],
        ]);
        build();
        await run(expected: []);
        expect(
          scanResult(adapter.requests[1]).content,
          contains('invalid_arguments'),
        );
        expect(paged.actions, isEmpty);
        expect(paged.current, 'start');
      },
    );

    test('does not continue without a newly authorized observation', () async {
      final readings = ScreenReadings();
      final cancel = CancelToken();
      final ctx = ToolContext(
        conversationId: 'chat',
        messageId: 'workflow',
        cancel: cancel,
      );
      readings.remember(
        ctx,
        ScreenReading.from(
          await paged.snapshot(screenshot: false, cancel: cancel),
        ),
      );
      final audit = AuditRepository(database);
      final primitive = ToolExecutor(
        registry: ToolRegistry(
          createScreenTools(paged, workspace: _Workspace(), readings: readings),
        ),
        permissions: gate,
        audit: audit,
      );
      final workflow = ScreenWorkflowTool(
        screen: paged,
        readings: readings,
        executor: () => primitive,
        remaining: () => 10,
        onStep: (_) {},
      );
      final result = await workflow.run({
        'title': 'Read list',
        'steps': [scan()],
      }, ctx);
      expect(result.isError, true);
      expect(
        tryDecodeObject(result.content)!['error'],
        'workflow_observation_unavailable',
      );
      expect(paged.actions, hasLength(1));
    });

    test('returns a visual-only page to the worker before scrolling', () async {
      final readings = ScreenReadings();
      final ctx = ToolContext(
        conversationId: 'chat',
        messageId: 'workflow',
        cancel: CancelToken(),
      );
      readings.remember(
        ctx,
        ScreenReading.from(
          const ScreenTree(
            token: 1,
            packageName: 'com.example.fixture',
            appLabel: 'Fixture',
            width: 1080,
            height: 2400,
            requiresVisualReview: true,
            nodes: [ScreenNode(text: 'Header above a custom visual list')],
          ),
        ),
      );
      final workflow = ScreenWorkflowTool(
        screen: paged,
        readings: readings,
        executor: () =>
            throw StateError('Visual review must precede scrolling'),
        remaining: () => 10,
        onStep: (_) {},
      );
      final result = await workflow.run({
        'title': 'Read list',
        'steps': [scan()],
      }, ctx);
      expect(
        tryDecodeObject(result.content)!['error'],
        'workflow_scan_visual_review_required',
      );
      expect(paged.actions, isEmpty);
    });
  });

  test(
    'native evidence ends the worker without a final model round; parent sees no raw screens',
    () async {
      build();
      final result = await run();
      final receipt = jsonDecode(result.content) as Map;
      expect(receipt['status'], 'verified');
      expect(receipt['matched_text'], ['Done']);
      expect(adapter.requests, hasLength(1));
      expect(result.attachments, isEmpty);
      expect(result.content.length, lessThan(1000));
      expect(result.content, isNot(contains('Unrelated private text')));
      expect(
        adapter.requests.single.messages.single.text,
        contains('Current screen'),
      );
      expect(
        adapter.requests.single.tools.any((t) => t.name == 'remote_control'),
        false,
      );
      expect(
        adapter.requests.single.tools.any((t) => t.name == 'file_read'),
        false,
      );
      final audited = await AuditRepository(database).list();
      expect(
        audited.map((a) => a.toolName),
        containsAll(['remote_control', 'tap', 'read_screen']),
      );
    },
  );
  test(
    'fresh check costs no model call and rejects another conversation',
    () async {
      build();
      final result = jsonDecode((await run()).content) as Map;
      screen.show('start');
      Future<ToolResultBlock> check(String chat) async =>
          (await executor.execute(
            ToolCallBlock(
              id: 'check',
              name: 'remote_control_check',
              arguments: jsonEncode({'task_id': result['task_id']}),
            ),
            ToolContext(
              conversationId: chat,
              messageId: 'check-response',
              cancel: CancelToken(),
            ),
          )).result;
      expect(
        (jsonDecode((await check('chat')).content)
            as Map<String, Object?>)['verified'],
        false,
      );
      expect(
        (await check('another-chat')).content,
        contains('unknown_remote_task'),
      );
      expect(adapter.requests, hasLength(1));
    },
  );
  test(
    'worker reasoning keeps matching request provenance across tool rounds',
    () async {
      adapter = _Adapter([
        [
          const ReasoningDelta('Choose the next action'),
          const ReasoningMetadata(
            blockIndex: 0,
            sourceApi: 'messages',
            signature: 'opaque-signature',
          ),
          ...call('read_screen', {'title': 'Inspect'}),
        ],
        call('tap', {'title': 'Start', 'id': 1}),
      ]);
      build();
      await run();
      final request = adapter.requests[1];
      final assistant = request.messages.firstWhere(
        (m) => m.content.whereType<ReasoningBlock>().isNotEmpty,
      );
      final reasoning = assistant.content.whereType<ReasoningBlock>().single;
      expect(assistant.providerId, 'worker');
      expect(assistant.model, 'claude-haiku-5-5');
      expect(reasoning.promptHash, request.promptHash);
      expect(request.promptHash, isNotNull);
      expect(reasoning.signature, 'opaque-signature');
    },
  );
  test(
    'matching search title cannot verify an uncompleted cart task',
    () async {
      screen.views['done'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(box([label('ESP32-S3 DevKit board')])),
      ]);
      adapter = _Adapter([
        call('tap', {'title': 'Inspect board', 'id': 1}),
        [
          const TextDelta('Stopped without adding to cart'),
          const Done('end_turn'),
        ],
      ]);
      build();
      final receipt =
          jsonDecode((await run(expected: [], query: 'ESP32S3')).content)
              as Map<String, Object?>;
      expect(receipt['status'], 'reported_complete');
      expect(receipt['verified'], false);
      expect(receipt['semantic_review_needed'], true);
    },
  );
  test('worker claims cannot satisfy a missing expected label', () async {
    adapter = _Adapter([
      [const TextDelta('Task completed: Done'), const Done('end_turn')],
      [const TextDelta('Task completed: Done'), const Done('end_turn')],
    ]);
    build();
    final receipt = jsonDecode((await run()).content) as Map;
    expect(receipt['verified'], false);
    expect(receipt['missing_text'], ['Done']);
    expect(receipt['status'], 'incomplete');
    expect(adapter.requests, hasLength(2));
    expect(receipt['semantic_review_needed'], true);
  });
  test(
    'unfinished navigation recovers once without treating reminders as blockers',
    () async {
      adapter = _Adapter([
        [
          const TextDelta(
            'Not completed: stuck on navigation. I did not enter passwords.',
          ),
          const Done('end_turn'),
        ],
        call('tap', {'title': 'Recover navigation', 'id': 1}),
      ]);
      build();
      final receipt = jsonDecode((await run()).content) as Map;
      expect(receipt['status'], 'verified');
      expect(receipt['verified'], true);
      expect(adapter.requests, hasLength(2));
      expect(screen.actions, hasLength(1));
      expect(
        adapter.requests[1].messages.last.content
            .whereType<TextBlock>()
            .first
            .text,
        contains('Recover within its original scope'),
      );
    },
  );
  test('concrete login and password gates do not retry navigation', () async {
    for (final note in [
      'Unable to continue: login required.',
      'A password prompt blocks this task.',
      '無法繼續：需要登入。',
    ]) {
      adapter = _Adapter([
        [TextDelta(note), const Done('end_turn')],
      ]);
      build();
      final result = await run();
      final receipt = jsonDecode(result.content) as Map;
      expect(receipt['status'], 'blocked', reason: note);
      expect(result.isError, true);
      expect(adapter.requests, hasLength(1));
      expect(screen.actions, isEmpty);
    }
  });
  test('navigation handoffs recover even without exact final labels', () async {
    for (final note in [
      'Please return to the home page and say continue.',
      'I need you to dismiss the progress banner or confirm I may use the back gesture.',
      '請先回到首頁，再跟我說「繼續」。',
      "I haven't reached the free wheel yet. Next I'd tap the back arrow. No spin has been performed.",
    ]) {
      adapter = _Adapter([
        [TextDelta(note), const Done('end_turn')],
        call('tap', {'title': 'Recover navigation', 'id': 1}),
        [const TextDelta('Done is visible.'), const Done('end_turn')],
      ]);
      build();
      final receipt = jsonDecode((await run(expected: [])).content) as Map;
      expect(receipt['status'], 'reported_complete', reason: note);
      expect(receipt['recovery_attempts'], 1);
      expect(adapter.requests, hasLength(3));
      final recovery = adapter.requests[1].messages.last.content;
      expect(recovery.whereType<ImageBlock>(), hasLength(1));
      expect(
        recovery.whereType<TextBlock>().first.text,
        contains('already authorized'),
      );
      expect(
        adapter.requests.first.systemPrompt,
        contains('Full permissions enabled'),
      );
      screen.show('start');
      screen.actions.clear();
    }
  });
  test('an uncertain spin outcome is not retried as navigation', () async {
    adapter = _Adapter([
      [
        const TextDelta(
          'Cannot confirm the spin outcome. Please return to the home page and say continue.',
        ),
        const Done('end_turn'),
      ],
    ]);
    build();
    final receipt = jsonDecode((await run(expected: [])).content) as Map;
    expect(receipt['status'], 'incomplete');
    expect(receipt['reason'], 'worker_mutation_outcome_uncertain');
    expect(receipt['recovery_attempts'], 0);
    expect(adapter.requests, hasLength(1));
    expect(screen.actions, isEmpty);
  });
  test(
    'a workflow image reaches the worker without another read round',
    () async {
      adapter = _Adapter([
        [const TextDelta('Start is visible.'), const Done('end_turn')],
      ]);
      build();
      final result = await run(
        expected: [],
        workflow: [
          {
            'tool': 'open_app',
            'package': 'com.example.fixture',
            'screenshot': true,
          },
        ],
      );
      expect(adapter.requests, hasLength(1));
      expect(
        adapter.requests.single.messages.single.content.whereType<ImageBlock>(),
        hasLength(1),
      );
      expect((jsonDecode(result.content) as Map)['steps'], 2);
    },
  );
  test('final native verification does not request automatic images', () async {
    final sparse = _SparseScreen(screen.views);
    screen = sparse;
    adapter = _Adapter([
      call('tap', {'title': 'Start', 'id': 1}),
    ]);
    build();
    final receipt = tryDecodeObject((await run()).content)!;
    expect(receipt['verified'], true);
    expect(sparse.imageAccess, [true, true, false]);
    expect(adapter.requests, hasLength(1));
    expect(screen.actions, hasLength(1));
  });
  test(
    'a partial launch plan never polls for criteria before worker actions',
    () async {
      build();
      final result = await run(
        workflow: [
          {'tool': 'open_app', 'package': 'com.example.fixture'},
        ],
      );
      expect(tryDecodeObject(result.content)!['status'], 'verified');
      final records = await AuditRepository(database).list();
      expect(records.where((r) => r.toolName == 'read_screen'), hasLength(1));
      expect(adapter.requests, hasLength(1));
    },
  );
  test('unfinished recovery is bounded to one attempt', () async {
    adapter = _Adapter([
      [const TextDelta('Not completed: stuck'), const Done('end_turn')],
      [const TextDelta('Not completed: stuck'), const Done('end_turn')],
    ]);
    build();
    final result = await run();
    final receipt = jsonDecode(result.content) as Map;
    expect(result.isError, true);
    expect(receipt['status'], 'incomplete');
    expect(receipt['reason'], 'worker_reported_incomplete');
    expect(adapter.requests, hasLength(2));
    expect(screen.actions, isEmpty);
  });
  test(
    'verification matches a value separately from its accessibility label',
    () async {
      screen.views['done'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(
          box([
            FakeNode(
              'android.widget.TextView',
              text: '15',
              description: 'Current expression',
            ),
          ]),
        ),
      ]);
      build();
      final receipt =
          jsonDecode((await run(expected: const ['15'])).content) as Map;
      expect(receipt['status'], 'verified');
      expect(receipt['matched_text'], ['15']);
    },
  );
  test(
    'local workflow navigates from fresh labels without model calls',
    () async {
      build();
      final receipt =
          jsonDecode(
                (await run(
                  workflow: [
                    {
                      'tool': 'tap',
                      'label': 'Start',
                      'expect_app': 'com.example.fixture',
                      'expect_text': 'Done',
                    },
                  ],
                )).content,
              )
              as Map<String, Object?>;
      expect(receipt['status'], 'verified');
      expect(receipt['model_rounds'], 0);
      expect(adapter.requests, isEmpty);
      expect(screen.actions, hasLength(1));
    },
  );
  test(
    'nested back navigation executes locally with fresh ids and exact destination',
    () async {
      screen.views['start'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(
          box([label('Detail'), icon(viewId: 'BackButton', opens: 'middle')]),
        ),
      ]);
      screen.views['middle'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(
          box([label('Category'), icon(viewId: 'BackButton', opens: 'root')]),
        ),
      ]);
      screen.views['root'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(box([button('Start', opens: 'done')])),
      ]);
      build();
      final receipt = tryDecodeObject(
        (await run(
          workflow: [
            {
              'tool': 'back',
              'expect_app': 'com.example.fixture',
              'until_label': 'Start',
              'max_back': 4,
            },
            {
              'tool': 'tap',
              'label': 'Start',
              'expect_app': 'com.example.fixture',
            },
          ],
        )).content,
      )!;
      expect(receipt['status'], 'verified');
      expect(receipt['model_rounds'], 0);
      expect(screen.actions, hasLength(3));
      expect(
        (await AuditRepository(
          database,
        ).list()).where((r) => r.toolName == 'tap'),
        hasLength(3),
      );
    },
  );
  for (final workflow in [false, true]) {
    test(
      'busy UI stops ${workflow ? 'workflow' : 'worker'} without another call',
      () async {
        final busy = _BusyScreen(screen.views);
        screen = busy;
        adapter = _Adapter([
          [
            ...call('tap', {
              'title': 'Start',
              'id': 1,
            }).where((e) => e is! Done),
            const ToolCallStart('second', 'read_screen'),
            const ToolCallArgsDelta('second', '{"title":"Read again"}'),
            const ToolCallEnd('second'),
            const Done('tool_use'),
          ],
        ]);
        build();
        final receipt = tryDecodeObject(
          (await run(
            workflow: workflow
                ? [
                    {
                      'tool': 'tap',
                      'label': 'Start',
                      'expect_app': 'com.example.fixture',
                    },
                  ]
                : null,
          )).content,
        )!;
        expect(receipt['status'], 'blocked');
        expect(receipt['reason'], 'device_ui_busy');
        expect(receipt['recovery_attempts'], 0);
        expect(busy.reads, 1);
        expect(busy.actions, hasLength(1));
        expect(adapter.requests, hasLength(workflow ? 0 : 1));
      },
    );
  }
  test(
    'busy initial observation never calls the worker or a final read',
    () async {
      final busy = _BusyScreen(screen.views)..busyInitially = true;
      screen = busy;
      build();
      final receipt = tryDecodeObject((await run()).content)!;
      expect(receipt['status'], 'blocked');
      expect(receipt['reason'], 'device_ui_busy');
      expect(busy.reads, 1);
      expect(busy.actions, isEmpty);
      expect(adapter.requests, isEmpty);
    },
  );
  test(
    'failed selector returns a fresh image without retrying the action',
    () async {
      adapter = _Adapter([
        call('tap', {'title': 'Unknown target', 'id': 999}),
        call('tap', {'title': 'Start', 'id': 1}),
      ]);
      build();
      final receipt = tryDecodeObject((await run()).content)!;
      expect(receipt['status'], 'verified');
      expect(receipt['observation_recoveries'], 1);
      expect(adapter.requests, hasLength(2));
      expect(screen.actions, hasLength(1));
      final fresh = adapter.requests[1].messages.last.content;
      expect(fresh.whereType<ImageBlock>(), hasLength(1));
      expect(fresh.whereType<TextBlock>().first.text, contains('not retried'));
      expect(fresh.whereType<TextBlock>().last.text, contains('Start'));
    },
  );
  test('ambiguous workflow returns a fresh image for replanning', () async {
    adapter = _Adapter([
      call('screen_workflow', {
        'title': 'Find route',
        'steps': [
          {
            'tool': 'tap',
            'label': 'Missing',
            'expect_app': 'com.example.fixture',
          },
        ],
      }),
      call('tap', {'title': 'Start', 'id': 1}),
    ]);
    build();
    final receipt = tryDecodeObject((await run()).content)!;
    expect(receipt['status'], 'verified');
    expect(receipt['observation_recoveries'], 1);
    expect(adapter.requests, hasLength(2));
    expect(screen.actions, hasLength(1));
    expect(
      adapter.requests[1].messages.last.content.whereType<ImageBlock>(),
      hasLength(1),
    );
  });
  test(
    'back workflow never repeats a tap when its page remains unchanged',
    () async {
      screen.views['start'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(box([icon(viewId: 'BackButton')])),
      ]);
      adapter = _Adapter([
        [
          const TextDelta('Navigation blocked by unchanged page.'),
          const Done('end_turn'),
        ],
      ]);
      build();
      await run(
        expected: [],
        workflow: [
          {'tool': 'back', 'expect_app': 'com.example.fixture', 'max_back': 4},
        ],
      );
      expect(screen.actions, hasLength(1));
      final records = await AuditRepository(database).list();
      expect(
        records
            .firstWhere((r) => r.toolName == 'screen_workflow')
            .resultSummary,
        contains('workflow_back_unchanged'),
      );
    },
  );
  test(
    'nested row and button are one selector; sibling duplicates remain ambiguous',
    () async {
      screen.views['start'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(
          box([
            row([button('Start', opens: 'done')], opens: 'done'),
          ]),
        ),
      ]);
      build();
      final result = await run(
        workflow: [
          {
            'tool': 'tap',
            'label': 'Start',
            'expect_app': 'com.example.fixture',
          },
        ],
      );
      expect(tryDecodeObject(result.content)!['model_rounds'], 0);
      expect(screen.actions, hasLength(1));
    },
  );
  test(
    'workflow resolves an app name locally before worker planning',
    () async {
      build();
      final result = await run(
        expected: [],
        workflow: [
          {'tool': 'open_app', 'name': 'Fixture'},
        ],
      );
      expect(tryDecodeObject(result.content)!['workflow_used'], true);
      final records = await AuditRepository(database).list();
      final launch = records.where((r) => r.toolName == 'open_app').single;
      expect(tryDecodeObject(launch.arguments)!['name'], 'Fixture');
      expect(tryDecodeObject(launch.arguments)!.containsKey('package'), false);
    },
  );
  test(
    'native image ID workflow finishes without a worker model call',
    () async {
      screen.views['start'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(
          box([
            FakeNode(
              'Image',
              viewId: 'ic_search_cart',
              opens: 'done',
              bounds: const ScreenBounds(360, 70, 384, 94),
            ),
          ]),
        ),
      ]);
      build();
      final receipt =
          jsonDecode(
                (await run(
                  workflow: [
                    {
                      'tool': 'tap',
                      'view_id': 'ic_search_cart',
                      'expect_app': 'com.example.fixture',
                      'expect_text': 'Done',
                    },
                  ],
                )).content,
              )
              as Map;
      expect(receipt['status'], 'verified');
      expect(receipt['model_rounds'], 0);
      expect(adapter.requests, isEmpty);
      expect(screen.actions, hasLength(1));
    },
  );
  test(
    'worker workflow can finish with native proof without a second model turn',
    () async {
      adapter = _Adapter([
        call('screen_workflow', {
          'title': 'Complete navigation',
          'steps': [
            {
              'tool': 'tap',
              'label': 'Start',
              'expect_app': 'com.example.fixture',
              'expect_text': 'Done',
            },
          ],
        }),
      ]);
      build();
      final receipt = jsonDecode((await run()).content) as Map;
      expect(receipt['verified'], true);
      expect(receipt['workflow_used'], true);
      expect(receipt['model_rounds'], 1);
      expect(adapter.requests, hasLength(1));
    },
  );
  test(
    'workflow selects the control over the same page title and uses fresh ids between steps',
    () async {
      screen.views['start'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(box([label('Start'), button('Start', opens: 'middle')])),
      ]);
      screen.views['middle'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(box([button('Finish', opens: 'done')])),
      ]);
      build();
      final receipt =
          jsonDecode(
                (await run(
                  workflow: [
                    {
                      'tool': 'tap',
                      'label': 'Start',
                      'expect_app': 'com.example.fixture',
                    },
                    {
                      'tool': 'tap',
                      'label': 'Finish',
                      'expect_app': 'com.example.fixture',
                    },
                  ],
                )).content,
              )
              as Map;
      expect(receipt['verified'], true);
      expect(receipt['model_rounds'], 0);
      expect(screen.actions, hasLength(2));
      expect(adapter.requests, isEmpty);
    },
  );
  test(
    'a workflow mismatch hands off its current screen without replaying steps',
    () async {
      adapter = _Adapter([
        [const TextDelta('Done is visible'), const Done('end_turn')],
      ]);
      build();
      final receipt =
          jsonDecode(
                (await run(
                  workflow: [
                    {
                      'tool': 'tap',
                      'label': 'Start',
                      'expect_app': 'com.example.fixture',
                    },
                    {
                      'tool': 'tap',
                      'label': 'No longer here',
                      'expect_app': 'com.example.fixture',
                    },
                  ],
                )).content,
              )
              as Map<String, Object?>;
      expect(receipt['status'], 'verified');
      expect(adapter.requests, hasLength(1));
      expect(screen.actions, hasLength(1));
      expect(
        adapter.requests.single.messages.single.text,
        contains('completed_steps'),
      );
    },
  );
  test(
    'search labels exclude fields and a bare echo and still need review',
    () async {
      screen.views['done'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(
          box([
            field(text: 'ESP32-S3 private query'),
            label('ESP32-S3'),
            label('ESP32-S3 DevKit board'),
          ]),
        ),
      ]);
      adapter = _Adapter([
        call('tap', {'title': 'Start', 'id': 1}),
        [const TextDelta('Results observed'), const Done('end_turn')],
      ]);
      build();
      final receipt =
          jsonDecode((await run(expected: [], query: 'ESP32S3')).content)
              as Map<String, Object?>;
      expect(receipt['matching_results'], ['ESP32-S3 DevKit board']);
      expect(receipt['semantic_review_needed'], true);
    },
  );
  test(
    'product evidence requires a title and price in the same visible card',
    () async {
      screen.views['done'] = FakeView('com.example.fixture', 'Fixture', [
        FakeWindow(
          box([
            list([
              row([label('ESP32-S3 DevKit board'), label('NT\$95')]),
              row([label('ESP32-S3 suggestions')]),
              row([label('Other advertisement'), label('\$1')]),
            ]),
          ]),
        ),
      ]);
      build();
      final receipt =
          jsonDecode(
                (await run(
                  expected: [],
                  query: 'ESP32S3',
                  resultKind: 'product',
                )).content,
              )
              as Map<String, Object?>;
      expect(receipt['status'], 'verified');
      expect(receipt['result_items'], [
        {'title': 'ESP32-S3 DevKit board', 'price': 'NT\$95'},
      ]);
      expect(receipt['semantic_review_needed'], false);
      expect(adapter.requests, hasLength(1));
    },
  );
  test(
    'a one-read budget never adds an unbudgeted verification read',
    () async {
      limit = 1;
      build();
      final receipt = jsonDecode((await run()).content) as Map<String, Object?>;
      expect(receipt['steps'], 1);
      expect(receipt['status'], 'incomplete');
      expect(adapter.requests, isEmpty);
    },
  );
  test('a comparison cannot finish on only one matching product', () async {
    screen.views['done'] = FakeView('com.example.fixture', 'Fixture', [
      FakeWindow(
        box([
          list([
            row([label('foldable stand A'), label(r'NT$95')]),
          ]),
        ]),
      ),
    ]);
    adapter = _Adapter([
      call('tap', {'title': 'Start', 'id': 1}),
      [
        const TextDelta('Not completed: only one option visible.'),
        const Done('end_turn'),
      ],
      [
        const TextDelta('Not completed: still only one option.'),
        const Done('end_turn'),
      ],
    ]);
    build();
    final receipt =
        jsonDecode(
              (await run(
                expected: [],
                query: 'stand',
                resultKind: 'product',
                minResults: 2,
              )).content,
            )
            as Map;
    expect(receipt['verified'], false);
    expect(receipt['status'], 'incomplete');
    expect(receipt['result_items'], hasLength(1));
    expect(adapter.requests, hasLength(3));
  });
  test(
    'denied child action stops with no later action or false success',
    () async {
      gate.policy = const PermissionPolicy(
        fullPermissions: true,
        overrides: {'tap': ToolPermission.deny},
      );
      build();
      final result = await run();
      expect(
        (jsonDecode(result.content) as Map<String, Object?>)['status'],
        'blocked',
      );
      expect(screen.actions, isEmpty);
      expect(adapter.requests, hasLength(1));
    },
  );
  test(
    'an own-app initial read does not prevent launching the requested app',
    () async {
      screen.show('own');
      adapter = _Adapter([
        call('open_app', {
          'title': 'Open fixture',
          'package': 'com.example.fixture',
        }),
        call('tap', {'title': 'Start', 'id': 1}),
      ]);
      build();
      final receipt = jsonDecode((await run()).content) as Map;
      expect(receipt['status'], 'verified');
      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests.first.messages.single.text,
        isNot(contains('Private main chat')),
      );
    },
  );
  test(
    'step exhaustion cannot promote a partial state to a completed task',
    () async {
      limit = 3;
      adapter = _Adapter([
        call('read_screen', {'title': 'Read'}),
      ]);
      build();
      final receipt =
          jsonDecode(
                (await run(
                  expected: const [],
                  app: 'com.example.fixture',
                )).content,
              )
              as Map;
      expect(receipt['status'], 'incomplete');
      expect(receipt['reason'], 'worker_step_limit');
      expect(receipt['semantic_review_needed'], true);
      expect(receipt['verified'], false);
    },
  );
  test('Stop cancels before any worker request', () async {
    build();
    token.cancel();
    final result = await run(cancel: token);
    expect(result.isError, true);
    expect(adapter.requests, isEmpty);
    expect(screen.actions, isEmpty);
  });
}
