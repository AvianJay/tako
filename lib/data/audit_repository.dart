import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/permissions/risk_level.dart';
import 'database.dart';

/// Credentials are never retained, including if a tool returned them by error.
/// This is defense in depth; credentials should not be tool arguments at all.
String redactAuditText(String text) => text
    .replaceAll(RegExp(r'sk-[A-Za-z0-9_-]+'), '[REDACTED]')
    .replaceAll(
      RegExp(r'Bearer\s+[^\s"\x27,}]+', caseSensitive: false),
      'Bearer [REDACTED]',
    )
    .replaceAllMapped(
      RegExp(
        r'''((?:api[_-]?key|authorization|password|secret|access[_-]?token|refresh[_-]?token)["']?\s*[:=]\s*)(?:"(?:\\.|[^"\r\n])*(?:"|$)|'(?:\\.|[^'\r\n])*(?:'|$)|[^\s,}\r\n]+)''',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}[REDACTED]',
    );

Object? _redactValue(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString():
            RegExp(
              r'password|secret|token|authorization|api.?key|cookie|credential',
              caseSensitive: false,
            ).hasMatch(entry.key.toString())
            ? '[REDACTED]'
            : _redactValue(entry.value),
    };
  }
  if (value is List) return [for (final item in value) _redactValue(item)];
  return value is String ? redactAuditText(value) : value;
}

String _redactArguments(String raw) {
  try {
    return jsonEncode(_redactValue(jsonDecode(raw)));
  } on FormatException {
    // Invalid JSON cannot be traversed reliably; do not persist arbitrary text
    // which could contain credentials the model attempted to pass as arguments.
    return '{"error":"invalid_arguments"}';
  }
}

class AuditRepository {
  AuditRepository(this.database);
  final AppDatabase database;

  Future<int> start({
    required String conversationId,
    required String messageId,
    required String toolCallId,
    required String toolName,
    required String arguments,
    required RiskLevel risk,
  }) => database
      .into(database.auditRecords)
      .insert(
        AuditRecordsCompanion.insert(
          conversationId: conversationId,
          messageId: messageId,
          toolCallId: toolCallId,
          toolName: redactAuditText(toolName),
          arguments: _redactArguments(arguments),
          risk: risk.name,
          decision: 'pending',
          startedAt: DateTime.now().toUtc(),
        ),
      );

  Future<void> finish(
    int id, {
    required String decision,
    required String resultSummary,
    required bool isError,
  }) async {
    final summary = redactAuditText(resultSummary);
    await (database.update(
      database.auditRecords,
    )..where((t) => t.id.equals(id))).write(
      AuditRecordsCompanion(
        decision: Value(decision),
        resultSummary: Value(
          summary.length > 600 ? '${summary.substring(0, 600)}…' : summary,
        ),
        isError: Value(isError),
        finishedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<List<AuditRecord>> list({int limit = 200, int offset = 0}) =>
      (database.select(database.auditRecords)
            ..orderBy([(t) => OrderingTerm.desc(t.id)])
            ..limit(limit.clamp(1, 1000), offset: offset < 0 ? 0 : offset))
          .get();

  Future<void> clear() async {
    await database.delete(database.auditRecords).go();
  }

  Future<int> recoverInterrupted() =>
      (database.update(
        database.auditRecords,
      )..where((t) => t.finishedAt.isNull())).write(
        AuditRecordsCompanion(
          decision: const Value('interrupted'),
          resultSummary: const Value('{"error":"interrupted"}'),
          isError: const Value(true),
          finishedAt: Value(DateTime.now().toUtc()),
        ),
      );
}
