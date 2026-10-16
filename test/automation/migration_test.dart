import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/data/database.dart';

class _InterruptedUpgrade extends AppDatabase {
  _InterruptedUpgrade(File file) : super(NativeDatabase(file));
  @override
  Future<void> customStatement(String statement, [List<Object?>? args]) {
    if (statement.startsWith('CREATE TABLE automation_runs')) {
      throw StateError('Injected migration interruption');
    }
    return super.customStatement(statement, args);
  }
}

class _V3Inspector extends AppDatabase {
  _V3Inspector(File file) : super(NativeDatabase(file));
  @override
  int get schemaVersion => 3;
}

void main() {
  late Directory directory;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tako-review-migration-');
    file = File('${directory.path}/fixture.sqlite');
    final initial = AppDatabase(NativeDatabase(file));
    await initial.customStatement(
      "INSERT INTO setting_records(key,value) VALUES('fixture','preserved')",
    );
    for (final table in [
      'automation_rules',
      'automation_inputs',
      'automation_runs',
      'automation_events',
      'execution_leases',
    ]) {
      await initial.customStatement('DROP TABLE $table');
    }
    await initial.customStatement('PRAGMA user_version=3');
    await initial.close();
  });
  tearDown(() async {
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final artifact = File('${file.path}$suffix');
      if (await artifact.exists()) await artifact.delete();
    }
    await directory.delete();
  });

  test(
    'a failed upgrade rolls back schema and version and can be retried',
    () async {
      final interrupted = _InterruptedUpgrade(file);
      await expectLater(
        interrupted.customSelect('SELECT 1').get(),
        throwsStateError,
      );
      await interrupted.close();
      final inspector = _V3Inspector(file);
      expect(
        (await inspector.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        3,
      );
      expect(
        await inspector
            .customSelect(
              "SELECT name FROM sqlite_master WHERE name LIKE 'automation_%'",
            )
            .get(),
        isEmpty,
      );
      await inspector.close();
      final retry = AppDatabase(NativeDatabase(file));
      expect(
        (await retry.select(retry.settingRecords).getSingle()).value,
        'preserved',
      );
      expect(
        (await retry.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        4,
      );
      await retry.close();
    },
  );

  test(
    'independent background database connections can open and migrate together',
    () async {
      final first = AppDatabase(
        NativeDatabase.createInBackground(
          file,
          setup: AppDatabase.nativeOptions.setup,
        ),
      );
      final second = AppDatabase(
        NativeDatabase.createInBackground(
          file,
          setup: AppDatabase.nativeOptions.setup,
        ),
      );
      try {
        final rows = await Future.wait([
          first.select(first.settingRecords).getSingle(),
          second.select(second.settingRecords).getSingle(),
        ]);
        expect(rows.map((r) => r.value), ['preserved', 'preserved']);
        expect(
          await first
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'automation_%'",
              )
              .get(),
          hasLength(4),
        );
      } finally {
        await first.close();
        await second.close();
      }
    },
  );
}
