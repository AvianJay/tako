import 'dart:math' as math;
import 'dart:ui';

import 'package:intl/intl.dart';

import 'mermaid.dart';
import 'visual_text.dart';

class GanttTask {
  const GanttTask(
    this.label,
    this.start,
    this.end, {
    this.section = 0,
    this.done = false,
    this.active = false,
    this.critical = false,
    this.milestone = false,
  });

  final String label;

  /// Wall-clock times kept in UTC, so daylight saving never moves a bar.
  final DateTime start;
  final DateTime end;

  /// An index into [GanttDiagram.sections].
  final int section;
  final bool done;
  final bool active;
  final bool critical;
  final bool milestone;
}

final class GanttDiagram extends MermaidDiagram {
  const GanttDiagram({
    required this.sections,
    required this.tasks,
    this.clockOnly = false,
    String? title,
  }) : super(title);

  /// Section names in order; an empty name holds tasks written before the
  /// first `section`.
  final List<String> sections;
  final List<GanttTask> tasks;

  /// Dates were written as times of day alone, so ticks never name a date.
  final bool clockOnly;
}

const maxGanttTasks = 100;

/// `title`, `dateFormat`, `section` and tasks written as
/// `Name :[tags,] [id,] start|after id, end|duration|until id`. Display
/// settings such as `axisFormat`, `excludes` and `todayMarker` are ignored,
/// and so are lines Tako cannot read.
GanttDiagram parseGantt(List<String> lines, String? title) {
  var heading = title;
  var reader = _DateReader('YYYY-MM-DD');
  var inclusive = false;
  final sections = <String>[''];
  final drafts = <_Draft>[];
  for (final raw in lines) {
    final line = raw.trim();
    final keyword = RegExp(r'^[A-Za-z]+').firstMatch(line)?[0]?.toLowerCase();
    final rest = keyword == null ? '' : line.substring(keyword.length);
    if (keyword == 'title' && rest.trimLeft().startsWith(':')) {
      heading = cleanMermaidText(rest.trimLeft().substring(1));
      continue;
    }
    if (keyword != null && RegExp(r'^(?:\s|$)').hasMatch(rest)) {
      switch (keyword) {
        case 'title':
          heading = cleanMermaidText(rest);
          continue;
        case 'dateformat':
          reader = _DateReader(rest.trim());
          continue;
        case 'section':
          final name = cleanMermaidText(rest);
          if (!drafts.any((d) => d.section == sections.length - 1)) {
            sections.last = name;
          } else {
            sections.add(name);
          }
          continue;
        case 'inclusiveenddates':
          inclusive = true;
          continue;
        case 'axisformat' ||
            'tickinterval' ||
            'excludes' ||
            'includes' ||
            'todaymarker' ||
            'weekday' ||
            'weekend' ||
            'displaymode' ||
            'topaxis' ||
            'acctitle' ||
            'accdescr' ||
            'click':
          continue;
      }
    }
    final colon = _taskColon.firstMatch(line);
    if (colon == null) continue;
    final label = cleanMermaidText(line.substring(0, colon.start));
    if (label.isEmpty) continue;
    drafts.add(
      _Draft.parse(
        label,
        line.substring(colon.end),
        sections.length - 1,
        reader,
        inclusive: inclusive,
      ),
    );
    if (drafts.length > maxGanttTasks) {
      throw const FormatException('Gantt chart is too large');
    }
  }
  if (drafts.isEmpty) throw const FormatException('A Gantt chart needs tasks');
  _resolve(drafts);

  // Sections without tasks are dropped; the rest keep their order, and with
  // it their colours.
  final used = <int, int>{};
  for (final draft in drafts) {
    used.putIfAbsent(draft.section, () => used.length);
  }
  final tasks = [
    for (final draft in drafts)
      GanttTask(
        draft.label,
        draft.from!,
        draft.to!,
        section: used[draft.section]!,
        done: draft.done,
        active: draft.active,
        critical: draft.critical,
        milestone: draft.milestone,
      ),
  ];
  final low = tasks.map((t) => t.start).reduce((a, b) => a.isBefore(b) ? a : b);
  final high = tasks.map((t) => t.end).reduce((a, b) => a.isAfter(b) ? a : b);
  if (high.difference(low).inDays > 366 * 200) {
    throw const FormatException('Gantt chart spans too long');
  }
  return GanttDiagram(
    sections: List.unmodifiable([
      for (final index in used.keys) sections[index],
    ]),
    tasks: List.unmodifiable(tasks),
    clockOnly: !reader.sawDate,
    title: heading == null || heading.isEmpty ? null : heading,
  );
}

/// The colon after a task name. One between digits belongs to a time such
/// as `09:30` instead.
final _taskColon = RegExp(r'(?<!\d):|:(?!\d)');

class _Draft {
  _Draft(
    this.label,
    this.section, {
    required this.id,
    required this.startAt,
    required this.after,
    required this.endAt,
    required this.until,
    required this.length,
    required this.done,
    required this.active,
    required this.critical,
    required this.milestone,
  });

  factory _Draft.parse(
    String label,
    String data,
    int section,
    _DateReader reader, {
    required bool inclusive,
  }) {
    final parts = [
      for (final part in data.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
    var done = false;
    var active = false;
    var critical = false;
    var milestone = false;
    tags:
    while (parts.isNotEmpty) {
      switch (parts.first.toLowerCase()) {
        case 'done':
          done = true;
        case 'active':
          active = true;
        case 'crit' || 'critical':
          critical = true;
        case 'milestone':
          milestone = true;
        default:
          break tags;
      }
      parts.removeAt(0);
    }
    bool startLike(String text) =>
        _after.hasMatch(text) || reader.read(text, peek: true) != null;
    String? id;
    String? start;
    final String end;
    switch (parts.length) {
      case 0 when milestone:
        end = '0d';
      case 0:
        throw FormatException('Task "$label" needs a duration or an end');
      case 1:
        end = parts[0];
      case 2:
        if (startLike(parts[0])) {
          start = parts[0];
        } else {
          id = parts[0];
        }
        end = parts[1];
      default:
        id = parts[0];
        start = parts[1];
        end = parts[2];
    }

    DateTime? startAt;
    List<String>? after;
    if (start != null) {
      if (_after.firstMatch(start) case final match?) {
        after = match[1]!.trim().split(RegExp(r'\s+'));
      } else {
        startAt =
            reader.read(start) ??
            (throw FormatException('Unreadable start "$start"'));
      }
    }
    DateTime? endAt;
    List<String>? until;
    _Span? length;
    if (_until.firstMatch(end) case final match?) {
      until = match[1]!.trim().split(RegExp(r'\s+'));
    } else if (reader.read(end) case final date?) {
      endAt = inclusive ? date.add(const Duration(days: 1)) : date;
    } else {
      length = _Span.parse(end) ?? (throw FormatException('Unreadable "$end"'));
    }
    return _Draft(
      label,
      section,
      id: id,
      startAt: startAt,
      after: after,
      endAt: endAt,
      until: until,
      length: length,
      done: done,
      active: active,
      critical: critical,
      milestone: milestone,
    );
  }

  final String label;
  final int section;
  final String? id;

  /// Without either, a task starts when the one above it ends.
  final DateTime? startAt;
  final List<String>? after;

  /// Exactly one of these is set.
  final DateTime? endAt;
  final List<String>? until;
  final _Span? length;
  final bool done;
  final bool active;
  final bool critical;
  final bool milestone;

  DateTime? from;
  DateTime? to;
}

final _after = RegExp(r'^after\s+(.+)$', caseSensitive: false);
final _until = RegExp(r'^until\s+(.+)$', caseSensitive: false);

/// Resolves `after` and `until` in any order, as Mermaid does. Unknown ids
/// fall back to the task above; a loop cannot be drawn.
void _resolve(List<_Draft> drafts) {
  final byId = {
    for (final draft in drafts)
      if (draft.id case final id?) id.toLowerCase(): draft,
  };
  List<_Draft> refer(List<String> ids, int index) {
    final found = [for (final id in ids) ?byId[id.toLowerCase()]];
    if (found.isNotEmpty) return found;
    if (index == 0) {
      throw const FormatException('The first task needs a start date');
    }
    return [drafts[index - 1]];
  }

  for (var pending = drafts.length; pending > 0;) {
    var progress = false;
    for (final (index, draft) in drafts.indexed) {
      if (draft.to != null) continue;
      var from = draft.startAt;
      if (from == null) {
        final after = refer(draft.after ?? const [], index);
        if (after.any((d) => d.to == null)) continue;
        from = after.map((d) => d.to!).reduce((a, b) => a.isAfter(b) ? a : b);
      }
      DateTime to;
      if (draft.until case final ids?) {
        final until = refer(ids, index);
        if (until.any((d) => d.from == null)) continue;
        to = until.map((d) => d.from!).reduce((a, b) => a.isBefore(b) ? a : b);
      } else {
        to = draft.endAt ?? draft.length!.after(from);
      }
      draft
        ..from = from
        ..to = to.isBefore(from) ? from : to;
      pending--;
      progress = true;
    }
    if (!progress) {
      throw const FormatException('Gantt tasks depend on each other');
    }
  }
}

/// A task length such as `3d`, `2w`, `5h`, `30m` or `1.5 months`. `M` is a
/// month and `m` a minute, as in Mermaid.
class _Span {
  const _Span(this.months, this.time);

  static _Span? parse(String text) {
    final match = RegExp(
      r'^(\d+(?:\.\d+)?)\s*([A-Za-z]+)$',
    ).firstMatch(text.trim());
    if (match == null) return null;
    final amount = double.parse(match[1]!);
    final unit = match[2]!;
    Duration time(int microseconds) =>
        Duration(microseconds: (amount * microseconds).round());
    const second = 1000000;
    if (unit == 'M') return _months(amount);
    return switch (unit.toLowerCase()) {
      'ms' => _Span(0, time(1000)),
      's' || 'sec' || 'secs' || 'second' || 'seconds' => _Span(0, time(second)),
      'm' ||
      'min' ||
      'mins' ||
      'minute' ||
      'minutes' => _Span(0, time(60 * second)),
      'h' ||
      'hr' ||
      'hrs' ||
      'hour' ||
      'hours' => _Span(0, time(3600 * second)),
      'd' || 'day' || 'days' => _Span(0, time(86400 * second)),
      'w' ||
      'wk' ||
      'wks' ||
      'week' ||
      'weeks' => _Span(0, time(7 * 86400 * second)),
      'mo' || 'mos' || 'mon' || 'month' || 'months' => _months(amount),
      'y' || 'yr' || 'yrs' || 'year' || 'years' => _months(amount * 12),
      _ => null,
    };
  }

  static _Span _months(double amount) => _Span(
    amount.floor(),
    Duration(hours: ((amount - amount.floor()) * 30 * 24).round()),
  );

  final int months;
  final Duration time;

  /// Whole months land on the same day of the month, or its last day.
  DateTime after(DateTime from) {
    var date = from;
    if (months != 0) {
      final first = DateTime.utc(from.year, from.month + months);
      final last = DateTime.utc(first.year, first.month + 1, 0).day;
      date = DateTime.utc(
        first.year,
        first.month,
        math.min(from.day, last),
        from.hour,
        from.minute,
        from.second,
        from.millisecond,
      );
    }
    return date.add(time);
  }
}

/// Reads dates in a dayjs `dateFormat` such as `YYYY-MM-DD HH:mm`. Formats
/// with tokens it does not know, and dates that do not match, fall back to
/// ISO dates and bare times.
class _DateReader {
  factory _DateReader(String format) {
    final fields = <String>[];
    final pattern = StringBuffer('^');
    var supported = format.isNotEmpty;
    for (var i = 0; i < format.length && supported;) {
      final char = format[i];
      if (char == '[') {
        final close = format.indexOf(']', i);
        final end = close < 0 ? format.length : close;
        pattern.write(RegExp.escape(format.substring(i + 1, end)));
        i = end + 1;
        continue;
      }
      final token = _tokens.keys
          .where((token) => format.startsWith(token, i))
          .firstOrNull;
      if (token != null) {
        final part = _tokens[token]!;
        pattern.write(part);
        if (part.startsWith('(') && !part.startsWith('(?:')) fields.add(token);
        i += token.length;
      } else if (RegExp('[A-Za-z]').hasMatch(char)) {
        supported = false;
      } else {
        pattern.write(char.trim().isEmpty ? r'\s+' : RegExp.escape(char));
        i++;
      }
    }
    pattern.write(r'$');
    return _DateReader._(
      supported ? RegExp(pattern.toString(), caseSensitive: false) : null,
      fields,
    );
  }

  _DateReader._(this._pattern, this._fields);

  /// Longest first, so `MMMM` is not read as `MM` twice.
  static const _tokens = {
    'YYYY': r'(\d{4})',
    'MMMM': r'([A-Za-z]{3,}\.?)',
    'dddd': r'[A-Za-z]+',
    'MMM': r'([A-Za-z]{3,}\.?)',
    'ddd': r'[A-Za-z]+',
    'SSS': r'(\d{1,3})',
    'YY': r'(\d{2})',
    'MM': r'(\d{1,2})',
    'Do': r'(\d{1,2})(?:st|nd|rd|th)',
    'DD': r'(\d{1,2})',
    'HH': r'(\d{1,2})',
    'hh': r'(\d{1,2})',
    'mm': r'(\d{1,2})',
    'ss': r'(\d{1,2})',
    'ZZ': r'(?:Z|[+-]\d{2}:?\d{2})',
    'M': r'(\d{1,2})',
    'D': r'(\d{1,2})',
    'H': r'(\d{1,2})',
    'h': r'(\d{1,2})',
    'm': r'(\d{1,2})',
    's': r'(\d{1,2})',
    'A': r'([AaPp][Mm])',
    'a': r'([AaPp][Mm])',
    'X': r'(-?\d+(?:\.\d+)?)',
    'x': r'(-?\d+)',
    'Z': r'(?:Z|[+-]\d{2}:?\d{2})',
  };

  static const _months = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];

  static final _iso = RegExp(
    r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})'
    r'(?:[T\s]+(\d{1,2}):(\d{2})(?::(\d{2}))?)?(?:Z|[+-]\d{2}:?\d{2})?$',
  );
  static final _clock = RegExp(r'^(\d{1,2}):(\d{2})$');

  final RegExp? _pattern;
  final List<String> _fields;

  /// Whether any date read so far named a day rather than only a time.
  bool sawDate = false;

  /// A date, or null when [text] is not one. [peek] leaves [sawDate] alone.
  DateTime? read(String text, {bool peek = false}) {
    final value = text.trim();
    final read = _formatted(value) ?? _fallback(value);
    if (read == null) return null;
    if (read.$2 && !peek) sawDate = true;
    return read.$1;
  }

  /// A date and whether it names a day.
  static (DateTime, bool)? _fallback(String value) {
    int? number(String? text) => text == null ? null : int.parse(text);
    if (_iso.firstMatch(value) case final m?) {
      final date = _date(
        number(m[1])!,
        number(m[2])!,
        number(m[3])!,
        number(m[4]) ?? 0,
        number(m[5]) ?? 0,
        number(m[6]) ?? 0,
      );
      return date == null ? null : (date, true);
    }
    if (_clock.firstMatch(value) case final m?) {
      final date = _date(1970, 1, 1, number(m[1])!, number(m[2])!, 0);
      return date == null ? null : (date, false);
    }
    return null;
  }

  (DateTime, bool)? _formatted(String value) {
    final match = _pattern?.firstMatch(value);
    if (match == null) return null;
    int? year;
    var month = 1;
    var day = 1;
    var hour = 0;
    var minute = 0;
    var second = 0;
    var millisecond = 0;
    bool? afternoon;
    var dated = false;
    for (final (index, field) in _fields.indexed) {
      final text = match[index + 1]!;
      final number = int.tryParse(text) ?? 0;
      switch (field) {
        case 'X':
          final seconds = double.tryParse(text);
          if (seconds == null) return null;
          return (
            DateTime.fromMillisecondsSinceEpoch(
              (seconds * 1000).round(),
              isUtc: true,
            ),
            true,
          );
        case 'x':
          return (
            DateTime.fromMillisecondsSinceEpoch(number, isUtc: true),
            true,
          );
        case 'YYYY':
          year = number;
        case 'YY':
          year = number > 68 ? 1900 + number : 2000 + number;
        case 'MMMM' || 'MMM':
          final index = _months.indexOf(text.toLowerCase().substring(0, 3));
          if (index < 0) return null;
          month = index + 1;
          dated = true;
        case 'MM' || 'M':
          month = number;
          dated = true;
        case 'DD' || 'D' || 'Do':
          day = number;
          dated = true;
        case 'HH' || 'H' || 'hh' || 'h':
          hour = number;
        case 'mm' || 'm':
          minute = number;
        case 'ss' || 's':
          second = number;
        case 'SSS':
          millisecond = int.parse(text.padRight(3, '0'));
        case 'A' || 'a':
          afternoon = text.toLowerCase() == 'pm';
      }
    }
    if (afternoon != null) hour = hour % 12 + (afternoon ? 12 : 0);
    final date = _date(year ?? 1970, month, day, hour, minute, second);
    if (date == null) return null;
    return (
      date.add(Duration(milliseconds: millisecond)),
      dated || year != null,
    );
  }

  static DateTime? _date(
    int year,
    int month,
    int day,
    int hour,
    int minute,
    int second,
  ) {
    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31 ||
        hour > 24 ||
        minute > 59 ||
        second > 59) {
      return null;
    }
    return DateTime.utc(year, month, day, hour, minute, second);
  }
}

class GanttTick {
  const GanttTick(this.x, this.label, this.labelLeft);
  final double x;
  final String label;

  /// Labels centre on their line unless that would cross the edge; null for
  /// a label skipped to keep its neighbours apart.
  final double? labelLeft;
}

class PlacedGanttSection {
  const PlacedGanttSection(this.title, this.titleOffset, this.band, this.slot);
  final String title;
  final Offset titleOffset;

  /// The heading and every row of the section.
  final Rect band;
  final int slot;
}

class PlacedGanttTask {
  const PlacedGanttTask(this.task, this.bar, this.labelOffset, this.slot);
  final GanttTask task;

  /// A milestone's diamond fills this square.
  final Rect bar;
  final Offset labelOffset;

  /// The series colour slot: one per section, in order.
  final int slot;
}

class GanttLayout {
  const GanttLayout({
    required this.size,
    required this.plot,
    required this.ticks,
    required this.sections,
    required this.tasks,
    required this.labelWidth,
  });

  final Size size;

  /// Bars span this rectangle, and grid lines run its height. Tick labels
  /// sit above it.
  final Rect plot;
  final List<GanttTick> ticks;
  final List<PlacedGanttSection> sections;
  final List<PlacedGanttTask> tasks;

  /// The wrap width of task labels.
  final double labelWidth;
}

enum _Unit { minute, hour, day, week, month, year }

/// Tick steps from a minute to fifty years.
const _steps = [
  (_Unit.minute, 1),
  (_Unit.minute, 5),
  (_Unit.minute, 10),
  (_Unit.minute, 15),
  (_Unit.minute, 30),
  (_Unit.hour, 1),
  (_Unit.hour, 2),
  (_Unit.hour, 3),
  (_Unit.hour, 6),
  (_Unit.hour, 12),
  (_Unit.day, 1),
  (_Unit.day, 2),
  (_Unit.week, 1),
  (_Unit.week, 2),
  (_Unit.month, 1),
  (_Unit.month, 2),
  (_Unit.month, 3),
  (_Unit.month, 6),
  (_Unit.year, 1),
  (_Unit.year, 2),
  (_Unit.year, 5),
  (_Unit.year, 10),
  (_Unit.year, 25),
  (_Unit.year, 50),
];

const _unitMinutes = {
  _Unit.minute: 1.0,
  _Unit.hour: 60.0,
  _Unit.day: 1440.0,
  _Unit.week: 10080.0,
  _Unit.month: 43830.0,
  _Unit.year: 525960.0,
};

/// Locale-aware tick labels. Each tick names the largest unit it starts: a
/// year, a month, a day, or else a time of day.
class GanttFormat {
  /// Locales whose date names are not loaded read in English. Only US
  /// English is built in; the app's localizations load the rest.
  factory GanttFormat(String localeName) {
    try {
      return GanttFormat._(localeName);
    } on Object {
      return GanttFormat._('en_US');
    }
  }

  GanttFormat._(String locale)
    : _time = DateFormat.Hm(locale),
      _day = DateFormat.MMMd(locale),
      _month = DateFormat.MMM(locale),
      _year = DateFormat.y(locale),
      _date = DateFormat.yMMMd(locale);

  final DateFormat _time;
  final DateFormat _day;
  final DateFormat _month;
  final DateFormat _year;
  final DateFormat _date;

  String tick(DateTime time, {bool clockOnly = false}) {
    if (clockOnly || time.hour != 0 || time.minute != 0) {
      return _time.format(time);
    }
    if (time.day != 1) return _day.format(time);
    if (time.month != 1) return _month.format(time);
    return _year.format(time);
  }

  /// A full date for screen readers, with its time when it has one.
  String when(DateTime time, {bool clockOnly = false}) {
    if (clockOnly) return _time.format(time);
    final day = _date.format(time);
    return time.hour == 0 && time.minute == 0
        ? day
        : '$day ${_time.format(time)}';
  }
}

double _minutes(DateTime from, DateTime to) =>
    to.difference(from).inMicroseconds / Duration.microsecondsPerMinute;

/// Rows of bars on a shared time axis, as wide as [fitWidth]. Wide columns
/// put task names in a column of their own; narrow ones put each name above
/// its bar, so the axis keeps the full width.
GanttLayout layoutGantt(
  GanttDiagram diagram,
  TextMeasurer text, {
  double? fitWidth,
  String localeName = 'en',
}) {
  final width = math.max(fitWidth ?? 640, 160.0);
  final format = GanttFormat(localeName);
  final stacked = width < 440;
  // Room for half a milestone past either end of the axis.
  const inset = 10.0;

  var low = diagram.tasks.first.start;
  var high = diagram.tasks.first.end;
  for (final task in diagram.tasks) {
    if (task.start.isBefore(low)) low = task.start;
    if (task.end.isAfter(high)) high = task.end;
  }
  if (!high.isAfter(low)) {
    low = low.subtract(const Duration(hours: 12));
    high = high.add(const Duration(hours: 12));
  }

  final widest = diagram.tasks.fold(
    0.0,
    (widest, task) =>
        math.max(widest, text.measure(task.label, VisualTextRole.body).width),
  );
  final labelWidth = stacked
      ? width
      : widest.clamp(64.0, math.min(width * .34, 200.0)).toDouble();
  final left = stacked ? inset : labelWidth + 16;
  final right = width - inset;
  final span = _minutes(low, high);
  double x(DateTime time) => left + _minutes(low, time) / span * (right - left);

  final ticks = <GanttTick>[];
  var lastRight = double.negativeInfinity;
  for (final time in _ticks(diagram, text, format, low, high, right - left)) {
    final at = x(time);
    final label = format.tick(time, clockOnly: diagram.clockOnly);
    final size = text.measure(label, VisualTextRole.tabular);
    final lowest = stacked ? 0.0 : left - 8;
    final labelLeft = (at - size.width / 2)
        .clamp(lowest, math.max(lowest, width - size.width))
        .toDouble();
    final fits = labelLeft >= lastRight + 8;
    if (fits) lastRight = labelLeft + size.width;
    ticks.add(GanttTick(at, label, fits ? labelLeft : null));
  }

  final top = text.measure('0', VisualTextRole.tabular).height + 8;
  final barHeight = stacked ? 12.0 : 18.0;
  final sections = <PlacedGanttSection>[];
  final tasks = <PlacedGanttTask>[];
  var y = top + 6;
  var section = -1;
  var sectionTop = y;
  void close() {
    if (section < 0) return;
    sections.add(
      PlacedGanttSection(
        diagram.sections[section],
        Offset(ganttSwatch + 8, sectionTop + 10),
        Rect.fromLTRB(0, sectionTop, width, y),
        section,
      ),
    );
  }

  for (final task in diagram.tasks) {
    if (task.section != section) {
      close();
      section = task.section;
      sectionTop = y;
      final name = diagram.sections[section];
      if (name.isNotEmpty) {
        y += text
            .measure(
              name,
              VisualTextRole.bodyStrong,
              maxWidth: width - ganttSwatch - 8,
              maxLines: 2,
            )
            .height;
        y += 14;
      }
    }
    final label = text.measure(
      task.label,
      VisualTextRole.body,
      maxWidth: labelWidth,
      maxLines: 2,
    );
    final start = x(task.start);
    final end = math.max(x(task.end), start + 3);
    if (stacked) {
      // The name rides above its bar, as far right as it fits.
      final barTop = y + 4 + label.height + 4;
      final bar = task.milestone
          ? Rect.fromCenter(
              center: Offset((start + end) / 2, barTop + barHeight / 2),
              width: barHeight + 4,
              height: barHeight + 4,
            )
          : Rect.fromLTRB(start, barTop, end, barTop + barHeight);
      final labelLeft = math.max(0.0, math.min(bar.left, width - label.width));
      tasks.add(
        PlacedGanttTask(task, bar, Offset(labelLeft, y + 4), task.section),
      );
      y = barTop + barHeight + 10;
    } else {
      final row = math.max(label.height, barHeight + 4) + 12;
      final middle = y + row / 2;
      final bar = task.milestone
          ? Rect.fromCenter(
              center: Offset((start + end) / 2, middle),
              width: barHeight,
              height: barHeight,
            )
          : Rect.fromLTRB(
              start,
              middle - barHeight / 2,
              end,
              middle + barHeight / 2,
            );
      tasks.add(
        PlacedGanttTask(
          task,
          bar,
          Offset(0, middle - label.height / 2),
          task.section,
        ),
      );
      y += row;
    }
  }
  close();
  return GanttLayout(
    size: Size(width, y + 4),
    plot: Rect.fromLTRB(left, top, right, y),
    ticks: ticks,
    sections: sections,
    tasks: tasks,
    labelWidth: labelWidth,
  );
}

/// The colour key beside a section's name.
const ganttSwatch = 10.0;

/// The finest step whose labels do not collide, from minutes to decades.
List<DateTime> _ticks(
  GanttDiagram diagram,
  TextMeasurer text,
  GanttFormat format,
  DateTime low,
  DateTime high,
  double width,
) {
  final span = _minutes(low, high);
  double labelWidth(DateTime sample) => text
      .measure(
        format.tick(sample, clockOnly: diagram.clockOnly),
        VisualTextRole.tabular,
      )
      .width;
  final clock = labelWidth(DateTime.utc(2026, 12, 28, 23, 45));
  final day = labelWidth(DateTime.utc(2026, 12, 28));
  final month = labelWidth(DateTime.utc(2026, 9));
  final year = labelWidth(DateTime.utc(2026));
  for (final (unit, count) in _steps) {
    final room = switch (unit) {
      _Unit.minute || _Unit.hour => math.max(clock, day),
      _Unit.day || _Unit.week => math.max(day, month),
      _Unit.month => math.max(month, year),
      _Unit.year => year,
    };
    final spacing = _unitMinutes[unit]! * count / span * width;
    if (spacing >= room + 14) {
      return _stepTicks(low, high, unit, count);
    }
  }
  return _stepTicks(low, high, _Unit.year, 100);
}

List<DateTime> _stepTicks(DateTime low, DateTime high, _Unit unit, int n) {
  var time = switch (unit) {
    _Unit.minute => DateTime.utc(
      low.year,
      low.month,
      low.day,
      low.hour,
      low.minute ~/ n * n,
    ),
    _Unit.hour => DateTime.utc(low.year, low.month, low.day, low.hour ~/ n * n),
    _Unit.day => DateTime.utc(low.year, low.month, low.day),
    _Unit.week => DateTime.utc(
      low.year,
      low.month,
      low.day - (low.weekday - DateTime.monday),
    ),
    _Unit.month => DateTime.utc(low.year, (low.month - 1) ~/ n * n + 1),
    _Unit.year => DateTime.utc(low.year ~/ n * n),
  };
  final ticks = <DateTime>[];
  while (!time.isAfter(high) && ticks.length < 200) {
    if (!time.isBefore(low)) ticks.add(time);
    time = switch (unit) {
      _Unit.minute => DateTime.utc(
        time.year,
        time.month,
        time.day,
        time.hour,
        time.minute + n,
      ),
      _Unit.hour => DateTime.utc(
        time.year,
        time.month,
        time.day,
        time.hour + n,
      ),
      // Every other day restarts on the first of each month.
      _Unit.day =>
        n > 1 &&
                DateTime.utc(time.year, time.month, time.day + n).month !=
                    time.month
            ? DateTime.utc(time.year, time.month + 1)
            : DateTime.utc(time.year, time.month, time.day + n),
      _Unit.week => DateTime.utc(time.year, time.month, time.day + 7 * n),
      _Unit.month => DateTime.utc(time.year, time.month + n),
      _Unit.year => DateTime.utc(time.year + n),
    };
  }
  return ticks;
}
