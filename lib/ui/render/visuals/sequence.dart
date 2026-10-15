import 'dart:math' as math;
import 'dart:ui';

import 'mermaid.dart';
import 'visual_text.dart';

enum MessageHead { none, arrow, open, cross }

enum NotePlacement { left, right, over }

class Participant {
  const Participant(this.id, this.label, {this.actor = false});
  final String id;
  final String label;
  final bool actor;
}

sealed class SequenceEvent {
  const SequenceEvent();
}

class SequenceMessage extends SequenceEvent {
  const SequenceMessage(
    this.from,
    this.to,
    this.text, {
    this.dashed = false,
    this.head = MessageHead.arrow,
    this.both = false,
  });

  final int from;
  final int to;
  final String text;
  final bool dashed;
  final MessageHead head;
  final bool both;
}

class SequenceNote extends SequenceEvent {
  const SequenceNote(this.placement, this.first, this.last, this.text);
  final NotePlacement placement;
  final int first;
  final int last;
  final String text;
}

/// `loop`, `alt`, `opt`, `par`, `critical`, `break` or `rect`.
class SequenceBlockStart extends SequenceEvent {
  const SequenceBlockStart(this.kind, this.label);
  final String kind;
  final String label;
}

/// `else`, `and` or `option` inside a block.
class SequenceBlockDivider extends SequenceEvent {
  const SequenceBlockDivider(this.label);
  final String label;
}

class SequenceBlockEnd extends SequenceEvent {
  const SequenceBlockEnd();
}

final class SequenceDiagram extends MermaidDiagram {
  const SequenceDiagram({
    required this.participants,
    required this.events,
    this.autonumber = false,
    String? title,
  }) : super(title);

  final List<Participant> participants;
  final List<SequenceEvent> events;
  final bool autonumber;
}

const _arrows = <String, (bool, MessageHead, bool)>{
  '<<-->>': (true, MessageHead.arrow, true),
  '<<->>': (false, MessageHead.arrow, true),
  '-->>': (true, MessageHead.arrow, false),
  '->>': (false, MessageHead.arrow, false),
  '--x': (true, MessageHead.cross, false),
  '-x': (false, MessageHead.cross, false),
  '--)': (true, MessageHead.open, false),
  '-)': (false, MessageHead.open, false),
  '-->': (true, MessageHead.none, false),
  '->': (false, MessageHead.none, false),
};

final _message = RegExp(
  r'^(.+?)\s*(<<-->>|<<->>|-->>|->>|--x|-x|--\)|-\)|-->|->)\s*([+-]?)\s*([^:]+?)\s*(?::\s*(.*))?$',
);

SequenceDiagram parseSequence(List<String> lines, String? title) {
  final participants = <Participant>[];
  final ids = <String, int>{};
  final events = <SequenceEvent>[];
  // True for blocks that draw a frame; `box` only groups participants.
  final open = <bool>[];
  var autonumber = false;
  var heading = title;

  int participant(String raw, {String? label, bool actor = false}) {
    final id = raw.trim();
    var index = ids[id];
    if (index == null) {
      index = participants.length;
      ids[id] = index;
      participants.add(
        Participant(id, cleanMermaidText(label ?? id), actor: actor),
      );
    } else if (label != null || actor) {
      participants[index] = Participant(
        id,
        cleanMermaidText(label ?? participants[index].label),
        actor: actor || participants[index].actor,
      );
    }
    return index;
  }

  for (final raw in lines) {
    final line = raw.trim();
    final lower = line.toLowerCase();
    String rest(int length) => line.substring(length).trim();
    final declaration = RegExp(
      r'^(?:create\s+)?(participant|actor)\s+(.+?)(?:\s+as\s+(.+))?$',
      caseSensitive: false,
    ).firstMatch(line);
    if (declaration != null) {
      participant(
        cleanMermaidText(declaration[2]!),
        label: declaration[3],
        actor: declaration[1]!.toLowerCase() == 'actor',
      );
      continue;
    }
    if (lower == 'autonumber' || lower.startsWith('autonumber ')) {
      autonumber = true;
      continue;
    }
    if (lower.startsWith('title ') || lower.startsWith('title:')) {
      heading = cleanMermaidText(rest(6).replaceFirst(RegExp('^:'), ''));
      continue;
    }
    if (RegExp(
      r'^(activate|deactivate|destroy|acctitle|accdescr|links?|properties|details)\b',
    ).hasMatch(lower)) {
      continue;
    }
    final note = RegExp(
      r'^note\s+(left of|right of|over)\s+([^:]+?)\s*:\s*(.*)$',
      caseSensitive: false,
    ).firstMatch(line);
    if (note != null) {
      final placement = switch (note[1]!.toLowerCase()) {
        'left of' => NotePlacement.left,
        'right of' => NotePlacement.right,
        _ => NotePlacement.over,
      };
      final names = note[2]!.split(',');
      final first = participant(names.first);
      final last = names.length > 1 ? participant(names[1]) : first;
      events.add(
        SequenceNote(
          placement,
          math.min(first, last),
          math.max(first, last),
          cleanMermaidText(note[3]!),
        ),
      );
      continue;
    }
    final block = RegExp(
      r'^(loop|alt|opt|par|critical|break|rect|box)\b\s*(.*)$',
      caseSensitive: false,
    ).firstMatch(line);
    if (block != null) {
      final kind = block[1]!.toLowerCase();
      open.add(kind != 'box');
      if (kind != 'box') {
        events.add(
          SequenceBlockStart(
            kind,
            kind == 'rect' ? '' : cleanMermaidText(block[2]!),
          ),
        );
      }
      continue;
    }
    final divider = RegExp(
      r'^(else|and|option)\b\s*(.*)$',
      caseSensitive: false,
    ).firstMatch(line);
    if (divider != null) {
      if (open.isEmpty || !open.last) {
        throw const FormatException('A divider outside a block');
      }
      events.add(SequenceBlockDivider(cleanMermaidText(divider[2]!)));
      continue;
    }
    if (lower == 'end') {
      if (open.isEmpty) throw const FormatException('Unbalanced end');
      if (open.removeLast()) events.add(const SequenceBlockEnd());
      continue;
    }
    final message = _message.firstMatch(line);
    if (message != null) {
      final (dashed, head, both) = _arrows[message[2]!]!;
      events.add(
        SequenceMessage(
          participant(message[1]!.replaceFirst(RegExp(r'[+-]$'), '')),
          participant(message[4]!),
          cleanMermaidText(message[5] ?? ''),
          dashed: dashed,
          head: head,
          both: both,
        ),
      );
    }
  }
  if (open.isNotEmpty) throw const FormatException('Unclosed block');
  if (participants.isEmpty) {
    throw const FormatException('A sequence diagram needs participants');
  }
  if (participants.length > 30 || events.length > 400) {
    throw const FormatException('Sequence diagram is too large');
  }
  return SequenceDiagram(
    participants: List.unmodifiable(participants),
    events: List.unmodifiable(events),
    autonumber: autonumber,
    title: heading,
  );
}

// Layout

class PlacedParticipant {
  const PlacedParticipant(this.rect, this.label, {this.actor = false});
  final Rect rect;
  final String label;
  final bool actor;
}

class PlacedMessage {
  const PlacedMessage({
    required this.from,
    required this.to,
    required this.y,
    required this.text,
    required this.textTopLeft,
    required this.dashed,
    required this.head,
    required this.both,
    this.number,
  });

  /// Equal for a message to oneself, drawn as a loop to the right.
  final double from;
  final double to;
  final double y;
  final String text;
  final Offset textTopLeft;
  final bool dashed;
  final MessageHead head;
  final bool both;
  final int? number;

  bool get self => from == to;
}

class PlacedNote {
  const PlacedNote(this.rect, this.text);
  final Rect rect;
  final String text;
}

class PlacedFrame {
  const PlacedFrame(this.rect, this.kind, this.label, this.dividers);
  final Rect rect;
  final String kind;
  final String label;
  final List<(double, String)> dividers;
}

class SequenceLayout {
  const SequenceLayout({
    required this.size,
    required this.participantWidth,
    required this.messageWidth,
    required this.noteWidth,
    required this.participants,
    required this.lifelineTop,
    required this.lifelineBottom,
    required this.messages,
    required this.notes,
    required this.frames,
  });

  final Size size;
  final List<PlacedParticipant> participants;
  final double lifelineTop;
  final double lifelineBottom;
  final List<PlacedMessage> messages;
  final List<PlacedNote> notes;
  final List<PlacedFrame> frames;

  /// Wrap widths for participant, message and note labels.
  final double participantWidth;
  final double messageWidth;
  final double noteWidth;
}

class _OpenFrame {
  _OpenFrame(this.start, this.kind, this.label);
  final double start;
  final String kind;
  final String label;
  final dividers = <(double, String)>[];
  double left = double.infinity;
  double right = double.negativeInfinity;

  /// Frames nested inside this one, which its padding must clear.
  int nested = 0;
}

const participantLabelWidth = 140.0;
const messageLabelWidth = 180.0;
const noteLabelWidth = 160.0;

/// Labels wrap narrower when [fitWidth] is small, so the diagram stays
/// readable without scrolling sideways.
SequenceLayout layoutSequence(
  SequenceDiagram diagram,
  TextMeasurer text, {
  double? fitWidth,
}) {
  final count = diagram.participants.length;
  final number = diagram.autonumber ? 14.0 : 0.0;
  final participantWidth = fitWidth == null
      ? participantLabelWidth
      : ((fitWidth - 16) / count - 24).clamp(56.0, participantLabelWidth);
  final messageWidth = fitWidth == null || count < 2
      ? messageLabelWidth
      : ((fitWidth - 24) / (count - 1) - 24 - number).clamp(
          64.0,
          messageLabelWidth,
        );
  final noteWidth = fitWidth == null
      ? noteLabelWidth
      : (fitWidth * .6).clamp(100.0, noteLabelWidth);
  final labels = [
    for (final p in diagram.participants)
      text.measure(
        p.label,
        VisualTextRole.bodyStrong,
        maxWidth: participantWidth,
      ),
  ];
  final widths = [for (final s in labels) (s.width + 24).clamp(72.0, 180.0)];
  final actorHeight = diagram.participants.any((p) => p.actor) ? 26.0 : 0.0;
  final boxHeight = labels.map((s) => s.height).fold(0.0, math.max) + 16;

  Size measure(String value, double width) => value.isEmpty
      ? Size.zero
      : text.measure(value, VisualTextRole.caption, maxWidth: width);

  // Column gaps grow until every message and note fits, narrowest first.
  final gaps = [
    for (var i = 0; i + 1 < count; i++) (widths[i] + widths[i + 1]) / 2 + 20,
  ];
  var leftRoom = widths.first / 2 + 8;
  var rightRoom = widths.last / 2 + 8;
  final spans = <(int, int, double)>[];
  void needRight(int index, double room) {
    if (index + 1 < count) {
      gaps[index] = math.max(gaps[index], room);
    } else {
      rightRoom = math.max(rightRoom, room);
    }
  }

  void needLeft(int index, double room) {
    if (index > 0) {
      gaps[index - 1] = math.max(gaps[index - 1], room);
    } else {
      leftRoom = math.max(leftRoom, room);
    }
  }

  for (final event in diagram.events) {
    switch (event) {
      case SequenceMessage(:final from, :final to, text: final value):
        final size = measure(value, messageWidth);
        if (from == to) {
          needRight(from, 44 + size.width + 8);
        } else {
          spans.add((
            math.min(from, to),
            math.max(from, to),
            size.width + 24 + number,
          ));
        }
      case SequenceNote(:final placement, :final first, :final last):
        final size = measure(event.text, noteWidth);
        final width = size.width + 20;
        switch (placement) {
          case NotePlacement.right:
            needRight(first, width + 20);
          case NotePlacement.left:
            needLeft(first, width + 20);
          case NotePlacement.over when first == last:
            needLeft(first, width / 2 + 8);
            needRight(first, width / 2 + 8);
          case NotePlacement.over:
            spans.add((first, last, width - 40));
            needLeft(first, 28);
            needRight(last, 28);
        }
      default:
    }
  }
  spans.sort((a, b) => (a.$2 - a.$1).compareTo(b.$2 - b.$1));
  for (final (first, last, need) in spans) {
    var current = 0.0;
    for (var i = first; i < last; i++) {
      current += gaps[i];
    }
    if (current < need) {
      final extra = (need - current) / (last - first);
      for (var i = first; i < last; i++) {
        gaps[i] += extra;
      }
    }
  }
  final xs = <double>[leftRoom];
  for (final gap in gaps) {
    xs.add(xs.last + gap);
  }
  final width = xs.last + rightRoom;

  final top = actorHeight + boxHeight;
  final participants = [
    for (final (i, p) in diagram.participants.indexed)
      PlacedParticipant(
        Rect.fromLTWH(xs[i] - widths[i] / 2, actorHeight, widths[i], boxHeight),
        p.label,
        actor: p.actor,
      ),
  ];

  final messages = <PlacedMessage>[];
  final notes = <PlacedNote>[];
  final frames = <PlacedFrame>[];
  final stack = <_OpenFrame>[];
  final tag = text.measure('loop', VisualTextRole.captionStrong).height + 6;
  var y = top + 18;
  var counter = 0;
  // Every open frame grows to cover what is drawn inside it.
  void touch(double left, double right) {
    for (final frame in stack) {
      frame.left = math.min(frame.left, left);
      frame.right = math.max(frame.right, right);
    }
  }

  for (final event in diagram.events) {
    switch (event) {
      case SequenceMessage():
        final size = measure(event.text, messageWidth);
        final from = xs[event.from];
        final to = xs[event.to];
        counter++;
        if (event.from == event.to) {
          final labelTop = y;
          messages.add(
            PlacedMessage(
              from: from,
              to: to,
              y: y + 4,
              text: event.text,
              textTopLeft: Offset(from + 40, labelTop),
              dashed: event.dashed,
              head: event.head,
              both: event.both,
              number: diagram.autonumber ? counter : null,
            ),
          );
          touch(from - 10, from + 40 + size.width);
          y += math.max(size.height, 26) + 18;
        } else {
          y += size.height + 4;
          final left = math.min(from, to);
          final right = math.max(from, to);
          final middle = (left + right) / 2 + (diagram.autonumber ? 6 : 0);
          messages.add(
            PlacedMessage(
              from: from,
              to: to,
              y: y,
              text: event.text,
              textTopLeft: Offset(middle - size.width / 2, y - size.height - 4),
              dashed: event.dashed,
              head: event.head,
              both: event.both,
              number: diagram.autonumber ? counter : null,
            ),
          );
          touch(left - 10, right + 10);
          y += 20;
        }
      case SequenceNote():
        final size = measure(event.text, noteWidth);
        final noteWidthOuter = size.width + 20;
        final height = size.height + 12;
        final first = xs[event.first];
        final last = xs[event.last];
        final span = math.max(last - first + 40, noteWidthOuter);
        final rect = switch (event.placement) {
          NotePlacement.right => Rect.fromLTWH(
            first + 12,
            y,
            noteWidthOuter,
            height,
          ),
          NotePlacement.left => Rect.fromLTWH(
            first - 12 - noteWidthOuter,
            y,
            noteWidthOuter,
            height,
          ),
          NotePlacement.over => Rect.fromLTWH(
            (first + last) / 2 - span / 2,
            y,
            span,
            height,
          ),
        };
        notes.add(PlacedNote(rect, event.text));
        touch(rect.left, rect.right);
        y += height + 14;
      case SequenceBlockStart():
        y += 4;
        stack.add(_OpenFrame(y, event.kind, event.label));
        y += (event.kind == 'rect' ? 8 : tag) + 12;
      case SequenceBlockDivider():
        y += 4;
        stack.last.dividers.add((y, event.label));
        y += tag + 10;
      case SequenceBlockEnd():
        y += 4;
        final frame = stack.removeLast();
        if (stack.isNotEmpty) {
          stack.last.nested = math.max(stack.last.nested, frame.nested + 1);
        }
        final pad = 12.0 + 6 * frame.nested;
        final left = frame.left.isFinite
            ? frame.left - pad
            : xs.first - widths.first / 2;
        final right = frame.right.isFinite
            ? frame.right + pad
            : xs.last + widths.last / 2;
        frames.add(
          PlacedFrame(
            Rect.fromLTRB(left, frame.start, right, y),
            frame.kind,
            frame.label,
            frame.dividers,
          ),
        );
        touch(left - 6, right + 6);
        y += 12;
    }
  }
  final bottom = y + 4;
  // Frames and notes may reach past the outer columns.
  var minX = 0.0;
  var maxX = width;
  for (final rect in [
    ...frames.map((f) => f.rect),
    ...notes.map((n) => n.rect),
  ]) {
    minX = math.min(minX, rect.left - 4);
    maxX = math.max(maxX, rect.right + 4);
  }
  for (final message in messages.where((m) => m.self)) {
    maxX = math.max(
      maxX,
      message.textTopLeft.dx + measure(message.text, messageWidth).width + 4,
    );
  }
  final shift = Offset(-minX, 0);
  return SequenceLayout(
    size: Size(maxX - minX, bottom),
    participantWidth: participantWidth,
    messageWidth: messageWidth,
    noteWidth: noteWidth,
    participants: [
      for (final p in participants)
        PlacedParticipant(p.rect.shift(shift), p.label, actor: p.actor),
    ],
    lifelineTop: top,
    lifelineBottom: bottom,
    messages: [
      for (final m in messages)
        PlacedMessage(
          from: m.from + shift.dx,
          to: m.to + shift.dx,
          y: m.y,
          text: m.text,
          textTopLeft: m.textTopLeft + shift,
          dashed: m.dashed,
          head: m.head,
          both: m.both,
          number: m.number,
        ),
    ],
    notes: [for (final n in notes) PlacedNote(n.rect.shift(shift), n.text)],
    frames: [
      for (final f in frames)
        PlacedFrame(f.rect.shift(shift), f.kind, f.label, f.dividers),
    ],
  );
}
