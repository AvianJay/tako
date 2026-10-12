import 'dart:convert';
import 'dart:typed_data';

/// What Tako needs from a GGUF file, read from its metadata without loading
/// the model.
class GgufInfo {
  const GgufInfo({
    required this.architecture,
    this.type,
    this.name,
    this.contextLength,
    this.chatTemplate,
  });

  /// `general.architecture`, e.g. `qwen35`, `gemma4`, or `clip` for a vision
  /// projector.
  final String architecture;

  /// `general.type`: `model`, or `mmproj` for a projector.
  final String? type;
  final String? name;

  /// The context the model was trained for.
  final int? contextLength;
  final String? chatTemplate;

  bool get isProjector => architecture == 'clip' || type == 'mmproj';

  /// The chat template renders tool definitions.
  bool get supportsTools => chatTemplate?.contains('tools') ?? false;

  /// The chat template has a thinking mode.
  bool get supportsThinking => [
    'enable_thinking',
    '<think>',
    'reasoning_content',
  ].any((marker) => chatTemplate?.contains(marker) ?? false);
}

class GgufFormatException extends FormatException {
  const GgufFormatException(super.message);
}

/// Reads up to [length] bytes at [offset]; fewer only at the end of the file.
typedef GgufReader = Future<Uint8List> Function(int offset, int length);

/// Reads GGUF v2 or v3 metadata. Large arrays such as the tokenizer's
/// vocabulary are skipped, and nothing past the metadata is read.
Future<GgufInfo> readGgufInfo(GgufReader read) async {
  final cursor = _Cursor(read);
  if (await cursor.bytes(4) case final magic
      when ascii.decode(magic, allowInvalid: true) != 'GGUF') {
    throw const GgufFormatException('not_gguf');
  }
  final version = await cursor.u32();
  if (version < 2 || version > 3) {
    throw const GgufFormatException('unsupported_gguf_version');
  }
  await cursor.u64(); // tensor count
  final count = await cursor.u64();
  if (count > _maxEntries) throw const GgufFormatException('invalid_gguf');
  final values = <String, Object?>{};
  for (var i = 0; i < count; i++) {
    final key = await cursor.string(_maxKeyBytes);
    final type = await cursor.u32();
    if (_wanted(key)) {
      values[key] = await cursor.value(type, _maxTemplateBytes);
    } else {
      await cursor.skip(type);
    }
  }
  final architecture = values['general.architecture'];
  if (architecture is! String || architecture.isEmpty) {
    throw const GgufFormatException('invalid_gguf');
  }
  final context = values['$architecture.context_length'];
  return GgufInfo(
    architecture: architecture,
    type: values['general.type'] as String?,
    name: values['general.name'] as String?,
    contextLength: context is int && context > 0 ? context : null,
    chatTemplate: values['tokenizer.chat_template'] as String?,
  );
}

const _maxEntries = 1 << 16;
const _maxKeyBytes = 1 << 16;
const _maxTemplateBytes = 1 << 20;
const _maxArrayLength = 1 << 24;

/// Metadata larger than this is not a model Tako can run.
const _maxMetadataBytes = 256 << 20;

bool _wanted(String key) =>
    key.startsWith('general.') ||
    key.endsWith('.context_length') ||
    key == 'tokenizer.chat_template';

class _Cursor {
  _Cursor(this._read);
  final GgufReader _read;
  static const _block = 1 << 16;
  Uint8List _buffer = Uint8List(0);
  int _bufferStart = 0;
  int _position = 0;

  Future<Uint8List> bytes(int length) async {
    if (_position + length > _maxMetadataBytes) {
      throw const GgufFormatException('invalid_gguf');
    }
    final end = _bufferStart + _buffer.length;
    if (_position < _bufferStart || _position + length > end) {
      _bufferStart = _position;
      _buffer = await _read(_position, length > _block ? length : _block);
      if (_buffer.length < length) {
        throw const GgufFormatException('truncated_gguf');
      }
    }
    final start = _position - _bufferStart;
    _position += length;
    return Uint8List.sublistView(_buffer, start, start + length);
  }

  Future<ByteData> _data(int length) async =>
      ByteData.sublistView(await bytes(length));

  Future<int> u32() async => (await _data(4)).getUint32(0, Endian.little);

  Future<int> u64() async {
    final value = (await _data(8)).getUint64(0, Endian.little);
    // Larger values do not fit Dart's int and no valid file needs them.
    if (value < 0) throw const GgufFormatException('invalid_gguf');
    return value;
  }

  Future<String> string(int maxBytes) async {
    final length = await u64();
    if (length > maxBytes) throw const GgufFormatException('invalid_gguf');
    return utf8.decode(await bytes(length), allowMalformed: true);
  }

  Future<void> _skipString() async {
    final length = await u64();
    if (_position + length > _maxMetadataBytes) {
      throw const GgufFormatException('invalid_gguf');
    }
    _position += length;
  }

  Future<Object?> value(int type, int maxString) async {
    switch (type) {
      case 0:
        return (await bytes(1))[0];
      case 1:
        return (await _data(1)).getInt8(0);
      case 2:
        return (await _data(2)).getUint16(0, Endian.little);
      case 3:
        return (await _data(2)).getInt16(0, Endian.little);
      case 4:
        return u32();
      case 5:
        return (await _data(4)).getInt32(0, Endian.little);
      case 6:
        return (await _data(4)).getFloat32(0, Endian.little);
      case 7:
        return (await bytes(1))[0] != 0;
      case 8:
        return string(maxString);
      case 9:
        await skip(type);
        return null;
      case 10:
        return u64();
      case 11:
        return (await _data(8)).getInt64(0, Endian.little);
      case 12:
        return (await _data(8)).getFloat64(0, Endian.little);
    }
    throw const GgufFormatException('invalid_gguf');
  }

  Future<void> skip(int type) async {
    if (type == 8) return _skipString();
    if (type == 9) {
      final itemType = await u32();
      final length = await u64();
      if (length > _maxArrayLength) {
        throw const GgufFormatException('invalid_gguf');
      }
      if (itemType == 8 || itemType == 9) {
        for (var i = 0; i < length; i++) {
          await skip(itemType);
        }
        return;
      }
      final size = _sizes[itemType];
      if (size == null) throw const GgufFormatException('invalid_gguf');
      _position += size * length;
      if (_position > _maxMetadataBytes) {
        throw const GgufFormatException('invalid_gguf');
      }
      return;
    }
    final size = _sizes[type];
    if (size == null) throw const GgufFormatException('invalid_gguf');
    _position += size;
  }

  static const _sizes = {
    0: 1,
    1: 1,
    2: 2,
    3: 2,
    4: 4,
    5: 4,
    6: 4,
    7: 1,
    10: 8,
    11: 8,
    12: 8,
  };
}
