import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:tako/core/on_device/on_device_capability.dart';
import 'package:tako/platform/on_device/model_files.dart';

import 'gguf_fixture.dart';

/// Serves [files] by URL, honouring Range unless [ignoreRange].
class FileServer extends http.BaseClient {
  FileServer(this.files, {this.ignoreRange = false, this.status = 200});
  final Map<String, Uint8List> files;
  final bool ignoreRange;
  final int status;
  final requests = <http.BaseRequest>[];
  StreamController<List<int>>? held;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (held != null) {
      return http.StreamedResponse(held!.stream, 200, contentLength: 1 << 20);
    }
    final body = files[request.url.toString()];
    if (body == null || status != 200) {
      return http.StreamedResponse(
        Stream.value(utf8.encode('<html>missing</html>')),
        body == null ? 404 : status,
      );
    }
    final range = RegExp(
      r'^bytes=(\d+)-$',
    ).firstMatch(request.headers['range'] ?? '');
    if (range != null && !ignoreRange) {
      final start = int.parse(range[1]!);
      final rest = body.sublist(start);
      return http.StreamedResponse(
        Stream.value(rest),
        206,
        contentLength: rest.length,
      );
    }
    return http.StreamedResponse(
      Stream.fromIterable([body.sublist(0, 10), body.sublist(10)]),
      200,
      contentLength: body.length,
    );
  }

  @override
  void close() {
    if (closed) return;
    closed = true;
    held?.addError(const SocketException('closed'));
    held?.close();
  }
}

void main() {
  late Directory root;
  late Directory folder;
  late FileServer server;
  late ModelFiles files;
  final model = ggufBytes();
  final projector = projectorBytes();
  final modelUrl = Uri.parse('https://hf.example/m/model.gguf');
  final projectorUrl = Uri.parse('https://hf.example/m/mmproj.gguf');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tako-models');
    folder = Directory(p.join(root.path, 'models'))..createSync();
    server = FileServer({
      '$modelUrl': model,
      '$projectorUrl': projector,
      'https://hf.example/page': Uint8List.fromList(
        utf8.encode('<!doctype html>${'x' * 64}'),
      ),
    });
    files = ModelFiles(folder, onChanged: () {}, clientFactory: () => server);
  });

  tearDown(() => root.delete(recursive: true));

  Future<void> settle() async {
    for (var i = 0; i < 400 && files.busy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('a download is checked, then becomes a model', () async {
    await files.download(
      modelUrl,
      fileName: 'Model Q4.gguf',
      sha256: sha256.convert(model).toString(),
      size: model.length,
      catalogId: 'fixture',
    );
    await settle();
    expect(files.downloads, isEmpty);
    final installed = files.models.single;
    expect(installed.id, 'Model Q4.gguf');
    expect(installed.catalogId, 'fixture');
    expect(installed.info.supportsTools, isTrue);
    expect(installed.sizeBytes, model.length);
    expect(File(p.join(folder.path, 'Model Q4.gguf')).readAsBytesSync(), model);
    expect(server.requests.single.headers['range'], isNull);
    expect((server.requests.single as http.Request).followRedirects, isTrue);
  });

  test('an interrupted download resumes where it stopped', () async {
    final partial = Directory(p.join(folder.path, '.downloads'))..createSync();
    File(
      p.join(partial.path, 'model.gguf.part'),
    ).writeAsBytesSync(model.sublist(0, 100));
    File(
      p.join(partial.path, 'model.gguf.json'),
    ).writeAsStringSync(jsonEncode({'url': '$modelUrl', 'size': model.length}));
    await files.refresh();
    final paused = files.downloads.single;
    expect((paused.state, paused.received), (DownloadState.paused, 100));

    await files.download(modelUrl, fileName: 'model.gguf', size: model.length);
    await settle();
    expect(server.requests.single.headers['range'], 'bytes=100-');
    expect(File(p.join(folder.path, 'model.gguf')).readAsBytesSync(), model);
  });

  test('a server that ignores Range starts over', () async {
    server = FileServer({'$modelUrl': model}, ignoreRange: true);
    files = ModelFiles(folder, onChanged: () {}, clientFactory: () => server);
    final partial = Directory(p.join(folder.path, '.downloads'))..createSync();
    File(
      p.join(partial.path, 'model.gguf.part'),
    ).writeAsBytesSync(List.filled(100, 1));
    File(
      p.join(partial.path, 'model.gguf.json'),
    ).writeAsStringSync(jsonEncode({'url': '$modelUrl'}));
    await files.download(modelUrl, fileName: 'model.gguf');
    await settle();
    expect(File(p.join(folder.path, 'model.gguf')).readAsBytesSync(), model);
  });

  test('a wrong checksum, size or format fails and keeps nothing', () async {
    await files.download(modelUrl, fileName: 'a.gguf', sha256: 'ab' * 32);
    await files.download(modelUrl, fileName: 'b.gguf', size: model.length + 1);
    await files.download(
      Uri.parse('https://hf.example/page'),
      fileName: 'c.gguf',
    );
    await files.download(
      Uri.parse('https://hf.example/gone'),
      fileName: 'd.gguf',
    );
    await settle();
    expect(
      {for (final d in files.downloads) d.id: (d.state, d.error)},
      {
        'a.gguf': (DownloadState.failed, 'checksum'),
        'b.gguf': (DownloadState.failed, 'size'),
        'c.gguf': (DownloadState.failed, 'not_gguf'),
        'd.gguf': (DownloadState.failed, 'http_404'),
      },
    );
    expect(files.models, isEmpty);
    expect(
      folder.listSync().whereType<File>().map((f) => p.basename(f.path)),
      isNot(contains(endsWith('.gguf'))),
    );
    await files.removeDownload('a.gguf');
    expect(files.downloads.map((d) => d.id), isNot(contains('a.gguf')));
  });

  test('only HTTPS, or HTTP inside the local network', () async {
    for (final url in [
      'http://hf.example/model.gguf',
      'ftp://hf.example/model.gguf',
      'https://user:pw@hf.example/model.gguf',
      'file:///sdcard/model.gguf',
    ]) {
      await expectLater(
        files.download(Uri.parse(url), fileName: 'model.gguf'),
        throwsA(
          isA<OnDeviceException>().having(
            (e) => e.code,
            'code',
            'unsupported_url',
          ),
        ),
      );
    }
    expect(downloadAllowed(Uri.parse('http://192.168.1.20:8000/m.gguf')), true);
    expect(server.requests, isEmpty);
  });

  test('pausing keeps what was received', () async {
    server.held = StreamController<List<int>>();
    await files.download(modelUrl, fileName: 'model.gguf');
    server.held!.add(model.sublist(0, 50));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    files.pause('model.gguf');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final paused = files.downloads.single;
    expect((paused.state, paused.received), (DownloadState.paused, 50));
    expect(
      File(p.join(folder.path, '.downloads', 'model.gguf.part')).lengthSync(),
      50,
    );
  });

  test('a projector download is attached to its model', () async {
    await files.download(modelUrl, fileName: 'model.gguf');
    await settle();
    await files.download(
      projectorUrl,
      fileName: 'mmproj.gguf',
      projectorFor: 'model.gguf',
    );
    await settle();
    expect(files.models.single.projector, 'mmproj.gguf');
    // A model file is not accepted as a projector, nor the reverse.
    await files.download(
      modelUrl,
      fileName: 'wrong-projector.gguf',
      projectorFor: 'model.gguf',
    );
    await files.download(projectorUrl, fileName: 'wrong-model.gguf');
    await settle();
    expect(files.downloads.map((d) => d.error), [
      'not_projector',
      'is_projector',
    ]);

    await files.removeProjector('model.gguf');
    expect(files.models.single.projector, isNull);
    expect(File(p.join(folder.path, 'mmproj.gguf')).existsSync(), isFalse);
  });

  test('importing moves the picked file in', () async {
    final picked = File(p.join(root.path, 'picked.gguf'))
      ..writeAsBytesSync(model);
    final imported = await files.importModel(picked, 'My model.gguf');
    expect(imported!.id, 'My model.gguf');
    expect(picked.existsSync(), isFalse);
    // The same name again gets a suffix.
    final again = File(p.join(root.path, 'again.gguf'))
      ..writeAsBytesSync(model);
    expect(
      (await files.importModel(again, 'My model.gguf'))!.id,
      'My model-2.gguf',
    );

    final page = File(p.join(root.path, 'page.gguf'))
      ..writeAsStringSync('<html>');
    await expectLater(
      files.importModel(page, 'page.gguf'),
      throwsA(
        isA<OnDeviceException>().having((e) => e.code, 'code', 'not_gguf'),
      ),
    );
    expect(page.existsSync(), isFalse);
    final mmproj = File(p.join(root.path, 'mmproj.gguf'))
      ..writeAsBytesSync(projector);
    await expectLater(
      files.importModel(mmproj, 'mmproj.gguf'),
      throwsA(
        isA<OnDeviceException>().having((e) => e.code, 'code', 'is_projector'),
      ),
    );

    final vision = File(p.join(root.path, 'vision.gguf'))
      ..writeAsBytesSync(projector);
    await files.importProjector(vision, 'vision.gguf', 'My model.gguf');
    expect(
      files.models.firstWhere((m) => m.id == 'My model.gguf').projector,
      'vision.gguf',
    );
  });

  test('deleting a model deletes its projector too', () async {
    final picked = File(p.join(root.path, 'picked.gguf'))
      ..writeAsBytesSync(model);
    await files.importModel(picked, 'model.gguf');
    final vision = File(p.join(root.path, 'vision.gguf'))
      ..writeAsBytesSync(projector);
    await files.importProjector(vision, 'vision.gguf', 'model.gguf');
    expect(files.storageBytes, greaterThan(model.length));

    await files.delete('model.gguf');
    expect(files.models, isEmpty);
    expect(
      folder.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.gguf'),
      ),
      isEmpty,
    );
  });

  test('file names stay inside the folder', () {
    expect(safeModelName('../../etc/passwd'), 'passwd.gguf');
    expect(safeModelName(r'C:\x\Model.GGUF'), 'Model.GGUF');
    expect(safeModelName('.hidden.gguf'), '_hidden.gguf');
    expect(safeModelName('a/b?c*.gguf'), 'b_c_.gguf');
    expect(safeModelName('x' * 300).length, 120);
  });
}
