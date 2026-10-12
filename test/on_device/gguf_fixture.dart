import 'dart:convert';
import 'dart:typed_data';

const qwenTemplate =
    '{%- if tools %}<tools>{{ tools }}</tools>{%- endif %}'
    '{%- if enable_thinking %}<think>{%- endif %}';

/// A small GGUF file: metadata, a vocabulary to skip, and filler tensor data.
Uint8List ggufBytes({
  String architecture = 'qwen35',
  String? type,
  String? name = 'Fixture Model',
  int? context = 262144,
  String? template = qwenTemplate,
  int vocabulary = 3000,
  int version = 3,
}) {
  final out = BytesBuilder();
  void u32(int value) => out.add(
    (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List(),
  );
  void u64(int value) => out.add(
    (ByteData(8)..setUint64(0, value, Endian.little)).buffer.asUint8List(),
  );
  void string(String value) {
    final bytes = utf8.encode(value);
    u64(bytes.length);
    out.add(bytes);
  }

  final entries = <void Function()>[];
  void entry(String key, int valueType, void Function() value) =>
      entries.add(() {
        string(key);
        u32(valueType);
        value();
      });
  entry('general.architecture', 8, () => string(architecture));
  if (type != null) entry('general.type', 8, () => string(type));
  if (name != null) entry('general.name', 8, () => string(name));
  if (context != null) {
    entry('$architecture.context_length', 4, () => u32(context));
  }
  if (vocabulary > 0) {
    entry('tokenizer.ggml.tokens', 9, () {
      u32(8);
      u64(vocabulary);
      for (var i = 0; i < vocabulary; i++) {
        string('token$i');
      }
    });
    entry('tokenizer.ggml.scores', 9, () {
      u32(6);
      u64(vocabulary);
      out.add(Uint8List(4 * vocabulary));
    });
  }
  if (template != null) {
    entry('tokenizer.chat_template', 8, () => string(template));
  }
  out.add(ascii.encode('GGUF'));
  u32(version);
  u64(0);
  u64(entries.length);
  for (final write in entries) {
    write();
  }
  out.add(Uint8List(256));
  return out.toBytes();
}

Uint8List projectorBytes() => ggufBytes(
  architecture: 'clip',
  type: 'mmproj',
  name: 'Fixture Projector',
  context: null,
  template: null,
  vocabulary: 0,
);
