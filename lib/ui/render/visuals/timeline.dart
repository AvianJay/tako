import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'cards.dart';
import 'mermaid.dart';
import 'visual_labels.dart';

/// Where an event stands in a plan. Events without one are drawn plainly.
enum TimelineStatus { done, current, upcoming }

class TimelineItem {
  const TimelineItem({
    this.time,
    this.icon,
    this.title,
    this.text,
    this.status,
    this.section,
  });

  /// Free text such as `09:00`, `Day 2` or `2026-11-03`.
  final String? time;
  final String? icon;
  final String? title;
  final String? text;
  final TimelineStatus? status;

  /// Consecutive events in the same section are grouped under its name.
  final String? section;
}

/// Model-authored timelines for itineraries, schedules, recipes and plans: a
/// JSON array of events, or an object with a `title` and `items`. An entry
/// with its own `items` is a section, such as one day of a trip.
class TimelineSpec {
  const TimelineSpec(this.title, this.items);

  factory TimelineSpec.parse(String source) {
    final decoded = jsonDecode(source);
    String? title;
    var entries = decoded;
    if (decoded is Map) {
      final map = decoded.cast<String, Object?>();
      title = specField(map, const ['title', 'heading', 'name']);
      entries = _events(map);
    }
    if (entries is! List) {
      throw const FormatException('A timeline is a list of events');
    }
    final items = <TimelineItem>[];
    void add(Object? entry, String? section) {
      if (_item(entry, section) case final item?) items.add(item);
      if (items.length > maxItems) {
        throw const FormatException('A timeline has at most 60 events');
      }
    }

    for (final entry in entries) {
      if (entry is Map && _events(entry.cast()) is List) {
        final map = entry.cast<String, Object?>();
        final section = specField(map, const [
          'section',
          'group',
          'title',
          'name',
          'label',
          'heading',
          'day',
          'date',
          'time',
        ]);
        for (final event in _events(map)! as List) {
          add(event, section);
        }
      } else {
        add(entry, null);
      }
    }
    if (items.isEmpty) throw const FormatException('A timeline needs events');
    if (items.any((item) => item.title == null && item.text == null)) {
      throw const FormatException('Every event needs a title or text');
    }
    return TimelineSpec(title, List.unmodifiable(items));
  }

  static const maxItems = 60;

  final String? title;
  final List<TimelineItem> items;
}

Object? _events(Map<String, Object?> map) =>
    map['items'] ??
    map['events'] ??
    map['steps'] ??
    map['entries'] ??
    map['timeline'];

TimelineItem? _item(Object? entry, String? section) {
  if (entry is String) {
    final title = entry.trim();
    return title.isEmpty
        ? null
        : TimelineItem(
            title: title.length > 600 ? '${title.substring(0, 600)}…' : title,
            section: section,
          );
  }
  if (entry is! Map) return null;
  final map = entry.cast<String, Object?>();
  var time = specField(map, const [
    'time',
    'date',
    'when',
    'at',
    'day',
    'year',
    'period',
  ]);
  if (time == null) {
    final start = specField(map, const ['start', 'from', 'begin']);
    final end = specField(map, const ['end', 'to', 'until']);
    time = start == null || end == null ? start ?? end : '$start–$end';
  }
  return TimelineItem(
    time: time,
    icon: specField(map, const ['icon', 'emoji']),
    title: specField(map, const [
      'title',
      'name',
      'label',
      'heading',
      'event',
      'summary',
    ]),
    text: specField(map, const [
      'text',
      'description',
      'desc',
      'body',
      'detail',
      'details',
      'content',
      'note',
      'notes',
    ]),
    status: _status(map),
    section: specField(map, const ['section', 'group']) ?? section,
  );
}

TimelineStatus? _status(Map<String, Object?> map) {
  if (specField(map, const ['status', 'state', 'progress']) case final word?) {
    return _statuses[word.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), ' ')];
  }
  bool flag(List<String> names) => names.any((name) => map[name] == true);
  if (flag(const ['done', 'completed', 'complete'])) return TimelineStatus.done;
  if (flag(const ['current', 'active', 'now'])) return TimelineStatus.current;
  return null;
}

const _statuses = {
  'done': TimelineStatus.done,
  'complete': TimelineStatus.done,
  'completed': TimelineStatus.done,
  'finished': TimelineStatus.done,
  'past': TimelineStatus.done,
  'passed': TimelineStatus.done,
  'checked': TimelineStatus.done,
  'success': TimelineStatus.done,
  '✓': TimelineStatus.done,
  '✅': TimelineStatus.done,
  '完成': TimelineStatus.done,
  '已完成': TimelineStatus.done,
  'current': TimelineStatus.current,
  'active': TimelineStatus.current,
  'now': TimelineStatus.current,
  'in progress': TimelineStatus.current,
  'inprogress': TimelineStatus.current,
  'ongoing': TimelineStatus.current,
  'doing': TimelineStatus.current,
  'started': TimelineStatus.current,
  'running': TimelineStatus.current,
  'live': TimelineStatus.current,
  'today': TimelineStatus.current,
  'wip': TimelineStatus.current,
  '進行中': TimelineStatus.current,
  '进行中': TimelineStatus.current,
  '目前': TimelineStatus.current,
  '当前': TimelineStatus.current,
  'upcoming': TimelineStatus.upcoming,
  'pending': TimelineStatus.upcoming,
  'todo': TimelineStatus.upcoming,
  'to do': TimelineStatus.upcoming,
  'planned': TimelineStatus.upcoming,
  'future': TimelineStatus.upcoming,
  'next': TimelineStatus.upcoming,
  'later': TimelineStatus.upcoming,
  'scheduled': TimelineStatus.upcoming,
  'waiting': TimelineStatus.upcoming,
  'queued': TimelineStatus.upcoming,
  'not started': TimelineStatus.upcoming,
  '待辦': TimelineStatus.upcoming,
  '待办': TimelineStatus.upcoming,
  '未開始': TimelineStatus.upcoming,
  '未开始': TimelineStatus.upcoming,
};

/// A Mermaid `timeline`: periods with their events, grouped by `section`.
final class TimelineDiagram extends MermaidDiagram {
  const TimelineDiagram(this.items, {String? title}) : super(title);
  final List<TimelineItem> items;
}

/// Events follow their period after `: `, and a line that starts with `:`
/// adds events to the period above. A colon inside a time such as `09:30`
/// stays part of the text.
TimelineDiagram parseTimeline(List<String> lines, String? title) {
  var heading = title;
  String? section;
  final periods = <(String, List<String>, String?)>[];
  List<String> events(Iterable<String> parts) => [
    for (final part in parts)
      if (cleanMermaidText(part) case final event when event.isNotEmpty) event,
  ];
  for (final raw in lines) {
    final line = raw.trim();
    final keyword = RegExp(r'^[A-Za-z]+').firstMatch(line)?[0]?.toLowerCase();
    final rest = keyword == null ? '' : line.substring(keyword.length);
    if (keyword == 'title' && RegExp(r'^(?:\s|:|$)').hasMatch(rest)) {
      heading = cleanMermaidText(rest.replaceFirst(RegExp(r'^\s*:'), ''));
      continue;
    }
    if (keyword == 'section' && RegExp(r'^(?:\s|$)').hasMatch(rest)) {
      section = cleanMermaidText(rest);
      if (section.isEmpty) section = null;
      continue;
    }
    if (keyword == 'acctitle' || keyword == 'accdescr') continue;
    if (line.startsWith(':')) {
      if (periods.isEmpty) {
        throw const FormatException('An event needs a period');
      }
      periods.last.$2.addAll(events(line.substring(1).split(_eventColon)));
      continue;
    }
    final parts = line.split(_eventColon);
    final period = cleanMermaidText(parts.first);
    if (period.isEmpty) continue;
    periods.add((period, events(parts.skip(1)), section));
    if (periods.length > TimelineSpec.maxItems) {
      throw const FormatException('Timeline is too large');
    }
  }
  if (periods.isEmpty) throw const FormatException('A timeline needs events');
  return TimelineDiagram(
    List.unmodifiable([
      for (final (period, events, section) in periods)
        events.isEmpty
            ? TimelineItem(title: period, section: section)
            : TimelineItem(
                time: period,
                title: events.join('\n'),
                section: section,
              ),
    ]),
    title: heading == null || heading.isEmpty ? null : heading,
  );
}

final _eventColon = RegExp(r'\s*:(?=\s|$)\s*');

/// An event with its Markdown fields already rendered as inline spans.
class TimelineContent {
  const TimelineContent({
    this.time,
    this.icon,
    this.title,
    this.text,
    this.status,
    this.section,
  });

  /// An event shown as plain text, such as one read from Mermaid.
  factory TimelineContent.plain(TimelineItem item) => TimelineContent(
    time: item.time,
    icon: item.icon,
    title: item.title == null ? null : TextSpan(text: item.title),
    text: item.text == null ? null : TextSpan(text: item.text),
    status: item.status,
    section: item.section,
  );

  final String? time;
  final String? icon;
  final InlineSpan? title;
  final InlineSpan? text;
  final TimelineStatus? status;
  final String? section;
}

/// A vertical rail of events. Short times get a column of their own; long
/// times, and times on narrow screens, sit above their titles instead.
class TimelineView extends StatelessWidget {
  const TimelineView({
    required this.items,
    this.title,
    this.labels = const VisualLabels(),
    this.padding = const EdgeInsets.only(bottom: 8),
    super.key,
  });

  final InlineSpan? title;
  final List<TimelineContent> items;

  /// Status names for screen readers.
  final VisualLabels labels;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title case final title?)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text.rich(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) => _events(
              context,
              constraints.maxWidth.isFinite ? constraints.maxWidth : 480,
            ),
          ),
        ],
      ),
    );
  }

  Widget _events(BuildContext context, double width) {
    final metrics = _Metrics.of(context, items, width);
    final children = <Widget>[];
    for (var start = 0, end = 0; start < items.length; start = end) {
      end = start + 1;
      while (end < items.length && items[end].section == items[start].section) {
        end++;
      }
      if (items[start].section case final section?) {
        children.add(
          Padding(
            padding: EdgeInsets.only(top: start == 0 ? 0 : 22, bottom: 12),
            child: Semantics(
              header: true,
              child: Text(section, style: metrics.section),
            ),
          ),
        );
      }
      for (var i = start; i < end; i++) {
        children.add(
          _Event(
            item: items[i],
            metrics: metrics,
            first: i == start,
            last: i == end - 1,
            labels: labels,
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

/// Text styles and the geometry every row of one timeline shares.
class _Metrics {
  const _Metrics({
    required this.time,
    required this.currentTime,
    required this.title,
    required this.doneTitle,
    required this.text,
    required this.section,
    required this.timeWidth,
    required this.rail,
    required this.timeLine,
    required this.titleLine,
    required this.textLine,
  });

  factory _Metrics.of(
    BuildContext context,
    List<TimelineContent> items,
    double width,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    final bold = MediaQuery.boldTextOf(context);
    TextStyle timeStyle(TextStyle? style) =>
        (style ?? const TextStyle()).copyWith(
          color: scheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    final columnTime = timeStyle(textTheme.labelLarge);
    final title = (textTheme.titleSmall ?? const TextStyle()).copyWith(
      fontWeight: FontWeight.w600,
    );
    final text = (textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: scheme.onSurfaceVariant,
    );
    Size measure(String value, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: base
              .merge(style)
              .copyWith(fontWeight: bold ? FontWeight.bold : null),
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final size = painter.size;
      painter.dispose();
      return size;
    }

    // Times are measured in the current event's heavier weight, so any of
    // them fits the column.
    final times = [for (final item in items) ?item.time];
    final widest = times.fold(
      0.0,
      (widest, time) => math.max(
        widest,
        measure(time, columnTime.copyWith(fontWeight: FontWeight.w700)).width,
      ),
    );
    final column =
        times.isNotEmpty &&
        !times.any((time) => time.contains('\n')) &&
        widest <= math.min(width * .3, 132);
    // A time above its title is a smaller kicker line.
    final time = column ? columnTime : timeStyle(textTheme.labelMedium);
    final currentTime = time.copyWith(
      color: scheme.primary,
      fontWeight: FontWeight.w700,
    );
    final iconic = items.any((item) => _glyph(item.icon) != null);
    return _Metrics(
      time: time,
      currentTime: currentTime,
      title: title,
      doneTitle: title.copyWith(color: scheme.onSurfaceVariant),
      text: text,
      section: (textTheme.titleSmall ?? const TextStyle()).copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
      ),
      timeWidth: column ? widest.ceilToDouble() + 1 : 0,
      rail: iconic ? 32 : 20,
      timeLine: measure('Ag', time).height,
      titleLine: measure('Ag', title).height,
      textLine: measure('Ag', text).height,
    );
  }

  final TextStyle time;
  final TextStyle currentTime;
  final TextStyle title;
  final TextStyle doneTitle;
  final TextStyle text;
  final TextStyle section;

  /// The time column's width, or 0 when times sit above titles.
  final double timeWidth;

  /// The rail column's width: room for an icon, or for a dot.
  final double rail;
  final double timeLine;
  final double titleLine;
  final double textLine;

  static const gap = 12.0;
}

class _Event extends StatelessWidget {
  const _Event({
    required this.item,
    required this.metrics,
    required this.first,
    required this.last,
    required this.labels,
  });

  final TimelineContent item;
  final _Metrics metrics;
  final bool first;
  final bool last;
  final VisualLabels labels;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final scheme = Theme.of(context).colorScheme;
    final current = item.status == TimelineStatus.current;
    final done = item.status == TimelineStatus.done;
    final time = item.time;
    final timeAbove = m.timeWidth == 0 && time != null;
    final firstLine = timeAbove
        ? m.timeLine
        : item.title != null || item.text == null
        ? m.titleLine
        : m.textLine;
    // The node sits on the first line of text, whatever its size.
    final middle = math.max(m.rail, firstLine) / 2;
    final railX =
        (m.timeWidth > 0 ? m.timeWidth + _Metrics.gap : 0) + m.rail / 2;
    final timeStyle = current ? m.currentTime : m.time;
    final status = switch (item.status) {
      TimelineStatus.done => labels.done,
      TimelineStatus.current => labels.inProgress,
      TimelineStatus.upcoming => labels.upcoming,
      null => null,
    };
    final line = ColoredBox(color: scheme.outlineVariant);
    return MergeSemantics(
      child: Stack(
        children: [
          if (!first)
            Positioned(
              left: railX - 1,
              width: 2,
              top: 0,
              height: middle,
              child: line,
            ),
          if (!last)
            Positioned(
              left: railX - 1,
              width: 2,
              top: middle,
              bottom: 0,
              child: line,
            ),
          Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (m.timeWidth > 0) ...[
                  SizedBox(
                    width: m.timeWidth,
                    child: time == null
                        ? null
                        : Padding(
                            padding: EdgeInsets.only(
                              top: math.max(0, middle - m.timeLine / 2),
                            ),
                            child: Text(
                              time,
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.visible,
                              style: timeStyle,
                            ),
                          ),
                  ),
                  const SizedBox(width: _Metrics.gap),
                ],
                SizedBox(
                  width: m.rail,
                  height: middle * 2,
                  child: Center(
                    child: Semantics(
                      label: status,
                      child: ExcludeSemantics(
                        child: _Node(
                          status: item.status,
                          icon: item.icon,
                          size: m.rail,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: _Metrics.gap),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: math.max(0, middle - firstLine / 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (timeAbove)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(time, style: timeStyle),
                          ),
                        if (item.title case final title?)
                          Text.rich(title, style: done ? m.doneTitle : m.title),
                        if (item.text case final text?)
                          Padding(
                            padding: EdgeInsets.only(
                              top: item.title == null && !timeAbove ? 0 : 2,
                            ),
                            child: Text.rich(text, style: m.text),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A Material icon or an emoji for an event, or null for a plain dot.
Object? _glyph(String? icon) {
  final name = icon?.trim() ?? '';
  if (name.isEmpty) return null;
  return cardIconData(name) ?? cardEmoji(name);
}

/// The mark on the rail: a dot, or a round icon when the event has one. Done
/// events are quieter and carry a check; the current one takes the theme's
/// primary colour and a halo.
class _Node extends StatelessWidget {
  const _Node({required this.status, required this.icon, required this.size});

  final TimelineStatus? status;
  final String? icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final surface = theme.scaffoldBackgroundColor;
    final halo = [
      BoxShadow(color: scheme.primary.withValues(alpha: .2), spreadRadius: 4),
    ];
    final glyph = _glyph(icon);
    if (glyph == null) {
      return switch (status) {
        TimelineStatus.done => Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.check, size: 12, color: scheme.onSurfaceVariant),
        ),
        TimelineStatus.current => Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: scheme.primary,
            shape: BoxShape.circle,
            boxShadow: halo,
          ),
        ),
        TimelineStatus.upcoming => Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: surface,
            shape: BoxShape.circle,
            border: Border.all(color: scheme.outline, width: 2),
          ),
        ),
        null => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: scheme.primary,
            shape: BoxShape.circle,
          ),
        ),
      };
    }
    final (fill, ink) = switch (status) {
      TimelineStatus.current => (scheme.primary, scheme.onPrimary),
      TimelineStatus.upcoming => (surface, scheme.onSurfaceVariant),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    final circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: status == TimelineStatus.upcoming
            ? Border.all(color: scheme.outlineVariant, width: 1.5)
            : null,
        boxShadow: status == TimelineStatus.current ? halo : null,
      ),
      alignment: Alignment.center,
      child: glyph is IconData
          ? Icon(glyph, size: size * .5, color: ink)
          : Text(
              glyph as String,
              textScaler: TextScaler.noScaling,
              style: TextStyle(fontSize: size * .46, color: ink),
            ),
    );
    if (status != TimelineStatus.done) return circle;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Opacity(opacity: .55, child: circle),
        Positioned(
          right: -4,
          bottom: -4,
          child: Container(
            width: 17,
            height: 17,
            decoration: BoxDecoration(
              color: scheme.outline,
              shape: BoxShape.circle,
              border: Border.all(color: surface, width: 2),
            ),
            child: Icon(Icons.check, size: 10, color: surface),
          ),
        ),
      ],
    );
  }
}
