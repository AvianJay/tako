import 'dart:convert';

import '../core/providers/provider_config.dart';
import '../core/util/json.dart';
import 'database.dart';

/// Config JSON contains secure-storage references only. Secret headers are
/// omitted by ProviderConfig.toJson just like the API key itself.
final class ProviderRepository {
  ProviderRepository(this.database);
  final AppDatabase database;

  Future<List<ProviderConfig>> list() async {
    final rows = await database.select(database.providerRecords).get();
    return rows
        .map((r) => ProviderConfig.fromJson(tryDecodeObject(r.data)!))
        .toList();
  }

  Future<void> save(ProviderConfig config) async {
    // Reject embedded URL credentials/query keys before persistence.
    providerEndpoint(config.baseUrl, 'models');
    await database
        .into(database.providerRecords)
        .insertOnConflictUpdate(
          ProviderRecordsCompanion.insert(
            id: config.id,
            data: jsonEncode(config.toJson()),
          ),
        );
  }

  Future<void> delete(String id) async {
    await (database.delete(
      database.providerRecords,
    )..where((t) => t.id.equals(id))).go();
  }
}
