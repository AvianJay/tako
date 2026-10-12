import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tako/core/permissions/risk_classifier.dart';
import 'package:tako/core/providers/cancel_token.dart';
import 'package:tako/core/shell/shell_capability.dart';
import 'package:tako/platform/workspace/workspace_shell.dart';

void main() {
  late Directory outside;
  late Directory root;
  late WorkspaceShell shell;

  setUp(() async {
    outside = await Directory.systemTemp.createTemp('tako-shell');
    root = Directory(p.join(outside.path, 'workspace'))..createSync();
    File(p.join(outside.path, 'secret.txt')).writeAsStringSync('secret');
    File(
      p.join(root.path, 'notes.txt'),
    ).writeAsStringSync('apples\nBananas\ncherries\napricots\n');
    Directory(p.join(root.path, 'docs', 'old')).createSync(recursive: true);
    File(p.join(root.path, 'docs', 'plan.md')).writeAsStringSync('# Plan\n');
    File(p.join(root.path, 'docs', 'old', 'a.md')).writeAsStringSync('apple\n');
    Directory(
      p.join(root.path, '.tako', 'history'),
    ).createSync(recursive: true);
    File(
      p.join(root.path, '.tako', 'history', 'x'),
    ).writeAsStringSync('backup');
    shell = WorkspaceShell(root: () async => root);
  });

  tearDown(() => outside.delete(recursive: true));

  Future<ShellResult> run(String command) => shell.run(
    command,
    timeout: const Duration(seconds: 10),
    cancel: CancelToken(),
  );

  test('reads the workspace with pipes', () async {
    expect((await run('ls')).stdout, 'docs/\nnotes.txt\n');
    expect((await run('ls -a /')).stdout, isNot(contains('.tako')));
    expect((await run('cat notes.txt | grep -i ^b')).stdout, 'Bananas\n');
    expect(
      (await run('grep -n ap notes.txt')).stdout,
      '1:apples\n4:apricots\n',
    );
    expect((await run('head -n 2 notes.txt')).stdout, 'apples\nBananas\n');
    expect((await run('tail -1 ./notes.txt')).stdout, 'apricots\n');
    expect((await run('cat notes.txt | wc -l')).stdout, '4\n');
    expect((await run('find . -name "*.md"')).stdout.split('\n')..sort(), [
      '',
      'docs/old/a.md',
      'docs/plan.md',
    ]);
    expect((await run('grep -r apple docs')).stdout, 'docs/old/a.md:apple\n');
    expect((await run("echo 'two  spaces' end")).stdout, 'two  spaces end\n');
    expect((await run('pwd')).stdout, '/\n');
  });

  test('changes files only inside the workspace', () async {
    expect((await run('mkdir -p out/deep')).exitCode, 0);
    expect((await run('cp notes.txt out/deep')).exitCode, 0);
    expect(
      File(p.join(root.path, 'out', 'deep', 'notes.txt')).readAsStringSync(),
      startsWith('apples'),
    );
    expect((await run('mv out/deep/notes.txt out/n.txt')).exitCode, 0);
    expect((await run('touch out/new.txt')).exitCode, 0);
    expect((await run('ls out')).stdout, 'deep/\nn.txt\nnew.txt\n');
    expect((await run('rm out')).exitCode, 1);
    expect((await run('rm -r out')).exitCode, 0);
    expect(Directory(p.join(root.path, 'out')).existsSync(), isFalse);
  });

  test(
    'nothing outside the workspace or in its history is reachable',
    () async {
      for (final command in [
        'cat ../secret.txt',
        'cat /../secret.txt',
        'ls .tako',
        'cat .tako/history/x',
        'rm -r .tako',
        'rm -r /',
        'cp ../secret.txt here.txt',
      ]) {
        final result = await run(command);
        expect(result.exitCode, isNot(0), reason: command);
        expect(result.stdout, isNot(contains('secret')), reason: command);
        expect(result.stdout, isNot(contains('backup')), reason: command);
      }
      expect(
        File(p.join(root.path, '.tako', 'history', 'x')).existsSync(),
        true,
      );
      expect(File(p.join(outside.path, 'secret.txt')).existsSync(), true);
    },
  );

  test('anything that needs a real shell is refused', () async {
    for (final command in [
      'cat notes.txt > copy.txt',
      'ls; rm notes.txt',
      'ls && rm notes.txt',
      r'echo $(rm notes.txt)',
      'echo `id`',
      'echo "unterminated',
      'ls |',
    ]) {
      final result = await run(command);
      expect(result.exitCode, 2, reason: command);
    }
    expect((await run('python3 -c 1')).exitCode, 127);
    expect(File(p.join(root.path, 'notes.txt')).existsSync(), isTrue);
  });

  test('read-only commands stay sensitive, the rest are high risk', () {
    // The permission gate classifies the command text before it runs.
    expect(RiskClassifier.isReadOnlyShell('cat notes.txt | grep a'), isTrue);
    expect(RiskClassifier.isReadOnlyShell('rm -r docs'), isFalse);
    expect(RiskClassifier.isReadOnlyShell('mkdir out'), isFalse);
    expect(shell.environment, contains('built-in mini shell'));
  });

  test('a cancelled command reports so', () async {
    final cancel = CancelToken()..cancel();
    final result = await shell.run(
      'grep -r a .',
      timeout: const Duration(seconds: 10),
      cancel: cancel,
    );
    expect(result.cancelled, isTrue);
  });
}
