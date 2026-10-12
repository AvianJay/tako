/// A per-send snapshot, persisted verbatim with its user message.
abstract final class ContextEnvelope {
  static String build({
    required DateTime now,
    DateTime? previousMessageAt,
    int? timezoneOffsetMinutes,
    int? batteryPercent,
    String? network,
    String? foregroundApp,
  }) {
    final offset = timezoneOffsetMinutes ?? now.timeZoneOffset.inMinutes;
    final local = now.toUtc().add(Duration(minutes: offset));
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    String pad(int value) => value.toString().padLeft(2, '0');
    final zone =
        '${offset < 0 ? '-' : '+'}${pad(offset.abs() ~/ 60)}:'
        '${pad(offset.abs() % 60)}';
    final time =
        '${local.year}-${pad(local.month)}-${pad(local.day)} '
        '${weekdays[local.weekday - 1]} ${pad(local.hour)}:${pad(local.minute)} $zone';
    final attributes = <String, String>{'time': time};
    if (previousMessageAt != null) {
      final gap = now.toUtc().difference(previousMessageAt.toUtc());
      if (gap >= const Duration(minutes: 30)) {
        final parts = <String>[
          if (gap.inDays > 0) '${gap.inDays}d',
          if (gap.inHours % 24 > 0) '${gap.inHours % 24}h',
          if (gap.inMinutes % 60 > 0) '${gap.inMinutes % 60}m',
        ];
        attributes['since_last'] = parts.join(' ');
      }
    }
    if (batteryPercent != null) {
      attributes['battery'] = '${batteryPercent.clamp(0, 100)}%';
    }
    if (network != null && network.isNotEmpty) attributes['net'] = network;
    if (foregroundApp != null && foregroundApp.isNotEmpty) {
      attributes['app'] = foregroundApp;
    }
    return '<ctx ${attributes.entries.map((e) => '${e.key}="${_escape(e.value)}"').join(' ')}/>';
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('\r', '&#13;')
      .replaceAll('\n', '&#10;');
}
