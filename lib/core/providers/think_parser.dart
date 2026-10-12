import 'provider_event.dart';

/// Splits local-model `<think>` tags even when their delimiters cross SSE frames.
class ThinkParser {
  String _buffer = '';
  bool _thinking = false;

  List<ProviderEvent> add(String text, {bool finish = false}) {
    _buffer += text;
    final result = <ProviderEvent>[];
    while (_buffer.isNotEmpty) {
      final tag = _thinking ? '</think>' : '<think>';
      final index = _buffer.indexOf(tag);
      if (index >= 0) {
        _emit(result, _buffer.substring(0, index));
        _buffer = _buffer.substring(index + tag.length);
        _thinking = !_thinking;
        continue;
      }
      var retained = 0;
      if (!finish) {
        for (
          var length = 1;
          length < tag.length && length <= _buffer.length;
          length++
        ) {
          if (_buffer.endsWith(tag.substring(0, length))) retained = length;
        }
      }
      _emit(result, _buffer.substring(0, _buffer.length - retained));
      _buffer = _buffer.substring(_buffer.length - retained);
      break;
    }
    return result;
  }

  void _emit(List<ProviderEvent> events, String text) {
    if (text.isEmpty) return;
    events.add(_thinking ? ReasoningDelta(text) : TextDelta(text));
  }
}
