import '../../core/providers/cancel_token.dart';
import '../../core/tools/device_tools.dart' show matchApps;
import '../device_tools_capability.dart';
import 'ictrl_screen.dart';

/// Adds app launching to native iOS tools while iCTRL is paired.
class IctrlDeviceTools implements DeviceToolsCapability {
  IctrlDeviceTools({required this.screen, required this.native});
  final IctrlScreen screen;
  final DeviceToolsCapability native;
  final _apps = <String, String>{};
  List<Map<String, Object?>>? _knownApps;
  DateTime? _knownAppsAt;
  @override
  bool get isAvailable => native.isAvailable || screen.isAvailable;
  @override
  bool supports(String tool) =>
      native.supports(tool) ||
      {'open_app', 'open_url', 'resolve_app'}.contains(tool) &&
          screen.isAvailable;
  @override
  Future<Map<String, Object?>> invoke(
    String tool,
    Map<String, Object?> arguments, {
    required CancelToken cancel,
  }) async {
    if (tool == 'resolve_app' && screen.isAvailable) {
      return _resolve(arguments['name'] as String, cancel);
    }
    if (tool == 'open_url' && screen.isAvailable) {
      cancel.throwIfCancelled();
      await screen.prepareModelSession(cancel);
      try {
        await screen.rpc('open_url', {'url': arguments['url']});
        screen.expectObservation();
      } on Exception {
        throw const DeviceToolException(
          'url_open_failed_check_screen_before_retry',
        );
      }
      return {'remote_opened': true};
    }
    if (tool != 'open_app') {
      return native.invoke(tool, arguments, cancel: cancel);
    }
    if (!screen.isAvailable) throw const DeviceToolException('unavailable');
    final name = arguments['name'] as String? ?? '';
    var bundle = arguments['package'] as String? ?? _apps[name];
    if (bundle == null) {
      final found = await _resolve(name, cancel);
      final apps = (found['apps'] as List? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .toList();
      if (apps.length != 1) {
        throw DeviceToolException(
          apps.isEmpty ? 'app_not_found' : 'ambiguous_app',
          details: {
            'candidates': apps
                .take(5)
                .map((a) => {'name': a['name'], 'package': a['package']})
                .toList(),
          },
        );
      }
      bundle = apps.single['package'] as String;
      _apps[name] = bundle;
    }
    cancel.throwIfCancelled();
    await screen.prepareModelSession(cancel);
    try {
      await screen.rpc('launch_app', {'bundle_id': bundle, 'settle': false});
      screen.expectObservation(app: bundle);
    } on Exception {
      throw const DeviceToolException(
        'app_launch_failed_check_screen_before_retry',
      );
    }
    return {'launched': true, 'bundle_id': bundle};
  }

  Future<Map<String, Object?>> _resolve(String name, CancelToken cancel) async {
    cancel.throwIfCancelled();
    if (_knownAppsAt == null ||
        DateTime.now().difference(_knownAppsAt!) >
            const Duration(minutes: 15)) {
      try {
        final known = await screen.rpc('list_apps', const {}, cancel);
        _knownApps = [
          for (final item in known['apps'] as List? ?? const [])
            if (item is Map &&
                item['bundle_id'] is String &&
                item['name'] is String)
              {
                'name': item['name'],
                'package': item['bundle_id'],
                'installed': true,
              },
        ];
        _knownAppsAt = DateTime.now();
      } on Exception {
        cancel.throwIfCancelled();
      }
    }
    final known = _matches(name, _knownApps ?? []);
    if (known.isNotEmpty) {
      if (known.length == 1) _apps[name] = known.single['package'] as String;
      return {'apps': known.take(10).toList()};
    }
    final found = await screen.rpc('resolve_app', {'text': name}, cancel);
    final candidates = <Map<String, Object?>>[
      for (final item in found['apps'] as List? ?? const [])
        if (item is Map && item['bundle_id'] is String)
          {
            'name': item['name'],
            'package': item['bundle_id'],
            'source': item['source'],
            if (item['installed_here'] == true) 'installed': true,
          },
    ];
    final apps = _matches(name, candidates);
    if (apps.length == 1 && apps.single['installed'] == true) {
      _apps[name] = apps.single['package'] as String;
    }
    return {
      'apps': apps.take(10).toList(),
      if (apps.isEmpty && candidates.isNotEmpty)
        'suggestions': candidates.take(5).toList(),
      'hint':
          'Only installed=true confirms this device. Catalog candidates require launch verification. Try localized aliases separated by | if needed; an empty result does not prove absence.',
    };
  }

  List<Map<String, Object?>> _matches(
    String query,
    List<Map<String, Object?>> candidates,
  ) {
    final names = [
      for (final app in candidates)
        (
          label: app['name'] as String? ?? '',
          packageName: app['package'] as String,
        ),
    ];
    final packages = {
      for (final term in query.split('|'))
        for (final app in matchApps(term, names)) app.packageName,
    };
    return candidates.where((a) => packages.contains(a['package'])).toList();
  }
}
