import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/providers/cancel_token.dart';
import '../../core/shell/shell_capability.dart';
import 'path_guard.dart';

/// run_shell where there is no Termux (iOS): a small shell over the
/// workspace, written in Dart. It runs one command or a pipeline of the
/// [commands] below. `/` is the workspace root; nothing outside it, and not
/// the file history in `.tako`, can be reached.
class WorkspaceShell extends ShellCapability {
  WorkspaceShell({required Future<Directory> Function() root}) : _root = root;
  final Future<Directory> Function() _root;

  static const commands = [
    'ls',
    'cat',
    'head',
    'tail',
    'wc',
    'grep',
    'find',
    'echo',
    'pwd',
    'date',
    'mkdir',
    'touch',
    'cp',
    'mv',
    'rm',
  ];

  /// Most bytes read from one file, and kept from one command's output.
  static const _maxBytes = 1 << 20;

  @override
  bool get installed => true;
  @override
  bool get permitted => true;
  @override
  String get environment =>
      "the app's built-in mini shell over the workspace "
      "(limited commands: ${commands.join(', ')}; pipes, no redirection)";
  @override
  Future<void> refresh() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<bool> openSetup() async => true;

  @override
  Future<ShellResult> run(
    String command, {
    required Duration timeout,
    required CancelToken cancel,
  }) async {
    final List<List<String>> pipeline;
    try {
      pipeline = parsePipeline(command);
    } on FormatException catch (error) {
      return ShellResult(exitCode: 2, stderr: 'sh: ${error.message}\n');
    }
    final guard = WorkspacePathGuard(await _root());
    final run = _Run(guard, cancel);
    try {
      var input = '';
      for (final (index, words) in pipeline.indexed) {
        cancel.throwIfCancelled();
        final last = index == pipeline.length - 1;
        input = await run.command(words, input).timeout(timeout);
        if (run.exitCode != 0 && !last) break;
      }
      return ShellResult(
        exitCode: run.exitCode,
        stdout: input,
        stderr: run.stderr.toString(),
      );
    } on RequestCancelled {
      return const ShellResult.cancelled();
    } on TimeoutException {
      return ShellResult(exitCode: 124, stderr: '${run.stderr}sh: timed out\n');
    }
  }

  /// Splits [command] into the words of each pipeline stage. Quotes group
  /// words; anything that would need a real shell is refused.
  static List<List<String>> parsePipeline(String command) {
    if (RegExp(r'[;&<>`\n\r\x00]|\$\(').hasMatch(command)) {
      throw const FormatException(
        'only single commands and pipes are supported',
      );
    }
    final stages = <List<String>>[[]];
    final word = StringBuffer();
    var hasWord = false;
    String? quote;
    void endWord() {
      if (hasWord) stages.last.add(word.toString());
      word.clear();
      hasWord = false;
    }

    for (var i = 0; i < command.length; i++) {
      final char = command[i];
      if (quote != null) {
        if (char == quote) {
          quote = null;
        } else if (char == r'\' && quote == '"' && i + 1 < command.length) {
          word.write(command[++i]);
        } else {
          word.write(char);
        }
      } else if (char == "'" || char == '"') {
        quote = char;
        hasWord = true;
      } else if (char == r'\' && i + 1 < command.length) {
        word.write(command[++i]);
        hasWord = true;
      } else if (char == ' ' || char == '\t') {
        endWord();
      } else if (char == '|') {
        endWord();
        stages.add([]);
      } else {
        word.write(char);
        hasWord = true;
      }
    }
    if (quote != null) throw const FormatException('unterminated quote');
    endWord();
    if (stages.any((stage) => stage.isEmpty)) {
      throw const FormatException('empty command');
    }
    return stages;
  }
}

class _Run {
  _Run(this.guard, this.cancel);
  final WorkspacePathGuard guard;
  final CancelToken cancel;
  final stderr = StringBuffer();
  var exitCode = 0;

  Future<String> command(List<String> words, String input) async {
    exitCode = 0;
    final name = words.first;
    final args = words.skip(1).toList();
    try {
      final output = switch (name) {
        'ls' => await _ls(args),
        'cat' => await _cat(args, input),
        'head' || 'tail' => await _lines(name, args, input),
        'wc' => await _wc(args, input),
        'grep' => await _grep(args, input),
        'find' => await _find(args),
        'echo' => '${args.join(' ')}\n',
        'pwd' => '/\n',
        'date' => '${DateTime.now().toIso8601String()}\n',
        'mkdir' => await _mkdir(args),
        'touch' => await _touch(args),
        'cp' || 'mv' => await _copyOrMove(name, args),
        'rm' => await _rm(args),
        _ => throw _Failure(127, 'command not found'),
      };
      return output.length > WorkspaceShell._maxBytes
          ? output.substring(0, WorkspaceShell._maxBytes)
          : output;
    } on _Failure catch (failure) {
      exitCode = failure.code;
      stderr.writeln('$name: ${failure.message}');
      return '';
    } on FormatException catch (error) {
      exitCode = 1;
      stderr.writeln('$name: ${error.message}');
      return '';
    } on FileSystemException catch (error) {
      exitCode = 1;
      stderr.writeln('$name: ${error.message}');
      return '';
    }
  }

  /// A workspace path for [path]; `/`, `.` and `./` start at its root.
  Future<String> _path(String path) {
    var relative = path.replaceAll(RegExp(r'^(\./|/)+'), '');
    relative = relative.replaceAll(RegExp(r'/+$'), '');
    if (relative == '.') relative = '';
    return guard.resolve(relative, allowRoot: true);
  }

  Future<String> _relative(String absolute) async {
    final root = await guard.resolve('', allowRoot: true);
    return p.relative(absolute, from: root).replaceAll(r'\', '/');
  }

  ({Set<String> flags, Map<String, String> values, List<String> rest}) _options(
    List<String> args, {
    Set<String> flags = const {},
    Set<String> values = const {},
  }) {
    final found = <String>{};
    final valued = <String, String>{};
    final rest = <String>[];
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (values.contains(arg) && i + 1 < args.length) {
        valued[arg] = args[++i];
      } else if (arg.startsWith('-') && arg.length > 1 && rest.isEmpty) {
        for (final flag in arg.substring(1).split('')) {
          if (!flags.contains(flag)) throw _Failure(2, 'unknown option -$flag');
          found.add(flag);
        }
      } else {
        rest.add(arg);
      }
    }
    return (flags: found, values: valued, rest: rest);
  }

  Future<String> _read(String path) async {
    final file = File(await _path(path));
    if (!await file.exists()) throw _Failure(1, '$path: no such file');
    final handle = await file.open();
    try {
      return utf8.decode(
        await handle.read(WorkspaceShell._maxBytes),
        allowMalformed: true,
      );
    } finally {
      await handle.close();
    }
  }

  Future<String> _ls(List<String> args) async {
    final options = _options(args, flags: {'l', 'a'});
    final paths = options.rest.isEmpty ? ['.'] : options.rest;
    final out = StringBuffer();
    for (final path in paths) {
      final absolute = await _path(path);
      final type = await FileSystemEntity.type(absolute, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        throw _Failure(1, '$path: no such file or directory');
      }
      final entries = type == FileSystemEntityType.directory
          ? (await Directory(absolute).list(followLinks: false).toList())
          : [File(absolute)];
      entries.sort((a, b) => a.path.compareTo(b.path));
      if (paths.length > 1) out.writeln('$path:');
      for (final entity in entries) {
        final name = p.basename(entity.path);
        if (name == '.tako' || entity is Link) continue;
        if (name.startsWith('.') && !options.flags.contains('a')) continue;
        final directory = entity is Directory;
        if (options.flags.contains('l')) {
          final stat = await entity.stat();
          final time = stat.modified.toIso8601String().substring(0, 16);
          out.writeln(
            '${(directory ? '-' : '${stat.size}').padLeft(10)}  $time  '
            '$name${directory ? '/' : ''}',
          );
        } else {
          out.writeln('$name${directory ? '/' : ''}');
        }
      }
    }
    return out.toString();
  }

  Future<String> _cat(List<String> args, String input) async {
    if (args.isEmpty) return input;
    final out = StringBuffer();
    for (final path in args) {
      out.write(await _read(path));
    }
    return out.toString();
  }

  Future<String> _lines(String name, List<String> args, String input) async {
    var count = 10;
    final rest = <String>[];
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '-n' && i + 1 < args.length) {
        count = int.tryParse(args[++i]) ?? (throw _Failure(2, 'bad count'));
      } else if (RegExp(r'^-\d+$').hasMatch(arg)) {
        count = int.parse(arg.substring(1));
      } else {
        rest.add(arg);
      }
    }
    final text = rest.isEmpty ? input : await _read(rest.single);
    final lines = const LineSplitter().convert(text);
    final kept = name == 'head'
        ? lines.take(count)
        : lines.skip(lines.length > count ? lines.length - count : 0);
    return kept.isEmpty ? '' : '${kept.join('\n')}\n';
  }

  Future<String> _wc(List<String> args, String input) async {
    final options = _options(args, flags: {'l', 'w', 'c'});
    final text = options.rest.isEmpty
        ? input
        : await _read(options.rest.single);
    final counts = {
      'l': '\n'.allMatches(text).length,
      'w': text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length,
      'c': utf8.encode(text).length,
    };
    final shown = [
      for (final key in ['l', 'w', 'c'])
        if (options.flags.isEmpty || options.flags.contains(key)) counts[key],
    ];
    return '${shown.join(' ')}\n';
  }

  Future<String> _grep(List<String> args, String input) async {
    final options = _options(args, flags: {'i', 'n', 'v', 'c', 'r'});
    if (options.rest.isEmpty) throw _Failure(2, 'missing pattern');
    final pattern = RegExp(
      options.rest.first,
      caseSensitive: !options.flags.contains('i'),
    );
    final sources = <(String?, String)>[];
    if (options.rest.length == 1) {
      sources.add((null, input));
    } else {
      for (final path in options.rest.skip(1)) {
        final absolute = await _path(path);
        if (await FileSystemEntity.isDirectory(absolute)) {
          if (!options.flags.contains('r')) {
            throw _Failure(2, '$path: is a directory');
          }
          for (final file in await _files(absolute)) {
            final relative = await _relative(file);
            sources.add((relative, await _read(relative)));
          }
        } else {
          sources.add((path, await _read(path)));
        }
      }
    }
    final out = StringBuffer();
    var matched = false;
    for (final (name, text) in sources) {
      cancel.throwIfCancelled();
      var count = 0;
      for (final (index, line) in const LineSplitter().convert(text).indexed) {
        if (pattern.hasMatch(line) == options.flags.contains('v')) continue;
        count++;
        if (options.flags.contains('c')) continue;
        out.writeln(
          [
            if (sources.length > 1 && name != null) name,
            if (options.flags.contains('n')) '${index + 1}',
            line,
          ].join(':'),
        );
      }
      if (options.flags.contains('c')) {
        out.writeln(
          sources.length > 1 && name != null ? '$name:$count' : count,
        );
      }
      matched |= count > 0;
    }
    if (!matched) exitCode = 1;
    return out.toString();
  }

  Future<List<String>> _files(String directory) async {
    final files = <String>[];
    await for (final entity in Directory(
      directory,
    ).list(recursive: true, followLinks: false)) {
      cancel.throwIfCancelled();
      final relative = await _relative(entity.path);
      if (relative.split('/').first == '.tako') continue;
      if (entity is File) files.add(entity.path);
    }
    return files..sort();
  }

  Future<String> _find(List<String> args) async {
    final options = _options(args, values: {'-name', '-type'});
    final start = options.rest.isEmpty ? '.' : options.rest.single;
    final glob = options.values['-name'];
    final type = options.values['-type'];
    final matcher = glob == null
        ? null
        : RegExp(
            '^${RegExp.escape(glob).replaceAll(r'\*', '.*').replaceAll(r'\?', '.')}\$',
          );
    final absolute = await _path(start);
    if (!await FileSystemEntity.isDirectory(absolute)) {
      throw _Failure(1, '$start: no such directory');
    }
    final out = StringBuffer();
    await for (final entity in Directory(
      absolute,
    ).list(recursive: true, followLinks: false)) {
      cancel.throwIfCancelled();
      final relative = await _relative(entity.path);
      if (relative.split('/').first == '.tako' || entity is Link) continue;
      if (type == 'f' && entity is! File ||
          type == 'd' && entity is! Directory) {
        continue;
      }
      if (matcher != null && !matcher.hasMatch(p.basename(entity.path))) {
        continue;
      }
      out.writeln(relative);
    }
    return out.toString();
  }

  Future<String> _mkdir(List<String> args) async {
    final options = _options(args, flags: {'p'});
    for (final path in options.rest) {
      final directory = Directory(await _path(path));
      if (!options.flags.contains('p') && await directory.exists()) {
        throw _Failure(1, '$path: exists');
      }
      await directory.create(recursive: options.flags.contains('p'));
    }
    return '';
  }

  Future<String> _touch(List<String> args) async {
    for (final path in args) {
      final file = File(await _path(path));
      if (await file.exists()) {
        await file.setLastModified(DateTime.now());
      } else {
        await file.create();
      }
    }
    return '';
  }

  Future<String> _copyOrMove(String name, List<String> args) async {
    final options = _options(args, flags: {'r'});
    if (options.rest.length != 2) {
      throw _Failure(2, 'needs a source and target');
    }
    final source = await _path(options.rest[0]);
    var target = await _path(options.rest[1]);
    if (source == await guard.resolve('', allowRoot: true)) {
      throw _Failure(1, 'cannot $name the workspace');
    }
    if (await FileSystemEntity.isDirectory(target)) {
      target = await _path('${options.rest[1]}/${p.basename(source)}');
    }
    final type = await FileSystemEntity.type(source, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw _Failure(1, '${options.rest[0]}: no such file or directory');
    }
    if (name == 'mv') {
      await (type == FileSystemEntityType.directory
          ? Directory(source).rename(target)
          : File(source).rename(target));
    } else if (type == FileSystemEntityType.directory) {
      if (!options.flags.contains('r')) {
        throw _Failure(1, '${options.rest[0]}: is a directory (use -r)');
      }
      for (final file in await _files(source)) {
        final copy = File(p.join(target, p.relative(file, from: source)));
        await copy.parent.create(recursive: true);
        await File(file).copy(copy.path);
      }
    } else {
      await File(source).copy(target);
    }
    return '';
  }

  Future<String> _rm(List<String> args) async {
    final options = _options(args, flags: {'r', 'f'});
    final root = await guard.resolve('', allowRoot: true);
    for (final path in options.rest) {
      final absolute = await _path(path);
      if (absolute == root) throw _Failure(1, 'cannot remove the workspace');
      final type = await FileSystemEntity.type(absolute, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        if (options.flags.contains('f')) continue;
        throw _Failure(1, '$path: no such file or directory');
      }
      if (type == FileSystemEntityType.directory) {
        if (!options.flags.contains('r')) {
          throw _Failure(1, '$path: is a directory (use -r)');
        }
        await Directory(absolute).delete(recursive: true);
      } else {
        await File(absolute).delete();
      }
    }
    return '';
  }
}

class _Failure implements Exception {
  _Failure(this.code, this.message);
  final int code;
  final String message;
}
