import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Only newly appended glyphs fade in; existing text never dims or replays.
/// Parsing is owned by MessageMarkdown. Animation changes span paint only.
class RevealingText extends StatefulWidget {
  const RevealingText({
    required this.span,
    required this.streaming,
    this.style,
    super.key,
  });
  final TextSpan span;
  final bool streaming;
  final TextStyle? style;
  @override
  State<RevealingText> createState() => _RevealingTextState();
}

class _Reveal {
  const _Reveal(this.start, this.end, this.at);
  final int start;
  final int end;
  final int at;
}

class _RevealingTextState extends State<RevealingText>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 220);
  final _clock = Stopwatch()..start();
  final _ranges = <_Reveal>[];
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: _duration,
  );
  late String _text;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _text = widget.span.toPlainText();
    if (widget.streaming && _text.isNotEmpty) {
      _ranges.add(_Reveal(0, _text.length, _clock.elapsedMilliseconds));
      _animation.forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced) {
      _ranges.clear();
      _animation.stop();
    }
  }

  @override
  void didUpdateWidget(covariant RevealingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.span.toPlainText();
    if (next != _text) {
      if ((widget.streaming || oldWidget.streaming) &&
          !_reduced &&
          next.startsWith(_text)) {
        _ranges.removeWhere(
          (range) =>
              _clock.elapsedMilliseconds - range.at >= _duration.inMilliseconds,
        );
        _ranges.add(
          _Reveal(_text.length, next.length, _clock.elapsedMilliseconds),
        );
        _animation.forward(from: 0);
      } else {
        _ranges.clear();
        _animation.stop();
      }
      _text = next;
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _clock.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animation,
    builder: (context, child) {
      if (_ranges.isEmpty || _reduced || _animation.isCompleted) {
        return Text.rich(widget.span, style: widget.style, softWrap: true);
      }
      final base = DefaultTextStyle.of(context).style.merge(widget.style);
      var offset = 0;
      InlineSpan paint(
        InlineSpan span,
        TextStyle inherited,
        GestureRecognizer? recognizer,
      ) {
        if (span is! TextSpan) {
          offset++;
          return span;
        }
        final effective = inherited.merge(span.style);
        final tap = span.recognizer ?? recognizer;
        final pieces = <InlineSpan>[];
        final text = span.text ?? '';
        var local = 0;
        for (final range in _ranges) {
          final start = (range.start - offset).clamp(0, text.length);
          final end = (range.end - offset).clamp(0, text.length);
          if (end <= start) continue;
          if (start > local) {
            pieces.add(
              TextSpan(text: text.substring(local, start), recognizer: tap),
            );
          }
          final progress =
              ((_clock.elapsedMilliseconds - range.at) /
                      _duration.inMilliseconds)
                  .clamp(0.0, 1.0);
          final color =
              effective.color ?? Theme.of(context).colorScheme.onSurface;
          pieces.add(
            TextSpan(
              text: text.substring(start, end),
              recognizer: tap,
              style: TextStyle(
                color: color.withValues(
                  alpha:
                      color.a *
                      (.15 + .85 * Curves.easeOut.transform(progress)),
                ),
              ),
            ),
          );
          local = end;
        }
        if (local < text.length) {
          pieces.add(TextSpan(text: text.substring(local), recognizer: tap));
        }
        offset += text.length;
        for (final child in span.children ?? const <InlineSpan>[]) {
          pieces.add(paint(child, effective, tap));
        }
        return TextSpan(
          style: span.style,
          children: pieces,
          recognizer: tap,
          semanticsLabel: span.semanticsLabel,
        );
      }

      return Text.rich(
        paint(widget.span, base, null),
        style: widget.style,
        softWrap: true,
      );
    },
  );
}
