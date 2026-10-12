import 'dart:convert';

class SseEvent {
  const SseEvent({required this.data, this.event, this.id});
  final String data;
  final String? event;
  final String? id;
}

/// UTF-8 decoding and line splitting retain their state across network chunks,
/// including split multibyte codepoints and split CRLF delimiters.
Stream<SseEvent> parseSse(Stream<List<int>> bytes) async* {
  var data = <String>[];
  String? event;
  String? id;
  var first = true;
  await for (var line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (first) {
      first = false;
      if (line.startsWith('\uFEFF')) line = line.substring(1);
    }
    if (line.isEmpty) {
      if (data.isNotEmpty) {
        yield SseEvent(data: data.join('\n'), event: event, id: id);
      }
      data = [];
      event = null;
      continue;
    }
    if (line.startsWith(':')) continue;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'data':
        data.add(value);
      case 'event':
        event = value;
      case 'id':
        if (!value.contains('\u0000')) id = value;
    }
  }
  // Some compatible servers close without the final blank line.
  if (data.isNotEmpty) {
    yield SseEvent(data: data.join('\n'), event: event, id: id);
  }
}
