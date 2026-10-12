import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/providers/cancel_token.dart';
import 'package:tako/core/tools/file_tools.dart';
import 'package:tako/core/tools/tool.dart';
import 'package:tako/platform/workspace/local_workspace.dart';
import 'package:tako/platform/workspace/path_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LocalWorkspace workspace;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tako_workspace_test_');
    workspace = LocalWorkspace(rootDirectory: root);
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'rejects traversal, absolute, URI, control, Windows aliases and history paths',
    () async {
      final guard = WorkspacePathGuard(root);
      for (final path in [
        '../x',
        'a/../x',
        '/x',
        r'C:\outside',
        r'\\server\share',
        'https://example.com/file',
        'x\u0000',
        'x\n',
        '.tako/history/x',
        '.TAKO/history/x',
        '.tako./history/x',
        'x//y',
        'x/./y',
        'x:stream',
        'CON.txt',
        'nested/NUL',
        'folder /x',
      ]) {
        await expectLater(
          guard.resolve(path),
          throwsFormatException,
          reason: path,
        );
      }
      expect(
        await guard.resolve('nested/new.txt'),
        p.join(root.path, 'nested', 'new.txt'),
      );
      expect(
        await guard.resolve('', allowRoot: true),
        await root.resolveSymbolicLinks(),
      );
    },
  );

  test(
    'rejects symlink parents for both existing reads and missing writes',
    () async {
      final outside = await Directory.systemTemp.createTemp(
        'tako_outside_test_',
      );
      final link = Link(p.join(root.path, 'shortcut'));
      try {
        await File(
          p.join(outside.path, 'existing.txt'),
        ).writeAsString('outside');
        try {
          await link.create(outside.path);
        } on FileSystemException catch (error) {
          if (Platform.isWindows &&
              [5, 1314].contains(error.osError?.errorCode)) {
            markTestSkipped(
              'Windows does not grant symbolic-link creation to this process',
            );
            return;
          }
          rethrow;
        }
        await expectLater(
          workspace.read('shortcut/existing.txt'),
          throwsFormatException,
        );
        await expectLater(
          workspace.write('shortcut/new.txt', 'escape'),
          throwsFormatException,
        );
        expect(await File(p.join(outside.path, 'new.txt')).exists(), isFalse);
        expect(await workspace.list(), isEmpty);
      } finally {
        if (await link.exists()) await link.delete();
        await outside.delete(recursive: true);
      }
    },
  );

  test(
    'new file, overwrite, delete and successive rewinds restore exact content',
    () async {
      final created = await workspace.write('notes/test.txt', 'first');
      final overwritten = await workspace.write('notes/test.txt', 'second');
      expect((await workspace.read('notes/test.txt')).text, 'second');
      final deleted = await workspace.delete('notes/test.txt');
      expect(await workspace.list(path: 'notes'), isEmpty);
      await workspace.restoreBackup(deleted.backupPath!);
      expect((await workspace.read('notes/test.txt')).text, 'second');
      await workspace.restoreBackup(overwritten.backupPath!);
      expect((await workspace.read('notes/test.txt')).text, 'first');
      await workspace.restoreBackup(created.backupPath!);
      expect(await workspace.list(path: 'notes'), isEmpty);
      expect(
        (await workspace.list()).any((entry) => entry.name == '.tako'),
        isFalse,
      );
    },
  );

  test(
    'backup restore requires a history metadata member and guarded target',
    () async {
      await expectLater(
        workspace.restoreBackup('notes/plain.txt'),
        throwsFormatException,
      );
      await expectLater(
        workspace.restoreBackup('.tako/history/../../outside.json'),
        throwsFormatException,
      );
      await expectLater(
        workspace.write('.tako/history/spoof.json', '{}'),
        throwsFormatException,
      );
      final effect = await workspace.write('notes.txt', 'safe');
      final metadata = File(
        p.joinAll([root.path, ...effect.backupPath!.split('/')]),
      );
      await metadata.writeAsString(
        jsonEncode({'path': '../outside.txt', 'existed': false}),
      );
      await expectLater(
        workspace.restoreBackup(effect.backupPath!),
        throwsFormatException,
      );
    },
  );

  test(
    'pruning deletes complete old backup groups and protects a requested backup',
    () async {
      workspace = LocalWorkspace(rootDirectory: root, maxHistoryBytes: 400);
      await workspace.write('test.txt', 'a' * 350);
      final older = await workspace.write('test.txt', 'b' * 350);
      final newest = await workspace.write('test.txt', 'c' * 350);
      await workspace.pruneHistory(protectedPaths: {newest.backupPath!});
      expect(
        await File(
          p.joinAll([root.path, ...older.backupPath!.split('/')]),
        ).exists(),
        isFalse,
      );
      await workspace.restoreBackup(newest.backupPath!);
      expect((await workspace.read('test.txt')).text, 'b' * 350);
      final history = Directory(p.join(root.path, '.tako', 'history'));
      final files = await history.list().toList();
      expect(files.length, 2);
      await workspace.pruneHistory();
      expect(await history.list().isEmpty, isTrue);
    },
  );

  test('cancelled mutations do not create or remove user files', () async {
    final cancel = CancelToken()..cancel();
    await expectLater(
      workspace.write('never.txt', 'x', cancel: cancel),
      throwsA(isA<RequestCancelled>()),
    );
    await workspace.write('keep.txt', 'keep');
    await expectLater(
      workspace.delete('keep.txt', cancel: cancel),
      throwsA(isA<RequestCancelled>()),
    );
    expect((await workspace.read('keep.txt')).text, 'keep');
  });

  test(
    'text attachments are copied with unique safe names, persisted without payload images',
    () async {
      final first = await workspace.importBytes(
        '../report.txt',
        Uint8List.fromList(utf8.encode('hello 世界')),
      );
      final second = await workspace.importBytes(
        '../report.txt',
        Uint8List.fromList(utf8.encode('different')),
      );
      expect(first, isA<FileBlock>());
      expect((first as FileBlock).path, startsWith('attachments/'));
      expect(first.path, isNot((second as FileBlock).path));
      expect((await workspace.read(first.path)).text, 'hello 世界');
      expect(first.extractedText, 'hello 世界');
      await workspace.write(first.path, 'changed by direct user operation');
      expect(
        ((await workspace.hydrateBlocks([first], vision: false)).single
                as FileBlock)
            .extractedText,
        'hello 世界',
      );
      final context = ToolContext(
        conversationId: 'c',
        messageId: 'm',
        cancel: CancelToken(),
      );
      await expectLater(
        FileTool(
          workspace,
          'file_write',
        ).run({'path': first.path, 'text': 'mutate'}, context),
        throwsFormatException,
      );
      await expectLater(
        FileTool(workspace, 'file_delete').run({'path': first.path}, context),
        throwsFormatException,
      );
    },
  );

  test(
    'images downscale to 1568, preserve runtime data only and degrade for text models',
    () async {
      final source = img.Image(width: 2000, height: 1000);
      final block =
          await workspace.importBytes(
                'wide.png',
                Uint8List.fromList(img.encodePng(source)),
              )
              as ImageBlock;
      final hydrated = await workspace.hydrateBlocks([block], vision: true);
      final image = hydrated.single as ImageBlock;
      final decoded = img.decodeJpg(base64Decode(image.data!))!;
      expect(decoded.width, 1568);
      expect(decoded.height, 784);
      expect(image.mimeType, 'image/jpeg');
      expect(image.toJson().containsKey('data'), isFalse);
      expect(
        (await workspace.hydrateBlocks([block], vision: false)).single,
        isA<TextBlock>(),
      );
      final toolResult = ToolResultBlock(
        toolCallId: 'call',
        toolName: 'file_read',
        content: 'image',
        attachments: [block],
      );
      final nested =
          (await workspace.hydrateBlocks([toolResult], vision: true)).single
              as ToolResultBlock;
      expect((nested.attachments.single as ImageBlock).data, isNotEmpty);
    },
  );

  test('PDFium extracts text from an actual PDF', () async {
    Pdfrx.cacheDirectoryPath = root.path;
    final text = await LocalWorkspace.extractPdfText(
      _simplePdf('Hello Tako PDF'),
    );
    expect(text, contains('Hello Tako PDF'));
  });

  test(
    'image imports decode payloads instead of trusting names and normalize safely',
    () async {
      final bytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 2000, height: 1000)),
      );
      final image = await workspace.importImageBytes('../../spoof.pdf', bytes);
      expect(image.path, startsWith('attachments/'));
      expect(image.path, endsWith('-spoof.jpg'));
      expect(image.path, isNot(contains('..')));
      expect(image.mimeType, 'image/jpeg');
      expect(image.data, isNull);
      final saved = await workspace.readBytes(image.path);
      final decoded = img.decodeJpg(saved)!;
      expect(decoded.width, 1568);
      expect(decoded.height, 784);
      expect(jsonEncode(image.toJson()), isNot(contains('data')));
      final hydrated =
          (await workspace.hydrateBlocks([image], vision: true)).single
              as ImageBlock;
      expect(img.decodeJpg(base64Decode(hydrated.data!))!.width, 1568);
    },
  );

  test('invalid image imports never write an attachment', () async {
    final invalidPayloads = [
      Uint8List(0),
      Uint8List.fromList(utf8.encode('plain text pretending to be an image')),
      Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      Uint8List(LocalWorkspace.maxFileBytes + 1),
    ];
    for (final payload in invalidPayloads) {
      await expectLater(
        workspace.importImageBytes('claimed.png', payload),
        throwsA(isA<Exception>()),
      );
      expect(await root.list().isEmpty, isTrue);
    }
  });

  test('cancelled image decoding cannot create an attachment', () async {
    final bytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 32, height: 16)),
    );
    final cancelled = CancelToken()..cancel();
    await expectLater(
      workspace.importImageBytes('cancelled.png', bytes, cancel: cancelled),
      throwsA(isA<RequestCancelled>()),
    );
    final duringDecode = CancelToken();
    final importing = workspace.importImageBytes(
      'cancel-during-decode.png',
      bytes,
      cancel: duringDecode,
    );
    duringDecode.cancel();
    await expectLater(importing, throwsA(isA<RequestCancelled>()));
    expect(await root.list().isEmpty, isTrue);
  });

  test(
    'GIF image imports normalize the first frame into the send format',
    () async {
      final image = await workspace.importImageBytes(
        'keyboard.gif',
        Uint8List.fromList(img.encodeGif(img.Image(width: 13, height: 7))),
      );
      expect(image.mimeType, 'image/jpeg');
      expect(image.path, endsWith('.jpg'));
      final decoded = img.decodeJpg(await workspace.readBytes(image.path))!;
      expect(decoded.width, 13);
      expect(decoded.height, 7);
    },
  );

  test(
    'image tool results snapshot bytes before later workspace edits',
    () async {
      final original = Uint8List.fromList(
        img.encodePng(img.Image(width: 16, height: 16)),
      );
      await File(p.join(root.path, 'picture.png')).writeAsBytes(original);
      final ctx = ToolContext(
        conversationId: 'c',
        messageId: 'm',
        cancel: CancelToken(),
      );
      final result = await FileTool(
        workspace,
        'file_read',
      ).run({'path': 'picture.png'}, ctx);
      final attachment = result.attachments.single as ImageBlock;
      expect(attachment.path, startsWith('attachments/'));
      await workspace.write('picture.png', 'changed later');
      final hydrated =
          (await workspace.hydrateBlocks([attachment], vision: true)).single
              as ImageBlock;
      expect(img.decodeJpg(base64Decode(hydrated.data!))!.width, 16);
    },
  );

  test(
    'all four file tools use the specified risk levels and return backup effects',
    () async {
      final ctx = ToolContext(
        conversationId: 'c',
        messageId: 'm',
        cancel: CancelToken(),
      );
      final tools = fileTools(workspace);
      expect(tools.map((tool) => tool.riskFor({}, ctx)), [
        RiskLevel.safe,
        RiskLevel.sensitive,
        RiskLevel.action,
        RiskLevel.high,
      ]);
      final result = await tools[2].run({
        'path': 'test.txt',
        'text': 'hello',
      }, ctx);
      expect(
        result.sideEffects.single.backupPath,
        startsWith('.tako/history/'),
      );
      expect((await tools[1].run({'path': 'test.txt'}, ctx)).content, 'hello');
      expect((await tools.first.run({}, ctx)).content, contains('test.txt'));
    },
  );
}

Uint8List _simplePdf(String text) {
  final stream = 'BT /F1 12 Tf 72 720 Td ($text) Tj ET';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ${stream.length} >>\nstream\n$stream\nendstream',
  ];
  final output = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(output.length);
    output.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = output.length;
  output.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    output.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  output.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
  );
  return Uint8List.fromList(ascii.encode(output.toString()));
}
