import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../chat/content_block.dart';

class ToolLoop {
  const ToolLoop(this.period, this.tools);
  final int period;
  final List<String> tools;
  String get contextHint =>
      'You are stuck in a tool-use loop: the same '
      '$period-step sequence (${tools.join(', ')}) has repeated at least three '
      'times with unchanged results. Repeating it has been blocked. Stop this '
      'loop, explain what prevented progress, and suggest a different approach '
      'or ask the user for the missing information. Do not claim success.';
}

/// A bounded history of actual inputs AND outcomes. Changing outputs count as
/// progress even when the same read/poll/action is requested again.
class ToolLoopDetector {
  final _history = <({String call, String outcome, String name})>[];
  static const _maxPeriod = 8;

  void record(
    ToolCallBlock call,
    ToolResultBlock result, {
    List<ContentBlock>? attachments,
  }) {
    _history.add((
      call: _callKey(call),
      outcome: _hash({
        'content': _decoded(result.content), 'error': result.isError,
        // New image/file paths and side-effect receipts are evidence of progress.
        'attachments': [
          for (final b in attachments ?? result.attachments)
            if (b is ImageBlock && b.data != null)
              {'mimeType': b.mimeType, 'imageHash': _hash(b.data)}
            else
              b.toJson(),
        ],
        'effects': [for (final effect in result.sideEffects) effect.toJson()],
      }),
      name: call.name,
    ));
    if (_history.length > _maxPeriod * 3) _history.removeAt(0);
  }

  ToolLoop? repeatingBefore(ToolCallBlock next) {
    final nextKey = _callKey(next);
    for (var period = 1; period <= _maxPeriod; period++) {
      if (_history.length < period * 3) break;
      final start = _history.length - period * 3;
      var matches = true;
      for (var i = start + period; i < _history.length; i++) {
        final previous = _history[i - period];
        final current = _history[i];
        if (previous.call != current.call ||
            previous.outcome != current.outcome) {
          matches = false;
          break;
        }
      }
      if (matches && _history[_history.length - period].call == nextKey) {
        return ToolLoop(period, [
          for (final item in _history.skip(_history.length - period)) item.name,
        ]);
      }
    }
    return null;
  }

  String _callKey(ToolCallBlock call) {
    final args = _decoded(call.arguments);
    // Operation titles are display metadata; calendar titles are actual input.
    if (args is Map<String, Object?> &&
        const {
          'read_screen',
          'tap',
          'long_press',
          'type_text',
          'swipe',
          'scroll',
          'press_key',
          'open_app',
          'open_url',
        }.contains(call.name)) {
      args.remove('title');
    }
    return _hash({'name': call.name, 'args': args});
  }
}

Object? _decoded(String text) {
  try {
    return jsonDecode(text);
  } catch (_) {
    return text.trim();
  }
}

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => '$k').toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

String _hash(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(_canonical(value)))).toString();
