import 'database.dart';

/// Non-secret preferences only; credentials belong in secure storage.
final class SettingsRepository {
  SettingsRepository(this.database);
  final AppDatabase database;

  Future<String?> getString(String key) async {
    final row = await (database.select(
      database.settingRecords,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setString(String key, String? value) async {
    if (value == null) {
      await (database.delete(
        database.settingRecords,
      )..where((t) => t.key.equals(key))).go();
    } else {
      await database
          .into(database.settingRecords)
          .insertOnConflictUpdate(
            SettingRecordsCompanion.insert(key: key, value: value),
          );
    }
  }

  /// Take the SQLite writer lock before reading, including across engines.
  /// A deferred read-then-write transaction can otherwise use a stale snapshot.
  Future<String> updateString(String key, String Function(String?) update) =>
      database.transaction(() async {
        await database.customStatement(
          'UPDATE setting_records SET value=value WHERE key=?',
          [key],
        );
        final value = update(await getString(key));
        await setString(key, value);
        return value;
      });

  Future<Map<String, String>> readAll() async => {
    for (final row in await database.select(database.settingRecords).get())
      row.key: row.value,
  };
}
