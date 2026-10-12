import 'dart:convert';

import '../../platform/capabilities.dart';
import '../chat/content_block.dart';
import '../memory/memory.dart';
import 'tool.dart';

const memoryToolNames = {
  'memory_search',
  'memory_save',
  'memory_update',
  'memory_delete',
};

/// [gate] makes the tools unavailable while memory is switched off.
List<Tool> createMemoryTools(MemoryCapability memory, {Capability? gate}) => [
  for (final name in memoryToolNames) MemoryTool(memory, name, gate: gate),
];

class MemoryTool extends Tool {
  MemoryTool(this.memory, this.name, {Capability? gate}) : _gate = gate;
  final MemoryCapability memory;
  final Capability? _gate;
  @override
  final String name;
  @override
  Capability get requires => _gate ?? memory;

  @override
  String get description => switch (name) {
    'memory_search' =>
      'Search saved memories about the user. Returns entries with ids.',
    'memory_save' =>
      'Save a lasting fact or preference the user stated. kind: profile (who they are), preference (how they want help), or fact.',
    'memory_update' => 'Change a saved memory by id.',
    _ => 'Delete a saved memory by id.',
  };

  @override
  Map<String, Object?> get schema {
    const text = {'type': 'string', 'minLength': 1, 'maxLength': 2000};
    const id = {'type': 'string', 'minLength': 1, 'maxLength': 100};
    const kind = {
      'type': 'string',
      'enum': ['profile', 'preference', 'fact'],
    };
    return {
      'type': 'object',
      'properties': switch (name) {
        'memory_search' => {
          'query': {'type': 'string', 'minLength': 1, 'maxLength': 500},
          'limit': {'type': 'integer', 'minimum': 1, 'maximum': 20},
        },
        'memory_save' => {
          'text': text,
          'kind': kind,
          'pinned': {'type': 'boolean'},
        },
        'memory_update' => {
          'id': id,
          'text': text,
          'kind': kind,
          'pinned': {'type': 'boolean'},
        },
        _ => {'id': id},
      },
      'required': switch (name) {
        'memory_search' => ['query'],
        'memory_save' => ['text'],
        _ => ['id'],
      },
      'additionalProperties': false,
    };
  }

  @override
  RiskLevel riskFor(Map<String, Object?> args, ToolContext ctx) =>
      switch (name) {
        'memory_search' => RiskLevel.sensitive,
        'memory_delete' => RiskLevel.high,
        _ => RiskLevel.action,
      };

  @override
  Future<ToolResult> run(Map<String, Object?> args, ToolContext ctx) async {
    ctx.cancel.throwIfCancelled();
    try {
      switch (name) {
        case 'memory_search':
          final query = args['query'];
          final limit = args['limit'];
          if (query is! String || limit != null && limit is! int) {
            throw const MemoryFailure('invalid_arguments');
          }
          final entries = await ctx.cancel.bind(
            memory.search(query, limit: (limit as int? ?? 8).clamp(1, 20)),
          );
          return ToolResult(
            content: jsonEncode({
              'memories': [for (final entry in entries) _data(entry)],
            }),
          );
        case 'memory_save':
          final text = args['text'];
          if (text is! String) throw const MemoryFailure('invalid_arguments');
          final saved = await memory.save(
            text: text,
            kind: _kind(args['kind']) ?? MemoryKind.fact,
            pinned: _pinned(args['pinned']),
            sourceMessageId: ctx.messageId,
            cancel: ctx.cancel,
          );
          if (saved.duplicate) {
            return ToolResult(
              content: jsonEncode({
                'saved': _data(saved.entry),
                'already_saved': true,
              }),
            );
          }
          return ToolResult(
            content: jsonEncode({'saved': _data(saved.entry)}),
            sideEffects: [
              SideEffect(
                kind: 'memory_saved',
                summary: memorySummary(saved.entry.text),
                memoryUndo: MemoryUndo(
                  id: saved.entry.id,
                  revision: saved.entry.revision,
                ).toJson(),
              ),
            ],
          );
        case 'memory_update':
          final id = _id(args['id']);
          final text = args['text'];
          if (text != null && text is! String ||
              !args.keys.any(const {'text', 'kind', 'pinned'}.contains)) {
            throw const MemoryFailure('invalid_arguments');
          }
          final entry = await memory.update(
            id,
            text: text as String?,
            kind: _kind(args['kind']),
            pinned: _pinned(args['pinned']),
            cancel: ctx.cancel,
          );
          return ToolResult(
            content: jsonEncode({'updated': _data(entry)}),
            sideEffects: [
              SideEffect(
                kind: 'memory_updated',
                summary: memorySummary(entry.text),
              ),
            ],
          );
        case 'memory_delete':
          final deleted = await memory.delete(
            _id(args['id']),
            cancel: ctx.cancel,
          );
          if (deleted == null) throw const MemoryFailure('memory_not_found');
          return ToolResult(
            content: jsonEncode({'deleted': deleted.id}),
            sideEffects: [
              SideEffect(
                kind: 'memory_deleted',
                summary: memorySummary(deleted.text),
              ),
            ],
          );
        default:
          throw const MemoryFailure('tool_unavailable');
      }
    } on MemoryFailure catch (error) {
      return ToolResult(
        content: jsonEncode({'error': error.code}),
        isError: true,
      );
    }
  }

  static Map<String, Object?> _data(MemoryEntry entry) => {
    'id': entry.id,
    'text': entry.text,
    'kind': entry.kind.name,
    'pinned': entry.pinned,
  };

  static MemoryKind? _kind(Object? value) {
    if (value == null) return null;
    return memoryKindNamed(value) ??
        (throw const MemoryFailure('invalid_arguments'));
  }

  static bool? _pinned(Object? value) {
    if (value != null && value is! bool) {
      throw const MemoryFailure('invalid_arguments');
    }
    return value as bool?;
  }

  static String _id(Object? value) {
    if (value is! String || value.isEmpty || value.length > 100) {
      throw const MemoryFailure('invalid_arguments');
    }
    return value;
  }
}

/// A short single-line excerpt for receipts, rewind sheets and chips.
String memorySummary(String text) {
  final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final runes = compact.runes.toList();
  return runes.length <= 120
      ? compact
      : '${String.fromCharCodes(runes.take(119))}…';
}
