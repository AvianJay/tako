import 'dart:convert';

import 'package:flutter/services.dart';

import '../../platform/capabilities.dart';
import '../chat/content_block.dart';
import '../repl/repl_runtime.dart';
import '../util/ids.dart';
import '../util/json.dart';
import 'action_title.dart';
import 'screen_tools.dart';
import 'tool.dart';
import 'tool_executor.dart';
import 'tool_registry.dart';

typedef ReplExecute =
    Future<ToolExecution> Function(ToolCallBlock call, ToolContext context);
typedef ReplRuntimeFactory = ReplRuntime Function();
const replToolNames = {'read_skill', 'js_repl'};
const _methods = <String, String>{
  'browser.open': 'browser_open',
  'browser.read': 'browser_read',
  'browser.click': 'browser_click',
  'browser.type': 'browser_type',
  'browser.scroll': 'browser_scroll',
  'browser.back': 'browser_back',
  'phone.openApp': 'open_app',
  'phone.openUrl': 'open_url',
  'phone.resolveApp': 'resolve_app',
  'phone.read': 'read_screen',
  'phone.tap': 'tap',
  'phone.longPress': 'long_press',
  'phone.type': 'type_text',
  'phone.scroll': 'scroll',
  'phone.swipe': 'swipe',
  'phone.pressKey': 'press_key',
  'phone.drag': 'drag',
  'phone.sequence': 'screen_sequence',
  'phone.workflow': 'screen_workflow',
  'phone.replay': 'screen_replay',
};

class _Reference {
  const _Reference(this.group, this.id, this.revision, this.check);
  final String group;
  final int id;
  final int revision;
  final String check;
}

/// Two presentation tools over the SAME audited primitive registry. One per task.
class ReplToolSession {
  ReplToolSession({
    required this.registry,
    required this.execute,
    required this.runtimeFactory,
    this.readings,
    this.maxOutputChars = 6000,
    this.loadSkill,
  });
  final ToolRegistry registry;
  final ReplExecute execute;
  final ReplRuntimeFactory runtimeFactory;
  final ScreenReadings? readings;
  final int maxOutputChars;
  final Future<String> Function(String skill)? loadSkill;
  final _loaded = <String>{};
  final _refs = <String, _Reference>{};
  int _browserRevision = 0;
  int _operation = 0;
  String? _phoneReadInMessage;
  ReplRuntime? _runtime;
  bool _running = false;

  bool get _phoneAvailable =>
      screenToolNames.any((name) => registry.get(name) != null);
  Map<String, String> get methods => {
    for (final entry in _methods.entries)
      if (registry.get(entry.value) != null &&
          (entry.key.startsWith('browser.') || _phoneAvailable))
        entry.key: entry.value,
  };
  Set<String> get skills => {
    for (final method in methods.keys) method.split('.').first,
  };
  Set<String> get controlledNames => methods.values.toSet();
  List<Tool> get tools => [
    _ReplTool(this, 'read_skill'),
    _ReplTool(this, 'js_repl'),
  ];

  Future<ToolResult> readSkill(Map<String, Object?> args) async {
    final skill = args['skill'];
    if (skill is! String || !skills.contains(skill)) {
      return _error('skill_unavailable');
    }
    final selected = args['method'];
    final apis = {
      for (final entry in methods.entries)
        if (entry.key.startsWith('$skill.') &&
            (selected == null || selected == entry.key.split('.').last))
          entry.key: {
            'tool': entry.value,
            'parameters': registry.get(entry.value)!.schema,
          },
    };
    if (apis.isEmpty) return _error('method_unavailable');
    final guide =
        await (loadSkill?.call(skill) ??
            rootBundle.loadString('assets/skills/$skill.md'));
    _loaded.add(skill);
    return ToolResult(
      content:
          '$guide\nHost tool schemas (title defaults to the js_repl title; element replaces id):\n${jsonEncode(apis)}',
    );
  }

  Future<ToolResult> run(Map<String, Object?> args, ToolContext context) async {
    final title = actionTitle(args);
    if (title == null || args['code'] is! String) {
      return _error('invalid_arguments');
    }
    if (_loaded.isEmpty) return _error('read_skill_first');
    if (_running) return _error('repl_busy');
    _running = true;
    final receipts = <Map<String, Object?>>[];
    final effects = <SideEffect>[];
    final images = <ContentBlock>[];
    try {
      final runtime = _runtime ??= runtimeFactory();
      final evaluation = await runtime.evaluate(
        args['code']! as String,
        cancel: context.cancel,
        invoke: (method, arguments) async {
          final group = method.split('.').first;
          if (!_loaded.contains(group)) {
            return {'error': '${group}_skill_not_loaded'};
          }
          final name = methods[method];
          if (name == null) return const {'error': 'method_unavailable'};
          final tool = registry.get(name);
          if (tool == null) return const {'error': 'tool_unavailable'};
          if (arguments.length > 1) {
            return const {'error': 'one_argument_object_expected'};
          }
          final value = arguments.firstOrNull;
          if (value != null && value is! Map<String, Object?>) {
            return const {'error': 'argument_object_expected'};
          }
          final params = Map<String, Object?>.of(
            value as Map<String, Object?>? ?? {},
          );
          final properties = asMap(tool.schema['properties']) ?? {};
          if (properties.containsKey('title')) {
            params.putIfAbsent('title', () => title);
          }
          _Reference? reference;
          final directElement = const {
            'phone.tap',
            'phone.longPress',
            'browser.click',
          }.contains(method);
          final element = directElement ? value : params.remove('element');
          if (element != null &&
              element is Map<String, Object?> &&
              element['ref'] is String) {
            reference = _refs[element['ref']];
            if (reference == null || reference.group != group) {
              return const {'error': 'stale_element_read_again'};
            }
            final revision = group == 'browser'
                ? _browserRevision
                : readings?.latest(context.conversationId)?.tree.token;
            if (revision != reference.revision) {
              return const {'error': 'stale_element_read_again'};
            }
            if (directElement) params.clear();
            params['id'] = reference.id;
            if (properties.containsKey('title')) params['title'] = title;
          } else if (directElement &&
              !(params['x'] is num && params['y'] is num)) {
            return const {'error': 'element_reference_required'};
          } else if (params.containsKey('id')) {
            return const {'error': 'element_reference_required'};
          }
          if (group == 'phone' &&
              (params.containsKey('x') || params.containsKey('to_x')) &&
              _phoneReadInMessage == context.messageId) {
            return const {'error': 'use_a_screenshot_from_an_earlier_response'};
          }
          final before = readings?.latest(context.conversationId)?.tree.token;
          final id = '${context.messageId}-repl-${++_operation}';
          final call = ToolCallBlock(
            id: id,
            name: name,
            arguments: jsonEncode(params),
          );
          final result = await execute(
            call,
            ToolContext(
              conversationId: context.conversationId,
              messageId: id,
              cancel: context.cancel,
              lastCall: true,
              expectedTargetCheck:
                  group == 'browser' && reference?.check.isNotEmpty == true
                  ? reference!.check
                  : null,
            ),
          );
          final receipt = result.result;
          effects.addAll(receipt.sideEffects);
          images.addAll(receipt.attachments);
          if (images.length > 8) images.removeRange(0, images.length - 8);
          final data = tryDecodeObject(receipt.content.split('\n').first);
          receipts.add({
            'tool': name,
            'ok': !receipt.isError,
            if (receipt.isError) 'error': data?['error'] ?? 'operation_failed',
            if (receipt.sideEffects.isNotEmpty)
              'effects': [
                for (final effect in receipt.sideEffects) effect.toJson(),
              ],
          });
          if (receipt.isError) {
            return {
              'error': data?['error'] ?? 'operation_failed',
              'details': data,
            };
          }
          if (name == 'browser_read' && result.data != null) {
            _browserRevision++;
            return _browserSnapshot(result.data!);
          }
          final reading = readings?.latest(context.conversationId);
          if (group == 'phone' &&
              reading != null &&
              reading.tree.token != before) {
            _phoneReadInMessage = context.messageId;
            final observation = _phoneSnapshot(
              context.conversationId,
              receipt.content,
            );
            if (name == 'read_screen') return observation;
            return {
              ...?data,
              if (data == null) 'text': receipt.content,
              'screen': observation,
            };
          }
          return data ?? {'text': receipt.content};
        },
      );
      if (evaluation.reset) _refs.clear();
      return ToolResult(
        content: jsonEncode({
          if (evaluation.error != null) 'error': evaluation.error,
          if (evaluation.reset) 'session_reset': true,
          if (evaluation.output.isNotEmpty) 'output': evaluation.output,
          if (evaluation.value != null) 'value': evaluation.value,
          'operations': receipts,
        }),
        isError: evaluation.error != null,
        sideEffects: effects,
        attachments: images,
      );
    } catch (_) {
      _runtime?.close();
      _runtime = null;
      _refs.clear();
      return ToolResult(
        content: jsonEncode({
          'error': 'repl_failed',
          'operations': receipts,
          'session_reset': true,
        }),
        isError: true,
        sideEffects: effects,
        attachments: images,
      );
    } finally {
      _running = false;
    }
  }

  Map<String, Object?> _browserSnapshot(Map<String, Object?> data) {
    _refs.removeWhere((_, ref) => ref.group == 'browser');
    return {
      ...data,
      'elements': [
        for (final raw in asList(data['elements']) ?? [])
          if (asMap(raw) case final element?) _browserElement(element),
      ],
    };
  }

  Map<String, Object?> _browserElement(Map<String, Object?> element) => {
    for (final entry in element.entries)
      if (entry.key != 'check') entry.key: entry.value,
    'ref': _reference(
      'browser',
      asInt(element['id']) ?? 0,
      _browserRevision,
      asString(element['check']) ?? '',
    ),
  };

  Map<String, Object?> _phoneSnapshot(String conversation, String text) {
    final reading = readings!.latest(conversation)!;
    _refs.removeWhere((_, ref) => ref.group == 'phone');
    return {
      'text': text,
      'app': reading.tree.appLabel,
      'width': reading.tree.imageWidth > 0
          ? reading.tree.imageWidth
          : reading.tree.width,
      'height': reading.tree.imageHeight > 0
          ? reading.tree.imageHeight
          : reading.tree.height,
      'elements': [
        for (final element in reading.elements)
          {
            'id': element.id,
            'type': element.type,
            'label': element.label,
            if (element.value != null) 'value': element.value,
            'flags': element.flags,
            'ref': _reference(
              'phone',
              element.id,
              reading.tree.token,
              reading.tree.nodes[element.node].check,
            ),
          },
      ],
    };
  }

  String _reference(String group, int id, int revision, String check) {
    final key = newId();
    _refs[key] = _Reference(group, id, revision, check);
    return key;
  }

  void close() {
    _runtime?.close();
    _runtime = null;
    _refs.clear();
    _loaded.clear();
  }

  static ToolResult _error(String code) =>
      ToolResult(content: jsonEncode({'error': code}), isError: true);
}

class _ReplCapability implements Capability {
  const _ReplCapability(this.session);
  final ReplToolSession session;
  @override
  bool get isAvailable => session.skills.isNotEmpty;
}

class _ReplTool extends Tool {
  _ReplTool(this.session, this.name);
  final ReplToolSession session;
  @override
  final String name;
  @override
  Capability get requires => _ReplCapability(session);
  @override
  String get description => name == 'read_skill'
      ? 'Load the browser or phone control skill and its available API. Load it before js_repl.'
      : 'Execute JavaScript with await and persistent variables for this task. Only loaded, audited browser/phone APIs are available. Include a short operation title. Print selected results with console.log.';
  @override
  Map<String, Object?> get schema => {
    'type': 'object',
    'properties': name == 'read_skill'
        ? {
            'skill': {'type': 'string', 'enum': session.skills.toList()},
            'method': {'type': 'string', 'maxLength': 40},
          }
        : {
            'title': actionTitleSchema,
            'code': {'type': 'string', 'minLength': 1, 'maxLength': 20000},
          },
    'required': name == 'read_skill' ? ['skill'] : ['title', 'code'],
    'additionalProperties': false,
  };
  @override
  RiskLevel riskFor(Map<String, Object?> args, ToolContext ctx) =>
      RiskLevel.safe;
  @override
  Future<ToolResult> run(Map<String, Object?> args, ToolContext ctx) =>
      name == 'read_skill' ? session.readSkill(args) : session.run(args, ctx);
}

ToolRegistry replPresentation(ToolRegistry backend, ReplToolSession session) =>
    ToolRegistry([
      for (final tool in backend.allTools)
        if (!session.controlledNames.contains(tool.name)) tool,
      ...session.tools,
    ], disabledTools: backend.disabledTools);
