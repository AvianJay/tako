import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/permissions/risk_classifier.dart';
import 'package:tako/core/providers/cancel_token.dart';
import 'package:tako/core/tools/tool.dart';

void main() {
  test('read-only shell supports allowlisted pipelines and quoted paths', () {
    for (final command in [
      'ls -la',
      'cat "my notes.txt" | head -n 10',
      'find . -name "*.txt"',
      'df -h',
      'du -sh .',
      'uname -a',
      'ps aux | grep tako',
      'pwd',
      'wc -l file',
      'date +%F',
      'echo hello',
    ]) {
      expect(RiskClassifier.isReadOnlyShell(command), isTrue, reason: command);
    }
  });

  test('shell mutation, expansion and shell syntax are always high risk', () {
    for (final command in [
      'rm file',
      'ls > file',
      'cat file >> copy',
      'echo x; rm file',
      'ls && pwd',
      'ls || pwd',
      'ls | sh',
      'cat \$(touch file)',
      'echo `touch file`',
      'echo \$HOME',
      'find . -delete',
      'find . -exec rm {} +',
      'find . -execdir touch file +',
      'find . -fprint output',
      'find . -fprintf output %p',
      'date -s 20260101',
      'date --set=now',
      'date 101001012026',
      'VAR=x ls',
      '/bin/ls',
      'ls\npwd',
      'cat < file',
      'ls &',
      'cat "unterminated',
      'ls |',
      'echo hi # comment',
      '',
    ]) {
      expect(RiskClassifier.isReadOnlyShell(command), isFalse, reason: command);
    }
  });

  test('tap and browser label escalation works for English and Chinese', () {
    for (final label in ['Send message', 'PAY NOW', '確認', '刪除', '发送']) {
      for (final tool in ['tap', 'browser_click']) {
        final risk = RiskClassifier.classify(
          toolName: tool,
          declaredRisk: RiskLevel.action,
          args: {'label': 'innocent label'},
          context: ToolContext(
            conversationId: 'chat',
            messageId: 'message',
            cancel: CancelToken(),
            targetLabel: label,
          ),
        );
        expect(risk, RiskLevel.high, reason: '$tool $label');
      }
    }
  });

  test('custom high risk labels and shell risk do not lower declared risk', () {
    final context = ToolContext(
      conversationId: 'chat',
      messageId: 'message',
      cancel: CancelToken(),
    );
    expect(
      RiskClassifier.classify(
        toolName: 'browser_click',
        declaredRisk: RiskLevel.action,
        args: {'label': 'Launch'},
        context: context,
        highRiskKeywords: ['launch'],
      ),
      RiskLevel.high,
    );
    expect(
      RiskClassifier.classify(
        toolName: 'run_shell',
        declaredRisk: RiskLevel.safe,
        args: {'command': 'pwd'},
        context: context,
      ),
      RiskLevel.sensitive,
    );
    expect(
      RiskClassifier.classify(
        toolName: 'run_shell',
        declaredRisk: RiskLevel.high,
        args: {'command': 'pwd'},
        context: context,
      ),
      RiskLevel.high,
    );
  });
}
