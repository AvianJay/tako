import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../core/on_device/gguf.dart';
import '../../core/on_device/on_device_capability.dart';
import '../../core/providers/provider_config.dart';

/// The model folder: GGUF files, `models.json` with what the files cannot say
/// (projectors, catalog IDs), and `.downloads/` with partial downloads.
class ModelFiles {
  ModelFiles(
    this.directory, {
    required this.onChanged,
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final Directory directory;
  final void Function() onChanged;
  final http.Client Function() _clientFactory;

  List<LocalModel> models = const [];
  final _downloads = <String, ModelDownload>{};
  final _clients = <String, http.Client>{};
  final _infos = <String, (int, DateTime, GgufInfo?)>{};
  var _storage = 0;
  var _lastProgress = DateTime(0);

  List<ModelDownload> get downloads => _downloads.values.toList();

  /// A download is still receiving, checking or moving its file.
  bool get busy => _clients.isNotEmpty;
  int get storageBytes => _storage;
  Directory get _partial => Directory(p.join(directory.path, '.downloads'));
  File get _index => File(p.join(directory.path, 'models.json'));
  String path(String fileName) => p.join(directory.path, fileName);
  File _part(String id) => File(p.join(_partial.path, '$id.part'));
  File _meta(String id) => File(p.join(_partial.path, '$id.json'));

  Future<void> refresh() async {
    await _partial.create(recursive: true);
    final index = await _readIndex();
    final infos = <String, GgufInfo>{};
    var storage = 0;
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      storage += stat.size;
      if (p.dirname(entity.path) != directory.path ||
          !entity.path.toLowerCase().endsWith('.gguf')) {
        continue;
      }
      final name = p.basename(entity.path);
      final cached = _infos[name];
      GgufInfo? info;
      if (cached != null &&
          cached.$1 == stat.size &&
          cached.$2 == stat.modified) {
        info = cached.$3;
      } else {
        try {
          info = await readGgufFile(entity);
        } on FormatException {
          info = null;
        } on FileSystemException {
          info = null;
        }
        _infos[name] = (stat.size, stat.modified, info);
      }
      if (info != null) infos[name] = info;
    }
    _storage = storage;
    models = [
      for (final MapEntry(key: name, value: info) in infos.entries)
        if (!info.isProjector)
          LocalModel(
            id: name,
            sizeBytes: _infos[name]!.$1,
            info: info,
            projector: switch (index[name]?['projector']) {
              final String projector
                  when infos[projector]?.isProjector == true =>
                projector,
              _ => null,
            },
            catalogId: index[name]?['catalogId'] as String?,
          ),
    ]..sort((a, b) => a.id.toLowerCase().compareTo(b.id.toLowerCase()));
    await for (final entity in _partial.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final id = p.basenameWithoutExtension(entity.path);
      if (_downloads.containsKey(id)) continue;
      final data = await _readJson(entity);
      final url = Uri.tryParse(data['url'] as String? ?? '');
      if (url == null) continue;
      final part = _part(id);
      _downloads[id] = ModelDownload(
        id: id,
        url: url,
        received: await part.exists() ? await part.length() : 0,
        total: data['size'] as int?,
        state: DownloadState.paused,
        projectorFor: data['projectorFor'] as String?,
        catalogId: data['catalogId'] as String?,
      );
    }
    onChanged();
  }

  /// Moves a picked file into the folder. The picker's copy is renamed, not
  /// copied, so a large model does not need its size twice.
  Future<LocalModel?> importModel(File picked, String name) async {
    await _checked(picked, projector: false);
    final target = await _free(name);
    await _move(picked, target);
    await refresh();
    return models.where((m) => m.id == p.basename(target.path)).firstOrNull;
  }

  Future<void> importProjector(File picked, String name, String model) async {
    await _checked(picked, projector: true);
    final target = await _free(name);
    await _move(picked, target);
    await _attach(model, p.basename(target.path));
  }

  Future<void> _checked(File file, {required bool projector}) async {
    final GgufInfo info;
    try {
      info = await readGgufFile(file);
    } on FormatException {
      await _deleteQuietly(file);
      throw const OnDeviceException('not_gguf');
    }
    if (info.isProjector != projector) {
      await _deleteQuietly(file);
      throw OnDeviceException(projector ? 'not_projector' : 'is_projector');
    }
  }

  Future<void> download(
    Uri url, {
    required String fileName,
    String? sha256,
    int? size,
    String? catalogId,
    String? projectorFor,
  }) async {
    if (!downloadAllowed(url)) {
      throw const OnDeviceException('unsupported_url');
    }
    final id = safeModelName(fileName);
    if (_clients.containsKey(id)) return;
    if (await File(path(id)).exists()) {
      throw const OnDeviceException('exists');
    }
    await _partial.create(recursive: true);
    final previous = await _readJson(_meta(id));
    if (previous.isNotEmpty && previous['url'] != url.toString()) {
      // Another source for the same name starts over.
      await _deleteQuietly(_part(id));
    }
    await _meta(id).writeAsString(
      jsonEncode({
        'url': url.toString(),
        'sha256': ?sha256,
        'size': ?size,
        'catalogId': ?catalogId,
        'projectorFor': ?projectorFor,
      }),
    );
    final part = _part(id);
    final download = _downloads[id] = ModelDownload(
      id: id,
      url: url,
      received: await part.exists() ? await part.length() : 0,
      total: size,
      projectorFor: projectorFor,
      catalogId: catalogId,
    );
    _clients[id] = _clientFactory();
    onChanged();
    unawaited(_run(download, sha256: sha256, size: size));
  }

  Future<void> _run(ModelDownload download, {String? sha256, int? size}) async {
    final id = download.id;
    final client = _clients[id]!;
    final part = _part(id);
    try {
      var received = await part.exists() ? await part.length() : 0;
      final request = http.Request('GET', download.url)
        ..followRedirects = true
        ..maxRedirects = 10;
      if (received > 0) request.headers['range'] = 'bytes=$received-';
      final response = await client.send(request);
      if (response.statusCode == 416 && size != null && received == size) {
        // Already complete.
      } else if (response.statusCode != 200 && response.statusCode != 206) {
        throw OnDeviceException('http_${response.statusCode}');
      } else {
        if (response.statusCode == 200) received = 0;
        final total = switch (response.contentLength) {
          final length? => received + length,
          null => size,
        };
        if (size != null && total != null && total != size) {
          throw const OnDeviceException('size');
        }
        _progress(id, received, total, force: true);
        final sink = part.openWrite(
          mode: received == 0 ? FileMode.writeOnly : FileMode.append,
        );
        var checkedMagic = received >= 4;
        final head = BytesBuilder();
        try {
          await for (final chunk in response.stream) {
            if (!checkedMagic) {
              head.add(chunk);
              if (head.length >= 4) {
                final magic = head.toBytes().sublist(0, 4);
                if (ascii.decode(magic, allowInvalid: true) != 'GGUF') {
                  throw const OnDeviceException('not_gguf');
                }
                checkedMagic = true;
              }
            }
            sink.add(chunk);
            received += chunk.length;
            _progress(id, received, total);
          }
        } finally {
          await sink.close();
        }
        if (total != null && received != total) {
          throw const OnDeviceException('network');
        }
      }
      _update(id, (d) => _copy(d, state: DownloadState.verifying));
      if (size != null && await part.length() != size) {
        await _deleteQuietly(part);
        throw const OnDeviceException('size');
      }
      if (sha256 != null &&
          (await crypto.sha256.bind(part.openRead()).first).toString() !=
              sha256.toLowerCase()) {
        await _deleteQuietly(part);
        throw const OnDeviceException('checksum');
      }
      await _checked(part, projector: download.projectorFor != null);
      await part.rename(path(id));
      await _deleteQuietly(_meta(id));
      _downloads.remove(id);
      if (download.projectorFor case final model?) {
        await _attach(model, id);
      } else {
        await _setIndex(id, {'catalogId': download.catalogId});
        await refresh();
      }
    } on OnDeviceException catch (error) {
      _fail(id, error.code);
    } on FileSystemException catch (error) {
      // ENOSPC on Linux and Android, and on iOS.
      final code = error.osError?.errorCode;
      _fail(id, code == 28 ? 'no_space' : 'storage');
    } catch (_) {
      // A paused or removed download's client was closed on purpose.
      if (_clients[id] == client) _fail(id, 'network');
    } finally {
      if (_clients[id] == client) _clients.remove(id);
      client.close();
      onChanged();
    }
  }

  void pause(String id) {
    final client = _clients.remove(id);
    if (client == null) return;
    client.close();
    _update(id, (d) => _copy(d, state: DownloadState.paused));
  }

  Future<void> removeDownload(String id) async {
    _clients.remove(id)?.close();
    _downloads.remove(id);
    await _deleteQuietly(_part(id));
    await _deleteQuietly(_meta(id));
    await refresh();
  }

  Future<void> delete(String modelId) async {
    final model = models.where((m) => m.id == modelId).firstOrNull;
    await _deleteQuietly(File(path(modelId)));
    if (model?.projector case final projector?) {
      await _deleteQuietly(File(path(projector)));
    }
    await _setIndex(modelId, {'projector': null, 'catalogId': null});
    await refresh();
  }

  Future<void> removeProjector(String modelId) async {
    final model = models.where((m) => m.id == modelId).firstOrNull;
    if (model?.projector case final projector?) {
      await _deleteQuietly(File(path(projector)));
    }
    await _setIndex(modelId, {'projector': null});
    await refresh();
  }

  Future<void> _attach(String model, String projector) async {
    final previous = models.where((m) => m.id == model).firstOrNull?.projector;
    if (previous != null && previous != projector) {
      await _deleteQuietly(File(path(previous)));
    }
    await _setIndex(model, {'projector': projector});
    await refresh();
  }

  void _progress(String id, int received, int? total, {bool force = false}) {
    final now = DateTime.now();
    final notify = force || now.difference(_lastProgress) >= _progressInterval;
    if (notify) _lastProgress = now;
    _update(
      id,
      (d) => ModelDownload(
        id: d.id,
        url: d.url,
        received: received,
        total: total ?? d.total,
        projectorFor: d.projectorFor,
        catalogId: d.catalogId,
      ),
      notify: notify,
    );
  }

  static const _progressInterval = Duration(milliseconds: 250);

  void _fail(String id, String code) =>
      _update(id, (d) => _copy(d, state: DownloadState.failed, error: code));

  void _update(
    String id,
    ModelDownload Function(ModelDownload) change, {
    bool notify = true,
  }) {
    final current = _downloads[id];
    if (current == null) return;
    _downloads[id] = change(current);
    if (notify) onChanged();
  }

  ModelDownload _copy(ModelDownload d, {DownloadState? state, String? error}) =>
      ModelDownload(
        id: d.id,
        url: d.url,
        received: d.received,
        total: d.total,
        state: state ?? d.state,
        error: error,
        projectorFor: d.projectorFor,
        catalogId: d.catalogId,
      );

  Future<File> _free(String name) async {
    final safe = safeModelName(name);
    final stem = p.basenameWithoutExtension(safe);
    var target = File(path(safe));
    for (var n = 2; await target.exists(); n++) {
      target = File(path('$stem-$n.gguf'));
    }
    return target;
  }

  Future<void> _move(File source, File target) async {
    try {
      await source.rename(target.path);
    } on FileSystemException {
      // Another file system: copy, then remove the picker's copy.
      await source.copy(target.path);
      await _deleteQuietly(source);
    }
  }

  Future<Map<String, Map<String, Object?>>> _readIndex() async => {
    for (final MapEntry(:key, :value) in (await _readJson(_index)).entries)
      if (value is Map) key: value.cast<String, Object?>(),
  };

  Future<void> _setIndex(String model, Map<String, Object?> values) async {
    final index = await _readIndex();
    final entry = {...?index[model], ...values}
      ..removeWhere((_, value) => value == null);
    if (entry.isEmpty) {
      index.remove(model);
    } else {
      index[model] = entry;
    }
    final temp = File('${_index.path}.tmp');
    await temp.writeAsString(jsonEncode(index), flush: true);
    await temp.rename(_index.path);
  }

  static Future<Map<String, Object?>> _readJson(File file) async {
    try {
      final value = jsonDecode(await file.readAsString());
      return value is Map<String, Object?> ? value : {};
    } on FileSystemException {
      return {};
    } on FormatException {
      return {};
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Already gone.
    }
  }
}

Future<GgufInfo> readGgufFile(File file) async {
  final handle = await file.open();
  try {
    return await readGgufInfo((offset, length) async {
      await handle.setPosition(offset);
      return handle.read(length);
    });
  } finally {
    await handle.close();
  }
}

/// HTTPS anywhere; plain HTTP only inside the local network.
bool downloadAllowed(Uri url) =>
    url.userInfo.isEmpty &&
    url.host.isNotEmpty &&
    (url.scheme == 'https' || url.scheme == 'http' && isLocalHost(url.host));

/// A file name safe in the model folder, ending in `.gguf`.
String safeModelName(String name) {
  var safe = p
      .basename(name.replaceAll('\\', '/'))
      .replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_')
      .trim();
  if (safe.startsWith('.')) safe = '_${safe.substring(1)}';
  if (!safe.toLowerCase().endsWith('.gguf')) safe = '$safe.gguf';
  if (safe.length > 120) safe = '${safe.substring(0, 115)}.gguf';
  return safe;
}
