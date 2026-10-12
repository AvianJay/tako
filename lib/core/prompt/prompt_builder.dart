import 'package:mustache_template/mustache_template.dart';

import '../../app/app_info.dart';

/// Call when creating a conversation or explicitly changing its provider or
/// capabilities, then persist the returned prompt on the conversation.
final class PromptBuilder {
  PromptBuilder(String template)
    : _template = Template(template, htmlEscapeValues: false);

  final Template _template;

  /// The template's table says an empty string hides its section, but this
  /// Mustache implementation renders a section for any string. Empty strings
  /// are therefore passed as null, which renders as '' inside text.
  String render(Map<String, Object?> variables) => _template.renderString({
    for (final MapEntry(:key, :value) in {
      'app_name': kAppName,
      'device_kind': 'phone',
      'provider_name': '',
      'platform': '',
      'os_version': '',
      'device_model': '',
      'user_notes': '',
      'memory_profile': '',
      'shell_env': '',
      'markdown': true,
      'on_device': false,
      'small_model': false,
      'memory': false,
      'web_search': false,
      'browser': false,
      'files': false,
      'screen_control': false,
      'screen_elements': false,
      'screen_vision': false,
      'shortcuts': false,
      'shell': false,
      ...variables,
    }.entries)
      key: value is String && value.trim().isEmpty ? null : value,
  });
}
