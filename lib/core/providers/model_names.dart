/// Presentation only: requests and saved selections always use the exact ID.
String modelDisplayName(String id, {String? suppliedName}) {
  final supplied = suppliedName?.trim();
  if (supplied != null && supplied.isNotEmpty && supplied != id) {
    return supplied;
  }
  final parts = id.split('/');
  final model = parts.last;
  String? name;
  final claude = RegExp(
    r'^claude-(haiku|sonnet|opus|fable)-(\d+)(?:[.-](\d{1,2})(?=-|$))?(.*)$',
    caseSensitive: false,
  ).firstMatch(model);
  final legacyClaude = RegExp(
    r'^claude-(\d+)(?:[.-](\d{1,2}))?-(haiku|sonnet|opus)(.*)$',
    caseSensitive: false,
  ).firstMatch(model);
  String title(String text) =>
      text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
  String suffix(String text) => text.isEmpty
      ? ''
      : ' ${text.replaceFirst(RegExp(r'^-'), '').split('-').map(title).join(' ')}';
  if (claude != null) {
    name =
        '${title(claude[1]!)} ${claude[2]}'
        '${claude[3] == null ? '' : '.${claude[3]}'}${suffix(claude[4]!)}';
  } else if (legacyClaude != null) {
    name =
        '${title(legacyClaude[3]!)} ${legacyClaude[1]}'
        '${legacyClaude[2] == null ? '' : '.${legacyClaude[2]}'}'
        '${suffix(legacyClaude[4]!)}';
  } else if (model.startsWith('gpt-') && !model.startsWith('gpt-image-')) {
    name = 'GPT ${model.substring(4).split('-').map(title).join(' ')}';
  } else if (model.startsWith('deepseek-')) {
    name = 'DeepSeek ${model.substring(9).split('-').map(title).join(' ')}';
  }
  if (name == null) return id;
  return parts.length == 1
      ? name
      : '${parts.take(parts.length - 1).join('/')} / $name';
}
