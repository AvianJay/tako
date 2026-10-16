import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/app/app_controller.dart';
import 'package:tako/core/permissions/permission_gate.dart';
import 'package:tako/core/providers/cancel_token.dart';
import 'package:tako/core/tools/tool.dart';
import 'package:tako/data/database.dart';

import '../app/app_controller_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late AppController ui, worker;
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final services = fixtures.FakeServices();
    AppController host() => AppController(
      database: database,
      services: services,
      promptTemplate: 'Fixture',
      bindControls: false,
    );
    ui = host();
    worker =
        host(); // Independent policy cache, as in a separate Flutter engine.
    await ui.initialize(automationWorker: true);
    await worker.initialize(automationWorker: true);
  });
  tearDown(() async {
    worker.dispose();
    ui.dispose();
    await database.close();
  });
  Future<PermissionDecision> authorize(String tool) =>
      worker.permissionGate.authorize(
        toolName: tool,
        args: const {},
        risk: RiskLevel.sensitive,
        context: ToolContext(
          conversationId: 'automation',
          messageId: 'call',
          cancel: CancelToken(),
        ),
      );
  Future<void> pending() async {
    for (
      var i = 0;
      i < 100 && worker.permissionGate.pendingApproval == null;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(worker.permissionGate.pendingApproval, isNotNull);
  }

  test(
    'always allow merges one rule without restoring revoked permissions',
    () async {
      await ui.savePermissionPolicy(
        const PermissionPolicy(
          fullPermissions: true,
          overrides: {'fixture': ToolPermission.ask},
        ),
      );
      await worker.permissionGate.refreshPolicy();
      final decision = authorize('fixture');
      await pending();
      await ui.savePermissionPolicy(
        const PermissionPolicy(
          overrides: {
            'fixture': ToolPermission.ask,
            'run_shell': ToolPermission.deny,
            'new_allow': ToolPermission.allow,
          },
        ),
      );
      worker.permissionGate.decide(PermissionChoice.alwaysAllow);
      expect((await decision).allowed, isTrue);
      final saved = PermissionPolicy.decode(
        await ui.settings.getString(PermissionPolicy.settingsKey),
      );
      expect(saved.fullPermissions, isFalse);
      expect(saved.overrides, {
        'fixture': ToolPermission.allow,
        'run_shell': ToolPermission.deny,
        'new_allow': ToolPermission.allow,
      });
    },
  );

  test('a new denial wins over an approval already on screen', () async {
    final decision = authorize('fixture');
    await pending();
    await ui.savePermissionPolicy(
      const PermissionPolicy(overrides: {'fixture': ToolPermission.deny}),
    );
    worker.permissionGate.decide(PermissionChoice.alwaysAllow);
    expect((await decision).reason, 'denied_by_policy');
    expect((await authorize('fixture')).allowed, isFalse);
  });

  test(
    'saving an unrelated UI preference preserves a new automation allowance',
    () async {
      final decision = authorize('fixture');
      await pending();
      worker.permissionGate.decide(PermissionChoice.alwaysAllow);
      expect((await decision).allowed, isTrue);
      await ui.savePermissionPolicy(
        ui.permissionGate.policy.copyWith(skipHighRiskConfirmations: true),
      );
      final saved = PermissionPolicy.decode(
        await ui.settings.getString(PermissionPolicy.settingsKey),
      );
      expect(saved.overrides['fixture'], ToolPermission.allow);
      expect(saved.skipHighRiskConfirmations, isTrue);
    },
  );

  test(
    'foreground and automation forks share current policy in one engine',
    () async {
      final fork = ui.forkForAutomation();
      addTearDown(fork.dispose);
      await fork.initialize(automationWorker: true);
      await ui.savePermissionPolicy(
        const PermissionPolicy(overrides: {'run_shell': ToolPermission.deny}),
      );
      expect(
        fork.permissionGate.policy.overrides['run_shell'],
        ToolPermission.deny,
      );
    },
  );
}
