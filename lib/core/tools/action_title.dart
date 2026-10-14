import '../chat/content_block.dart';
import '../util/json.dart';

const actionTitleSchema = {
  'type': 'string',
  'minLength': 1,
  'maxLength': 80,
  'description':
      'A short title describing this operation in the user\'s language, '
      'shown while it runs. Describe the action, not private screen contents.',
};

/// Display metadata only. Risk classification still uses the live target.
String? actionTitle(Map<String, Object?> args) {
  final value = args['title'];
  if (value is! String || value.length > 80) return null;
  final title = value.replaceAll(RegExp(r'[\s\x00-\x1f\x7f]+'), ' ').trim();
  return title.isEmpty ? null : title;
}

String? phoneActionTitle(ToolCallBlock call) {
  if (!const {
    'read_screen',
    'tap',
    'long_press',
    'swipe',
    'scroll',
    'type_text',
    'press_key',
    'open_app',
    'js_repl',
    'open_url',
    'remote_control',
    'screen_sequence',
    'screen_workflow',
    'screen_replay',
  }.contains(call.name)) {
    return null;
  }
  final args = tryDecodeObject(call.arguments);
  return args == null ? null : actionTitle(args);
}
