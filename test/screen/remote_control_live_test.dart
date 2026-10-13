// Opt-in live device and paid provider verification. Credentials stay ignored.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/files/workspace.dart';
import 'package:tako/core/permissions/permission_gate.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/core/screen/remote_control_agent.dart';
import 'package:tako/core/screen/remote_screen.dart';
import 'package:tako/core/tools/device_tools.dart';
import 'package:tako/core/tools/tool.dart';
import 'package:tako/core/tools/tool_executor.dart';
import 'package:tako/core/tools/tool_registry.dart';
import 'package:tako/data/audit_repository.dart';
import 'package:tako/data/database.dart';
import 'package:tako/platform/device_tools_capability.dart';
import 'package:tako/platform/ios/ictrl_client.dart';
import 'package:tako/platform/ios/ictrl_device_tools.dart';
import 'package:tako/platform/ios/ictrl_screen.dart';

class _Workspace implements WorkspaceCapability {
  @override
  bool get isAvailable => true;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No persistent worker images');
}

class _MeasuredClient extends IctrlClient {
  _MeasuredClient({
    required super.readSecret,
    required super.writeSecret,
    required super.endpoint,
  });
  final timings = <Map<String, Object?>>[];
  @override
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> params = const {},
    CancelToken? cancel,
  ]) async {
    final timer = Stopwatch()..start();
    try {
      return await super.call(method, params, cancel);
    } finally {
      timings.add({'method': method, 'elapsed_ms': timer.elapsedMilliseconds});
    }
  }
}

class _ObservedAdapter implements ProviderAdapter {
  _ObservedAdapter(this.inner, this.prefix, this.secret);
  final ProviderAdapter inner;
  final String prefix;
  final String secret;
  @override
  Future<List<ModelInfo>> listModels({CancelToken? cancel}) =>
      inner.listModels(cancel: cancel);
  @override
  Stream<ProviderEvent> send(
    ChatRequest request, {
    required CancelToken cancel,
  }) async* {
    await for (final event in inner.send(request, cancel: cancel)) {
      if (event is ProviderError) {
        File(
          '.build/ictrl-smoke/$prefix-provider-error.json',
        ).writeAsStringSync(
          jsonEncode({
            'code': event.code,
            'status': event.statusCode,
            'message': event.message.replaceAll(secret, '[REDACTED]'),
          }),
        );
      }
      yield event;
    }
  }
}

void main() {
  final search = Platform.environment['TAKO_ICTRL_WORKER_SHOPEE'] == '1';
  final workflow = Platform.environment['TAKO_ICTRL_WORKER_WORKFLOW'] == '1';
  final cart = Platform.environment['TAKO_ICTRL_WORKER_CART'] == '1';
  final resume = Platform.environment['TAKO_ICTRL_WORKER_RESUME'] == '1';
  final customTask = Platform.environment['TAKO_ICTRL_WORKER_TASK'];
  final customApp = Platform.environment['TAKO_ICTRL_WORKER_APP'];
  final customText = Platform.environment['TAKO_ICTRL_WORKER_TEXT'];
  final customQuery = Platform.environment['TAKO_ICTRL_WORKER_QUERY'];
  final customCriteria = Platform.environment['TAKO_ICTRL_WORKER_CRITERIA'];
  final prefix = Platform.environment['TAKO_ICTRL_WORKER_PREFIX'];
  final customWorkflow = Platform.environment['TAKO_ICTRL_WORKER_PLAN'];
  final effort = Platform.environment['TAKO_ICTRL_WORKER_EFFORT'] ?? 'xhigh';
  final model =
      Platform.environment['TAKO_ICTRL_WORKER_MODEL'] ?? 'claude-haiku-5-5';
  final api = model.startsWith('gpt-') ? ApiType.responses : ApiType.messages;
  test(
    '$model $effort delegates ${customApp != null
        ? 'cross-app task'
        : search
        ? 'Shopee search'
        : 'Calculator'} without main screen history',
    () async {
      final endpoint =
          Platform.environment['TAKO_ICTRL_ENDPOINT'] ??
          'http://100.77.80.7:8200';
      final stored =
          jsonDecode(File('.build/ictrl-pairing.json').readAsStringSync())
              as Map;
      final key =
          (stored[Uri.parse(endpoint).authority] as Map)['key'] as String;
      final secrets = <String, String>{'ictrl.key.$endpoint': key};
      final client = _MeasuredClient(
        endpoint: endpoint,
        readSecret: (k) async => secrets[k],
        writeSecret: (k, v) async {
          if (v == null) {
            secrets.remove(k);
          } else {
            secrets[k] = v;
          }
        },
      );
      final screen = IctrlScreen(client: client);
      final database = AppDatabase(NativeDatabase.memory());
      final env = <String, String>{};
      for (final line in File('cpa.env').readAsLinesSync()) {
        final split = line.indexOf('=');
        if (split > 0) {
          env[line.substring(0, split).trim()] = line
              .substring(split + 1)
              .trim()
              .replaceAll(RegExp(r'''^["']|["']$'''), '');
        }
      }
      final config = withWorkerReasoning(
        ProviderConfig(
          id: 'worker-live',
          displayName: 'Remote test',
          apiType: api,
          baseUrl: env['api_endpoint']!,
          model: model,
          reasoningMode: api == ApiType.messages
              ? ReasoningMode.adaptive
              : ReasoningMode.enabled,
          reasoningEffort: 'xhigh',
          maxOutputTokens: 8192,
          capabilities: const ProviderCapabilities(
            tools: true,
            vision: true,
            reasoning: true,
          ),
        ),
        effort,
      );
      final gate = PermissionGate(
        policy: const PermissionPolicy(
          fullPermissions: true,
          skipHighRiskConfirmations: true,
        ),
      );
      final audit = AuditRepository(database);
      final agent = RemoteControlAgent(
        screen: screen,
        workspace: _Workspace(),
        deviceTools: (observer) => createDeviceTools(
          IctrlDeviceTools(
            screen: screen,
            native: const UnavailableDeviceTools(),
          ),
          observer: observer,
        ),
        permissions: gate,
        audit: audit,
        backend: () async => (
          config: config,
          adapter: _ObservedAdapter(
            ProviderAdapter.create(config, apiKey: env['api_key']),
            prefix ?? 'haiku-worker',
            env['api_key']!,
          ),
        ),
        available: () => true,
        screenshots: () => true,
        disabledTools: () => {},
        stepLimit: () => cart ? 75 : 35,
      );
      final executor = ToolExecutor(
        registry: ToolRegistry(agent.tools),
        permissions: gate,
        audit: audit,
      );
      final metrics = <Map<String, Object?>>[];
      try {
        await screen.connect();
        expect(screen.status, RemoteScreenStatus.ready);
        final resolver = IctrlDeviceTools(
          screen: screen,
          native: const UnavailableDeviceTools(),
        );
        for (final app in [
          ('Shopee|蝦皮', 'com.beeasy.shopee.tw'),
          ('Settings|設定', 'com.apple.Preferences'),
        ]) {
          final found = await resolver.invoke('resolve_app', {
            'name': app.$1,
          }, cancel: CancelToken());
          expect(
            found['apps'],
            contains(
              equals({
                'name': app.$2 == 'com.apple.Preferences' ? '設定' : '蝦皮購物',
                'package': app.$2,
                'installed': true,
              }),
            ),
          );
        }
        for (final problem
            in customApp != null
                ? [('Cross-app worker smoke', 'custom')]
                : search
                ? [('Find ESP32-S3 on Shopee', 'ESP32S3')]
                : [('7 + 8', '15'), ('123 + 456', '579')]) {
          if (!resume) {
            await screen.rpc('launch_app', {
              'bundle_id': 'com.apple.calculator',
              'settle': false,
            });
          }
          final result = (await executor.execute(
            ToolCallBlock(
              id: 'delegate-${problem.$2}',
              name: 'remote_control',
              arguments: jsonEncode({
                'title': search ? problem.$1 : 'Calculate ${problem.$1}',
                'task':
                    customTask ??
                    (cart
                        ? 'Find the cheapest eligible ESP32-S3 development board in Shopee and add quantity 1 to the cart; verify it in the cart, then stop. Preserve existing cart items. Never buy/pay/checkout, message sellers, change settings, claim rewards or delete existing items. Current search ESP32-S3 was already sorted with 按價格排序：低到高. A prior comparison exhausted its budget without adding: it inspected the lowest advertised \$61 N8R2 board, a mixed C3/S3 SuperMini listing, \$82 N16R8 welded-pin listing, and \$90 N16R8 board. Their advertised minimum may be accessories/other variants; inspect the actual selected S3 variant price. Resume from the supplied screen; do not restart search or duplicate past reads. Compare only enough lowest-price candidates to pick the lowest confirmed S3 board variant; do not continue into more expensive pages once established. Report exact title/variant/price and why lower listings were excluded. Focus on completing add-to-cart and cart proof. Use exact labels and returned observations. Scroll indicators are not close buttons. If blocked by login/CAPTCHA/password, stop.'
                        : search
                        ? 'Open Shopee (com.beeasy.shopee.tw) and search for ESP32-S3 development boards. Find matching products on the actual search-results page and stop. Only search and inspect results. Do not buy, add to cart, share, message, delete data, change settings or claim rewards. If a login or CAPTCHA blocks searching, stop and report it. Use a real search field, type the term, submit, then inspect matching product titles; a search-history suggestion is not a product result.'
                        : 'Use Calculator to calculate ${problem.$1}. Clear the previous expression, enter all keys, press equals, verify and stop. Only operate Calculator. Labels are Traditional Chinese; 加 is plus, 等於 equals, 全部清除 all clear. Use screen_sequence for the full stable key sequence.'),
                'success_criteria':
                    customCriteria ??
                    (customApp != null
                        ? 'Requested app and expected text visible; report outcome and stop.'
                        : cart
                        ? 'Cart contains quantity one of the cheapest eligible ESP32-S3 development board, with the variant and price checked against ascending search results. Report the product title, variant, price, and compact cart evidence.'
                        : search
                        ? 'Shopee search results show ESP32-S3 development-board product titles'
                        : 'Calculator result must show exactly ${problem.$2}'),
                if (customText != null) 'expected_text': [customText],
                'result_contains': ?customQuery,
                if (cart && customApp == null) 'expected_text': ['購物車'],
                if (search && customApp == null)
                  'result_contains': 'ESP32S3'
                else if (customApp == null)
                  'expected_text': [problem.$2],
                'expected_app':
                    customApp ??
                    (search ? 'com.beeasy.shopee.tw' : 'com.apple.calculator'),
                if (search && !cart) 'result_kind': 'product',
                if (customWorkflow != null)
                  'workflow': jsonDecode(customWorkflow),
                if (search && workflow)
                  'workflow': [
                    {
                      'tool': 'open_url',
                      'url': 'https://shopee.tw/search?keyword=ESP32-S3',
                      'expect_app': 'com.beeasy.shopee.tw',
                    },
                  ],
              }),
            ),
            ToolContext(
              conversationId: 'worker-smoke',
              messageId: 'main-${problem.$2}',
              cancel: CancelToken(),
            ),
          )).result;
          final receipt = jsonDecode(result.content) as Map<String, Object?>;
          metrics.add({
            'problem': problem.$1,
            'worker_model': model,
            'worker_effort': effort,
            ...receipt,
            'main_result_characters': result.content.length,
          });
          File(
            '.build/ictrl-smoke/${prefix ?? (cart
                    ? 'haiku-worker-cart'
                    : search
                    ? workflow
                          ? 'haiku-workflow-shopee'
                          : 'haiku-worker-shopee'
                    : 'haiku-worker')}-metrics.json',
          ).writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(metrics),
          );
          expect(result.attachments, isEmpty);
          final records = await audit.list(limit: 1000);
          File(
            '.build/ictrl-smoke/${prefix ?? (cart ? 'haiku-worker-cart' : 'haiku-worker')}-audit.json',
          ).writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert([
              for (final record in records.reversed)
                {
                  'tool': record.toolName,
                  'args': record.arguments,
                  'result': record.resultSummary,
                  'elapsed_ms': record.finishedAt
                      ?.difference(record.startedAt)
                      .inMilliseconds,
                  'error': record.isError,
                },
            ]),
          );
          if (!cart && customText != null || !cart && customApp == null) {
            expect(receipt['status'], 'verified');
            expect(receipt['verified'], true);
          }
          debugPrint(
            '${receipt['status']}: ${problem.$1}: ${receipt['elapsed_ms']} ms, ${receipt['model_rounds']} worker rounds, ${result.content.length} main-result characters',
          );
        }
      } finally {
        File(
          '.build/ictrl-smoke/${prefix ?? 'worker'}-rpc-latency.json',
        ).writeAsStringSync(jsonEncode(client.timings));
        screen.dispose();
        await database.close();
      }
    },
    skip: Platform.environment['TAKO_ICTRL_WORKER_LIVE'] != '1',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
