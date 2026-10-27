import 'dart:convert';

import 'package:flutter/services.dart';

import '../../platform/capabilities.dart';
import '../chat/agent_suspended.dart';
import '../chat/content_block.dart';
import '../providers/cancel_token.dart';
import '../repl/repl_runtime.dart';
import '../screen/screen_reading.dart';
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
  'browser.startSession': 'browser_start_session',
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

/// Methods whose argument may be the element itself: `phone.tap(element)`.
const _directElement = {'phone.tap', 'phone.longPress', 'browser.click'};

/// Methods that need an element or a point.
const _pointTargets = {'phone.tap', 'phone.longPress'};

/// The longest `phone.wait`, in milliseconds.
const _maxWaitMs = 5000;
const _waitSchema = {
  'type': 'object',
  'properties': {
    'ms': {'type': 'integer', 'minimum': 0, 'maximum': _maxWaitMs},
  },
  'required': ['ms'],
};

/// Argument names an error may repeat back. Other names are not echoed: a
/// model-made name can contain private text.
const _knownKeys = {
  'element',
  'ref',
  'id',
  'x',
  'y',
  'to_x',
  'to_y',
  'text',
  'submit',
  'direction',
  'key',
  'duration',
  'observe',
  'screenshot',
  'title',
  'type',
  'label',
  'value',
  'flags',
  'view_id',
  'bounds',
  'clickable',
};

/// What to do next, shown with a host error's code.
const _hints = <String, String>{
  'app_not_found':
      'no installed app matches; pass {package}, pick one from details.similar, or call phone.resolveApp({name: "English|中文"})',
  'ambiguous_app_name':
      'several apps match; pass {package} from details.candidates',
  'tako_in_front_open_another_app':
      'Tako itself is in front; open the target app first',
  'stale_element_read_again':
      "the screen or page changed after that element was read; use an element of the latest observation (an action's result.screen, or read again)",
  'element_changed_read_again':
      'the element changed on screen; read again and use its new element',
  'unknown_id_read_again':
      'no such element in the latest observation; read again',
  'use_a_screenshot_from_an_earlier_response':
      'x and y must come from a screenshot returned in an earlier response; in this script pass an element instead',
  'denied_by_user': 'the user declined this action; do not retry it',
  'not_editable': 'that element is not a text field',
};

class _Reference {
  const _Reference(this.group, this.id, this.revision, this.check);
  final String group;
  final int id;
  final int revision;
  final String check;
}

typedef _Resolved = ({_Reference? reference, Map<String, Object?>? failure});

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

  /// Element ids of each group's latest observation, mapped to their refs.
  final _ids = <String, Map<int, String>>{};

  /// The response whose script made each group's latest observation.
  final _observedIn = <String, String>{};

  /// The latest phone observation's app and element identities, and refs.
  String? _phoneIdentity;
  List<String> _phoneRefs = const [];
  int _browserRevision = 0;
  int _operation = 0;
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
    bool wanted(String method) =>
        method.startsWith('$skill.') &&
        (selected == null || selected == method.split('.').last);
    final apis = {
      for (final entry in methods.entries)
        if (wanted(entry.key))
          entry.key: {
            'tool': entry.value,
            'parameters': _parameters(
              entry.key,
              registry.get(entry.value)!.schema,
            ),
          },
      if (skill == 'phone' && wanted('phone.wait'))
        'phone.wait': {'parameters': _waitSchema},
    };
    if (apis.isEmpty) return _error('method_unavailable');
    final guide =
        await (loadSkill?.call(skill) ??
            rootBundle.loadString('assets/skills/$skill.md'));
    _loaded.add(skill);
    return ToolResult(
      content:
          '$guide\nHost API parameters (title defaults to the js_repl title):\n${jsonEncode(apis)}',
    );
  }

  /// A tool schema as the JavaScript API takes it: an element's ref in place
  /// of a listing id, and the title filled in from js_repl.
  static Map<String, Object?> _parameters(
    String method,
    Map<String, Object?> schema,
  ) {
    final properties = {...?asMap(schema['properties'])};
    final required = [
      for (final key in asList(schema['required']) ?? const [])
        if (key != 'title') key,
    ];
    if (properties.remove('id') != null) {
      properties['ref'] = const {
        'type': 'string',
        'description':
            'ref of an element from the latest read; passing the element object also works',
      };
      if (required.remove('id')) required.add('ref');
    }
    return {
      ...schema,
      'properties': properties,
      'required': required,
      if (_pointTargets.contains(method))
        'anyOf': [
          {
            'required': ['ref'],
          },
          {
            'required': ['x', 'y'],
          },
        ],
    };
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
            return _failure(
              '${group}_skill_not_loaded',
              'call read_skill with skill "$group" first',
            );
          }
          if (method == 'phone.wait' && skills.contains('phone')) {
            return _wait(arguments, context.cancel);
          }
          final name = methods[method];
          if (name == null) {
            final offered = [
              for (final known in methods.keys)
                if (known.startsWith('$group.')) known,
              if (group == 'phone' && skills.contains('phone')) 'phone.wait',
            ];
            return _failure(
              'method_unavailable',
              'this device offers ${offered.join(', ')}',
            );
          }
          final tool = registry.get(name);
          if (tool == null) return const {'error': 'tool_unavailable'};
          if (arguments.length > 1) {
            return _failure(
              'one_argument_object_expected',
              'pass one object: $method({...})',
            );
          }
          final direct = _directElement.contains(method);
          var value = arguments.firstOrNull;
          // phone.tap(element.ref)
          if (direct && value is String) value = {'ref': value};
          if (value != null && value is! Map<String, Object?>) {
            return _failure(
              'argument_object_expected',
              'pass one object: $method({...})',
            );
          }
          var params = Map<String, Object?>.of(
            value as Map<String, Object?>? ?? {},
          );
          final properties = asMap(tool.schema['properties']) ?? {};
          Object? handle;
          if (properties.containsKey('id')) {
            if (direct &&
                params['ref'] is String &&
                !params.containsKey('element')) {
              // The argument is the element itself, or {ref}: keep options.
              handle = params['ref'];
              params = {
                for (final key in const ['observe', 'screenshot'])
                  if (params.containsKey(key)) key: params[key],
              };
            } else {
              final given = [
                for (final key in const ['element', 'ref', 'id'])
                  if (params.containsKey(key)) key,
              ];
              if (given.length > 1) {
                return _failure(
                  'one_element_reference',
                  'pass only one of element, ref or id',
                );
              }
              if (given.isNotEmpty) {
                handle = params.remove(given.single);
                if (handle == null) return _targetRequired(method, null);
              }
            }
          }
          if (properties.containsKey('title')) {
            params.putIfAbsent('title', () => title);
          }
          _Reference? reference;
          if (handle != null) {
            final resolved = _resolve(method, handle, context);
            if (resolved.failure case final failure?) return failure;
            reference = resolved.reference!;
            params['id'] = reference.id;
          } else if (direct && !(params['x'] is num && params['y'] is num)) {
            return _targetRequired(method, value);
          }
          if (group == 'phone' &&
              (params.containsKey('x') || params.containsKey('to_x')) &&
              _observedIn['phone'] == context.messageId) {
            const code = 'use_a_screenshot_from_an_earlier_response';
            return _failure(code, _hints[code]);
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
            final code = '${data?['error'] ?? 'operation_failed'}';
            return _failure(code, _hints[code], {
              for (final entry in (data ?? const {}).entries)
                if (entry.key != 'error') entry.key: entry.value,
            });
          }
          if (name == 'browser_read' && result.data != null) {
            _browserRevision++;
            _observedIn['browser'] = context.messageId;
            return _browserSnapshot(result.data!);
          }
          final reading = readings?.latest(context.conversationId);
          if (group == 'phone' &&
              reading != null &&
              reading.tree.token != before) {
            _observedIn['phone'] = context.messageId;
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
      if (evaluation.reset) _forget();
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
    } on AgentSuspended {
      close();
      rethrow;
    } catch (_) {
      _runtime?.close();
      _runtime = null;
      _forget();
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

  /// The reference that an element, its ref or a listing id names, or the
  /// failure to report.
  _Resolved _resolve(String method, Object? handle, ToolContext context) {
    final group = method.split('.').first;
    _Resolved fail(String code, String? hint) =>
        (reference: null, failure: _failure(code, hint));
    if (handle is Map) handle = handle['ref'] ?? handle['id'];
    final String? key;
    if (handle is String) {
      key = handle;
    } else if (handle is num && handle == handle.roundToDouble()) {
      // A bare id names an element of a listing the model has already seen.
      // A script that read again itself may hold ids of an older listing.
      if (_observedIn[group] == context.messageId) {
        return fail(
          'pass_the_element_not_its_id',
          'this response read the $group itself, so pass the element or element.ref; a bare id only names an element of a listing printed in an earlier response',
        );
      }
      key = _ids[group]?[handle.toInt()];
      if (key == null) {
        return fail('unknown_id_read_again', _hints['unknown_id_read_again']);
      }
    } else {
      return (reference: null, failure: _targetRequired(method, handle));
    }
    final reference = _refs[key];
    final revision = group == 'browser'
        ? _browserRevision
        : readings?.latest(context.conversationId)?.tree.token;
    if (reference == null ||
        reference.group != group ||
        reference.revision != revision) {
      return fail(
        'stale_element_read_again',
        _hints['stale_element_read_again'],
      );
    }
    return (reference: reference, failure: null);
  }

  static Map<String, Object?> _targetRequired(String method, Object? value) {
    final group = method.split('.').first;
    return _failure(
      'element_reference_required',
      value == null
          ? "$method got no element (null or undefined): nothing matched in the latest $group observation's elements"
          : '$method needs an element from the latest $group observation: pass the element itself, {ref: element.ref} or {element}'
                '${_pointTargets.contains(method) ? ', or {x, y} from a screenshot returned in an earlier response' : ''}',
      {
        if (value is Map)
          'received_keys': [
            for (final key in value.keys)
              _knownKeys.contains(key) ? key : '(other)',
          ],
      },
    );
  }

  /// A host error for JavaScript: its code, what to do next, and details.
  static Map<String, Object?> _failure(
    String code, [
    String? hint,
    Map<String, Object?>? details,
  ]) {
    final extra = details == null || details.isEmpty
        ? null
        : jsonEncode(details);
    return {
      'error': code,
      'message': [
        code,
        if (hint != null) ': $hint',
        if (extra != null)
          ' ${extra.length > 600 ? '${extra.substring(0, 600)}…' : extra}',
      ].join(),
      if (extra != null) 'details': details,
    };
  }

  /// Lets an animation or a loading screen finish without reading it.
  static Future<Map<String, Object?>> _wait(
    List<Object?> arguments,
    CancelToken cancel,
  ) async {
    final options = arguments.length == 1 ? asMap(arguments.single) : null;
    final ms = options?['ms'];
    if (ms is! num || !ms.isFinite || ms < 0 || ms > _maxWaitMs) {
      return _failure(
        'invalid_arguments',
        'phone.wait({ms}) waits 0..$_maxWaitMs milliseconds',
      );
    }
    await cancel.bind(Future<void>.delayed(Duration(milliseconds: ms.round())));
    return {'waited_ms': ms.round()};
  }

  Map<String, Object?> _browserSnapshot(Map<String, Object?> data) {
    _refs.removeWhere((_, ref) => ref.group == 'browser');
    final ids = _ids['browser'] = {};
    return {
      ...data,
      'elements': [
        for (final raw in asList(data['elements']) ?? [])
          if (asMap(raw) case final element?) _browserElement(element, ids),
      ],
    };
  }

  Map<String, Object?> _browserElement(
    Map<String, Object?> element,
    Map<int, String> ids,
  ) {
    final id = asInt(element['id']) ?? 0;
    final ref = _reference(
      'browser',
      id,
      _browserRevision,
      asString(element['check']) ?? '',
    );
    ids[id] = ref;
    return {
      for (final entry in element.entries)
        if (entry.key != 'check') entry.key: entry.value,
      'ref': ref,
    };
  }

  Map<String, Object?> _phoneSnapshot(String conversation, String text) {
    final reading = readings!.latest(conversation)!;
    final tree = reading.tree;
    final checks = [
      for (final element in reading.elements) tree.nodes[element.node].check,
    ];
    // An unchanged screen keeps its refs, so elements saved before another
    // read, or before an action that changed nothing, still work. Any change
    // mints new refs: a saved ref never moves to a different element.
    final identity = checks.any((check) => check.isEmpty)
        ? null
        : [tree.packageName, ...checks].join('\n');
    final kept = identity != null && identity == _phoneIdentity
        ? _phoneRefs
        : null;
    _refs.removeWhere((_, ref) => ref.group == 'phone');
    final ids = _ids['phone'] = {};
    // Bounds use the unit of x and y: screenshot pixels when one is attached.
    final scaleX = reading.hasImage ? tree.imageWidth / tree.width : 1.0;
    final scaleY = reading.hasImage ? tree.imageHeight / tree.height : 1.0;
    final refs = <String>[];
    final elements = <Map<String, Object?>>[];
    for (final (index, element) in reading.elements.indexed) {
      final node = tree.nodes[element.node];
      final ref = _reference(
        'phone',
        element.id,
        tree.token,
        checks[index],
        key: kept?[index],
      );
      refs.add(ref);
      ids[element.id] = ref;
      final viewId = screenText(node.viewId, 120);
      elements.add({
        'id': element.id,
        'type': element.type,
        'label': element.label,
        if (element.value != null) 'value': element.value,
        'view_id': ?viewId,
        'clickable': node.clickable,
        'bounds': {
          'x1': (node.bounds.left * scaleX).round(),
          'y1': (node.bounds.top * scaleY).round(),
          'x2': (node.bounds.right * scaleX).round(),
          'y2': (node.bounds.bottom * scaleY).round(),
        },
        'flags': element.flags,
        'ref': ref,
      });
    }
    _phoneIdentity = identity;
    _phoneRefs = refs;
    return {
      'text': text,
      'app': tree.appLabel,
      'width': reading.hasImage ? tree.imageWidth : tree.width,
      'height': reading.hasImage ? tree.imageHeight : tree.height,
      'elements': elements,
    };
  }

  String _reference(
    String group,
    int id,
    int revision,
    String check, {
    String? key,
  }) {
    final ref = key ?? newId();
    _refs[ref] = _Reference(group, id, revision, check);
    return ref;
  }

  void _forget() {
    _refs.clear();
    _ids.clear();
    _phoneIdentity = null;
    _phoneRefs = const [];
  }

  void close() {
    _runtime?.close();
    _runtime = null;
    _forget();
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
