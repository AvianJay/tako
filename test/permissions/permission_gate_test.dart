import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/permissions/permission_gate.dart';
import 'package:tako/core/providers/cancel_token.dart';
import 'package:tako/core/tools/tool.dart';

ToolContext context([String conversation = 'chat', CancelToken? cancel]) =>
    ToolContext(
      conversationId: conversation,
      messageId: 'message',
      cancel: cancel ?? CancelToken(),
    );

Future<PermissionDecision> authorize(
  PermissionGate gate,
  RiskLevel risk, {
  ToolContext? ctx,
  String name = 'tool',
}) => gate.authorize(
  toolName: name,
  args: {},
  risk: risk,
  context: ctx ?? context(),
);

void main() {
  test('safe allows without an approval', () async {
    final gate = PermissionGate();
    expect((await authorize(gate, RiskLevel.safe)).allowed, isTrue);
    expect(gate.pendingApproval, isNull);
  });

  test('sensitive once asks again, chat grant stays in one chat', () async {
    final gate = PermissionGate();
    var future = authorize(gate, RiskLevel.sensitive);
    expect(gate.pendingApproval?.toolName, 'tool');
    gate.decide(PermissionChoice.allowOnce);
    expect((await future).allowed, isTrue);
    future = authorize(gate, RiskLevel.sensitive);
    expect(gate.pendingApproval, isNotNull);
    gate.decide(PermissionChoice.allowInChat);
    expect((await future).allowed, isTrue);
    expect(
      (await authorize(gate, RiskLevel.sensitive)).reason,
      'allowed_in_chat',
    );
    future = authorize(gate, RiskLevel.sensitive, ctx: context('other'));
    expect(gate.pendingApproval?.conversationId, 'other');
    gate.decide(PermissionChoice.deny);
    expect((await future).allowed, isFalse);
    gate.forgetConversation('chat');
    future = authorize(gate, RiskLevel.sensitive);
    expect(gate.pendingApproval, isNotNull);
    gate.decide(PermissionChoice.deny);
    await future;
  });

  test('action asks once per tool per chat', () async {
    final gate = PermissionGate();
    var future = authorize(gate, RiskLevel.action);
    expect(gate.pendingApproval?.choices, [
      PermissionChoice.allowInChat,
      PermissionChoice.alwaysAllow,
      PermissionChoice.deny,
    ]);
    gate.decide(PermissionChoice.allowInChat);
    expect((await future).allowed, isTrue);
    expect((await authorize(gate, RiskLevel.action)).reason, 'allowed_in_chat');
    future = authorize(gate, RiskLevel.action, name: 'other_tool');
    expect(gate.pendingApproval, isNotNull);
    gate.decide(PermissionChoice.deny);
    await future;
  });

  test(
    'forced ask exposes only effective choices and always allowance resets it',
    () async {
      final gate = PermissionGate(
        policy: const PermissionPolicy(overrides: {'tool': ToolPermission.ask}),
      );
      var future = authorize(gate, RiskLevel.action);
      expect(gate.pendingApproval?.choices, [
        PermissionChoice.allowOnce,
        PermissionChoice.alwaysAllow,
        PermissionChoice.deny,
      ]);
      gate.decide(PermissionChoice.allowOnce);
      expect((await future).allowed, isTrue);
      future = authorize(gate, RiskLevel.action);
      expect(gate.pendingApproval, isNotNull);
      gate.decide(PermissionChoice.alwaysAllow);
      expect((await future).allowed, isTrue);
      expect(gate.policy.overrides['tool'], ToolPermission.allow);
      expect((await authorize(gate, RiskLevel.action)).allowed, isTrue);
      expect(gate.pendingApproval, isNull);
    },
  );

  test('allowsWithoutAsking follows authorize and never asks', () async {
    final gate = PermissionGate();
    bool allows(RiskLevel risk, {String name = 'tool', String chat = 'chat'}) =>
        gate.allowsWithoutAsking(
          toolName: name,
          risk: risk,
          conversationId: chat,
        );
    expect(allows(RiskLevel.safe), isTrue);
    expect(allows(RiskLevel.sensitive), isFalse);
    // Allowing one call is not an approval for the next.
    var future = authorize(gate, RiskLevel.sensitive);
    gate.decide(PermissionChoice.allowOnce);
    await future;
    expect(allows(RiskLevel.sensitive), isFalse);
    future = authorize(gate, RiskLevel.sensitive);
    gate.decide(PermissionChoice.allowInChat);
    await future;
    expect(allows(RiskLevel.sensitive), isTrue);
    expect(allows(RiskLevel.sensitive, chat: 'other'), isFalse);
    expect(allows(RiskLevel.high), isFalse);
    expect(gate.pendingApproval, isNull);
    gate.policy = const PermissionPolicy(fullPermissions: true);
    expect(allows(RiskLevel.sensitive, chat: 'other'), isTrue);
    expect(allows(RiskLevel.high), isFalse);
    gate.policy = const PermissionPolicy(
      fullPermissions: true,
      skipHighRiskConfirmations: true,
      overrides: {'tool': ToolPermission.ask, 'blocked': ToolPermission.deny},
    );
    expect(allows(RiskLevel.sensitive), isFalse);
    expect(allows(RiskLevel.high), isFalse);
    expect(allows(RiskLevel.safe, name: 'blocked'), isFalse);
    expect(allows(RiskLevel.high, name: 'next'), isTrue);
  });

  test('always persists explicit per-tool allowance', () async {
    PermissionPolicy? saved;
    final gate = PermissionGate(
      onAlwaysAllow: (tool) async =>
          saved = PermissionPolicy(overrides: {tool: ToolPermission.allow}),
    );
    final future = authorize(gate, RiskLevel.sensitive);
    gate.decide(PermissionChoice.alwaysAllow);
    expect((await future).allowed, isTrue);
    expect(saved?.overrides['tool'], ToolPermission.allow);
    expect(
      (await authorize(
        gate,
        RiskLevel.sensitive,
        ctx: context('next'),
      )).allowed,
      isTrue,
    );
  });

  test(
    'high always asks despite full, tool override, and chat grants',
    () async {
      final gate = PermissionGate(
        policy: const PermissionPolicy(
          fullPermissions: true,
          overrides: {'tool': ToolPermission.allow},
        ),
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        final future = authorize(gate, RiskLevel.high);
        expect(gate.pendingApproval?.choices, [
          PermissionChoice.allowOnce,
          PermissionChoice.deny,
        ]);
        gate.decide(PermissionChoice.alwaysAllow);
        expect(gate.pendingApproval, isNotNull);
        gate.decide(PermissionChoice.allowOnce);
        expect((await future).allowed, isTrue);
      }
      gate.policy = gate.policy.copyWith(skipHighRiskConfirmations: true);
      expect(
        (await authorize(gate, RiskLevel.high)).reason,
        'high_risk_opt_in',
      );
    },
  );

  test(
    'deny and ask overrides win over full permissions and high opt-in',
    () async {
      final gate = PermissionGate(
        policy: const PermissionPolicy(
          fullPermissions: true,
          skipHighRiskConfirmations: true,
          overrides: {
            'denied': ToolPermission.deny,
            'asked': ToolPermission.ask,
          },
        ),
      );
      for (final risk in RiskLevel.values) {
        expect((await authorize(gate, risk, name: 'denied')).allowed, isFalse);
        final future = authorize(gate, risk, name: 'asked');
        expect(gate.pendingApproval, isNotNull);
        gate.decide(PermissionChoice.deny);
        expect((await future).allowed, isFalse);
      }
    },
  );

  test(
    'password typing is blocked even with every permission enabled',
    () async {
      final gate = PermissionGate(
        policy: const PermissionPolicy(
          fullPermissions: true,
          skipHighRiskConfirmations: true,
          overrides: {'browser_type': ToolPermission.allow},
        ),
      );
      final result = await gate.authorize(
        toolName: 'browser_type',
        args: {'text': 'example'},
        risk: RiskLevel.action,
        context: ToolContext(
          conversationId: 'chat',
          messageId: 'message',
          cancel: CancelToken(),
          targetIsPassword: true,
        ),
      );
      expect(result.allowed, isFalse);
      expect(result.reason, 'password_entry_blocked');
      expect(gate.pendingApproval, isNull);
    },
  );

  test('Stop clears pending approval and ignores a later approval', () async {
    final changes = <PermissionRequest?>[];
    final gate = PermissionGate(onPendingChanged: changes.add);
    final token = CancelToken();
    final future = authorize(gate, RiskLevel.high, ctx: context('chat', token));
    final assertion = expectLater(future, throwsA(isA<RequestCancelled>()));
    token.cancel();
    await assertion;
    expect(gate.pendingApproval, isNull);
    expect(changes.last, isNull);
    gate.decide(PermissionChoice.allowOnce);
  });

  test('policy JSON roundtrips; malformed and unknown values fail safe', () {
    const policy = PermissionPolicy(
      fullPermissions: true,
      overrides: {'one': ToolPermission.deny, 'two': ToolPermission.ask},
      highRiskKeywords: ['custom'],
    );
    final restored = PermissionPolicy.decode(policy.encode());
    expect(restored.fullPermissions, isTrue);
    expect(restored.skipHighRiskConfirmations, isFalse);
    expect(restored.overrides, policy.overrides);
    expect(restored.highRiskKeywords, ['custom']);
    expect(PermissionPolicy.decode('bad').fullPermissions, isFalse);
    expect(
      PermissionPolicy.decode('{"overrides":{"one":"other"}}').overrides,
      isEmpty,
    );
  });
}
