import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/memory/memory.dart';
import '../core/providers/cancel_token.dart';
import '../core/util/ids.dart';
import '../core/util/json.dart';
import 'database.dart';

/// A rendered pinned profile and how much of the word budget it used.
typedef MemoryProfile = ({String text, int words, bool truncated});

final class MemoryRepository implements MemoryCapability {
  MemoryRepository(this.database);
  final AppDatabase database;

  static const maxTextLength = 2000;
  static const profileWordLimit = 150;
  static const profileCharacterLimit = 1200;
  static const maxImportBytes = 2 * 1024 * 1024;
  static const maxImportEntries = 1000;
  static const _maxCandidates = 500;

  @override
  bool get isAvailable => true;

  /// Reactive list for the memory screen; [query] uses the search ranking.
  Stream<List<MemoryEntry>> watch({String query = ''}) {
    final terms = searchTerms(query);
    if (terms.isEmpty) {
      return _ordered().watch().map(
        (rows) => rows.map(_entry).toList(growable: false),
      );
    }
    return _candidates(
      terms,
    ).watch().map((rows) => _rank(rows, terms, _maxCandidates));
  }

  Future<List<MemoryEntry>> list() async =>
      (await _ordered().get()).map(_entry).toList(growable: false);

  @override
  Future<List<MemoryEntry>> search(String query, {int limit = 10}) async {
    if (query.length > 500) throw const MemoryFailure('query_too_long');
    final terms = searchTerms(query);
    if (terms.isEmpty) return const [];
    return _rank(await _candidates(terms).get(), terms, limit.clamp(1, 50));
  }

  @override
  Future<MemoryEntry?> get(String id) async {
    final row = await (database.select(
      database.memories,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _entry(row);
  }

  @override
  Future<MemorySaveResult> save({
    required String text,
    MemoryKind kind = MemoryKind.fact,
    bool? pinned,
    String? sourceMessageId,
    CancelToken? cancel,
  }) async {
    final value = _validateText(text);
    return database.transaction(() async {
      final existing = await (database.select(
        database.memories,
      )..where((t) => t.textValue.equals(value))).get();
      if (existing.isNotEmpty) {
        return MemorySaveResult(_entry(existing.first), duplicate: true);
      }
      final now = _now();
      final entry = MemoryEntry(
        id: newId(),
        text: value,
        kind: kind,
        // Profile and preference entries are pinned unless explicitly not.
        pinned: pinned ?? kind != MemoryKind.fact,
        createdAt: now,
        updatedAt: now,
        revision: newId(),
        sourceMessageId: sourceMessageId,
      );
      cancel?.throwIfCancelled();
      await database.into(database.memories).insert(_row(entry));
      // After the commit, the receipt is returned even if Stop arrived.
      return MemorySaveResult(entry);
    });
  }

  @override
  Future<MemoryEntry> update(
    String id, {
    String? text,
    MemoryKind? kind,
    bool? pinned,
    String? expectedRevision,
    CancelToken? cancel,
  }) async {
    final value = text == null ? null : _validateText(text);
    return database.transaction(() async {
      final previous = await get(id);
      if (previous == null) throw const MemoryFailure('memory_not_found');
      if (expectedRevision != null && previous.revision != expectedRevision) {
        throw const MemoryFailure('memory_changed');
      }
      if ((value ?? previous.text) == previous.text &&
          (kind ?? previous.kind) == previous.kind &&
          (pinned ?? previous.pinned) == previous.pinned) {
        return previous;
      }
      final entry = MemoryEntry(
        id: id,
        text: value ?? previous.text,
        kind: kind ?? previous.kind,
        pinned: pinned ?? previous.pinned,
        createdAt: previous.createdAt,
        updatedAt: _now(),
        revision: newId(),
        sourceMessageId: previous.sourceMessageId,
      );
      cancel?.throwIfCancelled();
      await (database.update(
        database.memories,
      )..where((t) => t.id.equals(id))).write(_row(entry));
      return entry;
    });
  }

  @override
  Future<MemoryEntry?> delete(
    String id, {
    String? expectedRevision,
    CancelToken? cancel,
  }) => database.transaction(() async {
    final previous = await get(id);
    if (previous == null ||
        expectedRevision != null && previous.revision != expectedRevision) {
      return null;
    }
    cancel?.throwIfCancelled();
    await (database.delete(
      database.memories,
    )..where((t) => t.id.equals(id))).go();
    return previous;
  });

  @override
  Future<bool> undoSaved(MemoryUndo undo) async =>
      await delete(undo.id, expectedRevision: undo.revision) != null;

  Future<void> clear() => database.delete(database.memories).go();

  /// Explicit user export includes every entry, independent of the UI limit.
  Future<String> exportJson() async {
    final rows =
        await (database.select(database.memories)..orderBy([
              (t) => OrderingTerm.asc(t.createdAt),
              (t) => OrderingTerm.asc(t.id),
            ]))
            .get();
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'tako.memories',
      'version': 1,
      'memories': [
        for (final row in rows)
          {
            'text': row.textValue,
            'kind': row.kind,
            'pinned': row.pinned,
            'createdAt': row.createdAt.toUtc().toIso8601String(),
            'updatedAt': row.updatedAt.toUtc().toIso8601String(),
          },
      ],
    });
  }

  /// Validates the whole document before writing. Imports get new IDs and
  /// revisions, never overwrite a local entry, and skip text already present,
  /// so importing the same export twice does not duplicate it.
  Future<int> importJson(String source) async {
    if (source.length > maxImportBytes ||
        utf8.encode(source).length > maxImportBytes) {
      throw const MemoryFailure('import_too_large');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const MemoryFailure('invalid_memory_import');
    }
    final json = asMap(decoded);
    final values = asList(json?['memories']);
    if (json == null ||
        json['format'] != 'tako.memories' ||
        json['version'] != 1 ||
        values == null ||
        values.length > maxImportEntries) {
      throw const MemoryFailure('invalid_memory_import');
    }
    final now = _now();
    final incoming = <MemoryEntry>[];
    for (final item in values) {
      final value = asMap(item);
      final text = value?['text'];
      final kind = memoryKindNamed(value?['kind']);
      final pinned = value?['pinned'];
      final created = DateTime.tryParse(asString(value?['createdAt']) ?? '');
      final updated = DateTime.tryParse(asString(value?['updatedAt']) ?? '');
      if (text is! String || kind == null || pinned is! bool) {
        throw const MemoryFailure('invalid_memory_import');
      }
      incoming.add(
        MemoryEntry(
          id: newId(),
          text: _validateText(text),
          kind: kind,
          pinned: pinned,
          createdAt: (created ?? now).toUtc(),
          updatedAt: (updated ?? created ?? now).toUtc(),
          revision: newId(),
        ),
      );
    }
    return database.transaction(() async {
      final texts = {
        for (final row in await database.select(database.memories).get())
          row.textValue,
      };
      var added = 0;
      for (final entry in incoming) {
        if (!texts.add(entry.text)) continue;
        await database.into(database.memories).insert(_row(entry));
        added++;
      }
      return added;
    });
  }

  @override
  Future<String> profileSnapshot({int maxWords = profileWordLimit}) async {
    final rows =
        await (database.select(database.memories)
              ..where(
                (t) =>
                    t.pinned.equals(true) &
                    t.kind.isIn([
                      MemoryKind.profile.name,
                      MemoryKind.preference.name,
                    ]),
              )
              ..orderBy([
                (t) => OrderingTerm.asc(t.createdAt),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    return buildProfile(rows.map(_entry), maxWords: maxWords).text;
  }

  /// One bullet per pinned profile/preference entry, oldest first. Each CJK
  /// character counts as a word so unspaced text cannot exceed the budget.
  /// Whitespace is collapsed: an entry can never add its own prompt section.
  static MemoryProfile buildProfile(
    Iterable<MemoryEntry> entries, {
    int maxWords = profileWordLimit,
  }) {
    var remaining = maxWords.clamp(0, profileWordLimit);
    var characters = profileCharacterLimit;
    var words = 0;
    var truncated = false;
    final lines = <String>[];
    for (final entry in entries) {
      if (!entry.inProfile) continue;
      final compact = entry.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final units = _wordUnits.allMatches(compact).toList();
      if (units.isEmpty) continue;
      if (remaining == 0 || characters < 8) {
        truncated = true;
        break;
      }
      final allowed = units.take(remaining).toList();
      var end = allowed.last.end;
      if (end > characters - 4) end = characters - 4;
      // Never split a UTF-16 surrogate pair.
      if (end > 0 && end < compact.length) {
        final unit = compact.codeUnitAt(end - 1);
        if (unit >= 0xd800 && unit <= 0xdbff) end--;
      }
      final piece = compact.substring(0, end).trimRight();
      if (piece.isEmpty) {
        truncated = true;
        break;
      }
      final cut = end < compact.length;
      final line = '- $piece${cut ? '…' : ''}';
      lines.add(line);
      characters -= line.length + 1;
      final used = _wordUnits.allMatches(piece).length;
      words += used;
      remaining -= used;
      if (cut) {
        truncated = true;
        break;
      }
    }
    return (text: lines.join('\n'), words: words, truncated: truncated);
  }

  /// Lowercased words. An unspaced CJK run is also split into bigrams because
  /// unicode61 indexes the whole run as one token: 咖啡偏好 finds 我偏好黑咖啡.
  static List<String> searchTerms(String query) {
    final terms = <String>{};
    void add(String run, bool cjk) {
      terms.add(run);
      final runes = run.runes.toList();
      if (cjk && runes.length > 2) {
        for (var i = 0; i + 1 < runes.length; i++) {
          terms.add(String.fromCharCodes(runes.sublist(i, i + 2)));
        }
      }
    }

    for (final match in _word.allMatches(query.toLowerCase())) {
      final run = StringBuffer();
      bool? cjk;
      for (final rune in match.group(0)!.runes) {
        final char = String.fromCharCode(rune);
        final isCjk = _cjk.hasMatch(char);
        if (cjk != null && isCjk != cjk) {
          add(run.toString(), cjk);
          run.clear();
        }
        cjk = isCjk;
        run.write(char);
      }
      if (run.isNotEmpty) add(run.toString(), cjk!);
      if (terms.length >= 24) break;
    }
    return terms.take(24).toList(growable: false);
  }

  SimpleSelectStatement<$MemoriesTable, MemoryRow> _ordered() =>
      database.select(database.memories)..orderBy([
        (t) => OrderingTerm.desc(t.pinned),
        (t) => OrderingTerm.desc(t.updatedAt),
        (t) => OrderingTerm.asc(t.id),
      ]);

  /// FTS terms are quoted phrases built from letters and digits only, so model
  /// input can never inject FTS operators. Substring checks cover CJK text.
  Selectable<MemoryRow> _candidates(List<String> terms) {
    final substrings = [
      for (final _ in terms) 'instr(lower(text), ?) > 0',
    ].join(' OR ');
    return database
        .customSelect(
          'SELECT * FROM memories WHERE id IN '
          '(SELECT id FROM memories_fts WHERE memories_fts MATCH ?) '
          'OR $substrings '
          'ORDER BY pinned DESC, updated_at DESC, id ASC LIMIT $_maxCandidates',
          variables: [
            Variable(terms.map((term) => '"$term"').join(' OR ')),
            for (final term in terms) Variable(term),
          ],
          readsFrom: {database.memories},
        )
        .map((row) => database.memories.map(row.data));
  }

  /// Most matched terms first, then pinned and recently updated entries.
  static List<MemoryEntry> _rank(
    List<MemoryRow> rows,
    List<String> terms,
    int limit,
  ) {
    final scored = <({MemoryEntry entry, int hits})>[];
    for (final row in rows) {
      final text = row.textValue.toLowerCase();
      scored.add((entry: _entry(row), hits: terms.where(text.contains).length));
    }
    scored.sort((a, b) {
      if (a.hits != b.hits) return b.hits.compareTo(a.hits);
      if (a.entry.pinned != b.entry.pinned) return a.entry.pinned ? -1 : 1;
      return b.entry.updatedAt.compareTo(a.entry.updatedAt);
    });
    return [for (final item in scored.take(limit)) item.entry];
  }

  static final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

  /// Kana, CJK ideographs (with extension A and compatibility) and Hangul.
  static final _cjkClass =
      [
            (0x3040, 0x30ff),
            (0x3400, 0x4dbf),
            (0x4e00, 0x9fff),
            (0xf900, 0xfaff),
            (0xac00, 0xd7af),
          ]
          .map(
            (r) => '${String.fromCharCode(r.$1)}-${String.fromCharCode(r.$2)}',
          )
          .join();
  static final _cjk = RegExp('[$_cjkClass]');
  static final _wordUnits = RegExp('[$_cjkClass]|[^${r'\s'}$_cjkClass]+');

  /// Drift stores whole seconds; returned entries must equal stored ones.
  static DateTime _now() {
    final now = DateTime.now().toUtc();
    return now.subtract(
      Duration(microseconds: now.microsecondsSinceEpoch % 1000000),
    );
  }

  static String _validateText(String value) {
    final text = value.trim();
    if (text.isEmpty ||
        text.length > maxTextLength ||
        text.contains('\u0000')) {
      throw const MemoryFailure('invalid_memory_text');
    }
    return text;
  }

  static MemoryEntry _entry(MemoryRow row) => MemoryEntry(
    id: row.id,
    text: row.textValue,
    kind: memoryKindNamed(row.kind) ?? MemoryKind.fact,
    pinned: row.pinned,
    createdAt: row.createdAt.toUtc(),
    updatedAt: row.updatedAt.toUtc(),
    revision: row.revision,
    sourceMessageId: row.sourceMessageId,
  );

  static MemoriesCompanion _row(MemoryEntry entry) => MemoriesCompanion.insert(
    id: entry.id,
    textValue: entry.text,
    kind: entry.kind.name,
    pinned: Value(entry.pinned),
    createdAt: entry.createdAt,
    updatedAt: entry.updatedAt,
    revision: entry.revision,
    sourceMessageId: Value(entry.sourceMessageId),
  );
}
