import 'dart:io';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

const _sourceUrl =
    'https://github.com/quickjs-ng/quickjs/releases/download/v0.17.0/quickjs-amalgam.zip';
const _sourceHash =
    'a0955463c74809173a253ff87365095e6972e8b171cfb6aa8a1e781adf35cfeb';

Future<void> main(List<String> args) => build(args, (input, output) async {
  if (!input.config.buildCodeAssets) return;
  final sourceRoot = input.outputDirectoryShared.resolve('quickjs-0.17.0/');
  await Directory.fromUri(sourceRoot).create(recursive: true);
  final ready = File.fromUri(sourceRoot.resolve('ready'));
  // Different ABI builds share this source cache. Publish it only when complete.
  final lock = await File.fromUri(
    sourceRoot.resolve('source.lock'),
  ).open(mode: FileMode.append);
  await lock.lock(FileLock.blockingExclusive);
  try {
    if (!await ready.exists()) {
      final client = HttpClient();
      late List<int> bytes;
      try {
        final response = await (await client.getUrl(
          Uri.parse(_sourceUrl),
        )).close();
        if (response.statusCode != HttpStatus.ok) {
          throw StateError(
            'QuickJS source download failed (${response.statusCode})',
          );
        }
        bytes = await response.fold<List<int>>(
          [],
          (data, chunk) => data..addAll(chunk),
        );
      } finally {
        client.close(force: true);
      }
      if (sha256.convert(bytes).toString() != _sourceHash) {
        throw StateError('QuickJS source checksum mismatch');
      }
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final name in ['quickjs-amalgam.c', 'quickjs.h', 'quickjs-libc.h']) {
        final entry = archive.findFile(name);
        if (entry == null) throw StateError('QuickJS source is incomplete');
        await File.fromUri(
          sourceRoot.resolve(name),
        ).writeAsBytes(entry.content);
      }
      await ready.writeAsString(_sourceHash);
    }
  } finally {
    await lock.unlock();
    await lock.close();
  }
  final os = input.config.code.targetOS;
  final source = sourceRoot.resolve('quickjs-amalgam.c');
  final shim = input.packageRoot.resolve('native/repl_bridge.c');
  // MinGW provides a small, self-contained test library on Windows hosts.
  // Android/iOS use the compiler supplied by Flutter through code assets.
  if (os == OS.windows &&
      input.config.code.targetArchitecture == Architecture.x64) {
    ProcessResult? compiler;
    try {
      compiler = await Process.run('gcc', ['-dumpmachine']);
    } on ProcessException {
      // Fall back to the configured Windows toolchain when MinGW is absent.
    }
    if (compiler != null &&
        compiler.exitCode == 0 &&
        '${compiler.stdout}'.contains('x86_64')) {
      final library = input.outputDirectory.resolve('tako_quickjs.dll');
      final result = await Process.run('gcc', [
        '-shared',
        '-O2',
        '-std=gnu11',
        '-static-libgcc',
        '-DQUICKJS_NG_BUILD',
        '-DBUILDING_QJS_SHARED',
        '-I${Directory.fromUri(sourceRoot).path}',
        source.toFilePath(),
        shim.toFilePath(),
        '-o',
        library.toFilePath(),
      ]);
      if (result.exitCode != 0) {
        throw StateError('QuickJS compilation failed: ${result.stderr}');
      }
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: 'quickjs.dart',
          file: library,
          linkMode: DynamicLoadingBundled(),
        ),
      );
      output.dependencies.addAll([source, shim]);
      return;
    }
  }
  await CBuilder.library(
    name: 'tako_quickjs',
    assetName: 'quickjs.dart',
    sources: ['native/repl_bridge.c', source.toFilePath()],
    includes: [Directory.fromUri(sourceRoot).path],
    defines: {'QUICKJS_NG_BUILD': null, 'BUILDING_QJS_SHARED': null},
    flags: [
      '-O2',
      '-std=gnu11',
      if (os == OS.android) '-Wl,-z,max-page-size=16384',
    ],
    libraries: [
      if (os == OS.android || os == OS.linux) 'm',
      if (os == OS.linux) 'pthread',
    ],
  ).run(input: input, output: output);
});
