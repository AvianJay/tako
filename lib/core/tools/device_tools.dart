import 'dart:convert';

import '../../platform/capabilities.dart';
import '../../platform/device_tools_capability.dart';
import '../chat/content_block.dart';
import 'action_title.dart';
import 'screen_tools.dart';
import 'tool.dart';

/// With an [observer], open_app also returns the screen of the opened app.
List<Tool> createDeviceTools(
  DeviceToolsCapability capability, {
  ScreenObserver? observer,
  int maxChars = 6000,
}) => [
  for (final name in deviceToolNames)
    _DeviceTool(
      name,
      capability,
      observer: name == 'open_app' ? observer : null,
      maxChars: maxChars,
    ),
];

class _PerToolCapability implements Capability {
  const _PerToolCapability(this.device, this.tool);
  final DeviceToolsCapability device;
  final String tool;
  @override
  bool get isAvailable => device.isAvailable && device.supports(tool);
}

class _DeviceTool extends Tool {
  _DeviceTool(this.name, this.device, {this.observer, this.maxChars = 6000});
  @override
  final String name;
  final DeviceToolsCapability device;
  final ScreenObserver? observer;
  final int maxChars;
  @override
  Capability get requires => _PerToolCapability(device, name);
  @override
  String get description => _descriptions[name]!;
  @override
  Map<String, Object?> get schema => _schemas[name]!;
  @override
  RiskLevel riskFor(Map<String, Object?> args, ToolContext ctx) =>
      switch (name) {
        'get_device_status' => RiskLevel.safe,
        'get_location' ||
        'clipboard_read' ||
        'calendar_list' => RiskLevel.sensitive,
        'calendar_add' || 'open_url' => RiskLevel.high,
        _ => RiskLevel.action,
      };

  @override
  Future<ToolResult> run(Map<String, Object?> args, ToolContext ctx) async {
    ctx.cancel.throwIfCancelled();
    if (!validDeviceArguments(name, args)) {
      return const ToolResult(
        content: '{"error":"invalid_arguments"}',
        isError: true,
      );
    }
    if (!requires.isAvailable) {
      return const ToolResult(
        content: '{"error":"unavailable"}',
        isError: true,
      );
    }
    try {
      final observer = this.observer;
      if (name == 'open_app' && observer?.screen.isAvailable == true) {
        observer!.screen.updateModelSession(title: actionTitle(args));
      }
      final result = await device.invoke(name, args, cancel: ctx.cancel);
      final effects = [
        if (_sideEffectKinds[name] case final String kind)
          SideEffect(kind: kind, summary: name),
      ];
      if (observer != null && result['launched'] == true) {
        return observer.result(
          ctx,
          jsonEncode(result),
          maxChars: maxChars,
          sideEffects: effects,
          title: actionTitle(args),
        );
      }
      return ToolResult(content: jsonEncode(result), sideEffects: effects);
    } on DeviceToolException catch (error) {
      return ToolResult(
        content: jsonEncode({...error.details, 'error': error.code}),
        isError: true,
      );
    }
  }
}

typedef InstalledApp = ({String label, String packageName});

/// Apps whose label matches [query]: exact labels (or the package name)
/// first, then label prefixes, then labels containing the query.
List<InstalledApp> matchApps(String query, List<InstalledApp> apps) {
  String normalize(String value) => value
      .toLowerCase()
      .split(RegExp('[ \t]+'))
      .where((s) => s.isNotEmpty)
      .join(' ');
  final wanted = normalize(query);
  if (wanted.isEmpty) return const [];
  for (final test in <bool Function(String)>[
    (label) => label == wanted,
    (label) => label.startsWith(wanted),
    (label) => label.contains(wanted),
  ]) {
    final found = [
      for (final app in apps)
        if (test(normalize(app.label)) ||
            app.packageName.toLowerCase() == wanted)
          app,
    ];
    if (found.isNotEmpty) return found;
  }
  return const [];
}

/// Apps sharing a word (or, for CJK names, a character) with [query].
List<InstalledApp> similarApps(String query, List<InstalledApp> apps) {
  Set<String> parts(String value) => {
    for (final word in value.toLowerCase().split(RegExp('[ \t._-]+')))
      if (word.length >= 2) word,
    for (final rune in value.runes)
      if (rune >= 0x3040) String.fromCharCode(rune),
  };
  final wanted = parts(query);
  return [
    for (final app in apps)
      if (parts(app.label).any(wanted.contains)) app,
  ];
}

/// Validate before touching the OS, including contextual constraints JSON Schema
/// cannot express. Native code repeats bounds checks at its trust boundary.
bool validDeviceArguments(String name, Map<String, Object?> args) {
  final schema = _schemas[name];
  if (schema == null) return false;
  final properties = schema['properties'] as Map<String, Object?>;
  if (args.keys.any((key) => !properties.containsKey(key))) return false;
  for (final key in schema['required'] as List<String>) {
    if (!args.containsKey(key)) return false;
  }
  for (final entry in args.entries) {
    final rule = properties[entry.key] as Map<String, Object?>;
    final value = entry.value;
    if (rule['type'] == 'string') {
      if (value is! String) return false;
      if (value.length < (rule['minLength'] as int? ?? 0) ||
          value.length > (rule['maxLength'] as int? ?? 100000)) {
        return false;
      }
    } else if (rule['type'] == 'integer') {
      if (value is! num ||
          !value.isFinite ||
          value != value.roundToDouble() ||
          value < (rule['minimum'] as num) ||
          value > (rule['maximum'] as num)) {
        return false;
      }
    }
  }
  if (name == 'calendar_list' || name == 'calendar_add') {
    final start = _date(args['start']);
    final end = _date(args['end']);
    if (start == null ||
        end == null ||
        start.millisecondsSinceEpoch < 0 ||
        !end.isAfter(start) ||
        end.difference(start) > const Duration(days: 366)) {
      return false;
    }
    if (name == 'calendar_add' && (args['title'] as String).trim().isEmpty) {
      return false;
    }
  }
  if (name == 'open_url') {
    final value = args['url'] as String;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !{'https', 'http'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        value.codeUnits.any((unit) => unit <= 32)) {
      return false;
    }
  }
  if (name == 'open_app') {
    if (actionTitle(args) == null) return false;
    // Exactly one of the app's name or its package name.
    final package = args['package'];
    final appName = args['name'];
    if ((package == null) == (appName == null)) return false;
    if (appName is String && appName.trim().isEmpty) return false;
    if (package is String &&
        !RegExp(
          r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
        ).hasMatch(package)) {
      return false;
    }
  }
  return true;
}

DateTime? _date(Object? value) {
  if (value is! String) return null;
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(?:Z|[+-](\d{2}):(\d{2}))$',
  ).firstMatch(value);
  if (match == null) return null;
  int part(int group) => int.parse(match.group(group) ?? '0');
  final date = DateTime.utc(part(1), part(2), part(3));
  if (date.year != part(1) ||
      date.month != part(2) ||
      date.day != part(3) ||
      part(4) > 23 ||
      part(5) > 59 ||
      part(6) > 59 ||
      part(7) > 23 ||
      part(8) > 59) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}

const _descriptions = {
  'get_device_status': 'Read battery, network connection, OS and model.',
  'get_location':
      'Read a recent device location after permission. May be approximate.',
  'clipboard_read': 'Read up to 6000 characters of text from the clipboard.',
  'clipboard_write': 'Replace clipboard text.',
  'calendar_list':
      'List visible calendars and events in a bounded time range. Times need an explicit UTC offset.',
  'calendar_add':
      'Create an event in a writable calendar ID from calendar_list; may sync externally. Times need an explicit UTC offset.',
  'set_alarm':
      'Ask the clock app to set an alarm in device local time. Completion is not verified.',
  'set_timer':
      'Ask the clock app to start a timer. Completion is not verified.',
  'open_url':
      'Open an HTTP or HTTPS URL externally. Sends the URL to the selected app.',
  'open_app':
      'Launch an installed app by the name shown on the phone, or by exact Android package name.',
};
const _sideEffectKinds = {
  'clipboard_write': 'clipboard_written',
  'calendar_add': 'calendar_added',
  'set_alarm': 'alarm_requested',
  'set_timer': 'timer_requested',
  'open_url': 'url_opened',
  'open_app': 'app_opened',
};

Map<String, Object?> _object(
  Map<String, Object?> properties,
  List<String> required,
) => {
  'type': 'object',
  'properties': properties,
  'required': required,
  'additionalProperties': false,
};
Map<String, Object?> _string(int max, {int min = 0}) => {
  'type': 'string',
  'minLength': min,
  'maxLength': max,
};
Map<String, Object?> _integer(int min, int max) => {
  'type': 'integer',
  'minimum': min,
  'maximum': max,
};
final _schemas = <String, Map<String, Object?>>{
  for (final name in ['get_device_status', 'get_location', 'clipboard_read'])
    name: _object({}, []),
  'clipboard_write': _object({'text': _string(100000)}, ['text']),
  'calendar_list': _object(
    {'start': _string(50), 'end': _string(50), 'limit': _integer(1, 100)},
    ['start', 'end'],
  ),
  'calendar_add': _object(
    {
      'calendar_id': _integer(1, 9007199254740991),
      'title': _string(500, min: 1),
      'start': _string(50),
      'end': _string(50),
      'description': _string(4000),
      'location': _string(500),
    },
    ['calendar_id', 'title', 'start', 'end'],
  ),
  'set_alarm': _object(
    {'hour': _integer(0, 23), 'minute': _integer(0, 59), 'label': _string(200)},
    ['hour', 'minute'],
  ),
  'set_timer': _object(
    {'seconds': _integer(1, 86400), 'label': _string(200)},
    ['seconds'],
  ),
  'open_url': _object({'url': _string(8192, min: 1)}, ['url']),
  'open_app': _object(
    {
      'title': actionTitleSchema,
      'name': _string(100, min: 1),
      'package': _string(255, min: 3),
    },
    ['title'],
  ),
};
