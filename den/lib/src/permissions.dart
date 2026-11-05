import 'api.dart';

const defaultPermissions = <String, Object?>{
  'useSharedProviders': true,
  'ownProviders': true,
  'dailyTokenLimit': null,
};

Map<String, Object?> effectivePermissions(
  bool admin,
  Map defaults,
  Map overrides,
) => admin
    ? {...defaultPermissions}
    : {
        for (final key in defaultPermissions.keys)
          key: key == 'dailyTokenLimit' && overrides[key] == -1
              ? null
              : overrides[key] ?? defaults[key],
      };

Map<String, Object?> validatePermissions(
  Object? value, {
  bool overrides = false,
}) {
  if (value is! Map<String, Object?>) fail(400, 'invalid_request');
  for (final entry in value.entries) {
    if (!defaultPermissions.containsKey(entry.key)) {
      fail(400, 'invalid_request');
    }
    if (entry.key == 'dailyTokenLimit') {
      if (entry.value != null &&
          (entry.value is! int ||
              (entry.value as int) < (overrides ? -1 : 0))) {
        fail(400, 'invalid_request');
      }
    } else if (entry.value is! bool && !(overrides && entry.value == null)) {
      fail(400, 'invalid_request');
    }
  }
  return value;
}
