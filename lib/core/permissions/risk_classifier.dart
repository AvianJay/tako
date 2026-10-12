import '../tools/tool.dart';
import 'permission_policy.dart';

/// Defense in depth for screen, browser, and shell tools.
class RiskClassifier {
  const RiskClassifier._();

  static bool isPasswordEntry(
    String toolName,
    Map<String, Object?> args,
    ToolContext context,
  ) =>
      const {'type_text', 'browser_type'}.contains(toolName) &&
      (context.targetIsPassword ||
          args['isPassword'] == true ||
          args['inputType'] == 'password');

  static RiskLevel classify({
    required String toolName,
    required RiskLevel declaredRisk,
    required Map<String, Object?> args,
    required ToolContext context,
    List<String> highRiskKeywords = PermissionPolicy.defaultHighRiskKeywords,
  }) {
    if (toolName == 'run_shell') {
      final command = args['command'];
      return command is String && isReadOnlyShell(command)
          ? _maximum(declaredRisk, RiskLevel.sensitive)
          : RiskLevel.high;
    }
    // Submitting a form by typing is a click on its submit control. The
    // browser tool resolves the form's submit labels into targetLabel.
    if (const {'tap', 'long_press', 'browser_click'}.contains(toolName) ||
        toolName == 'browser_type' && args['submit'] == true) {
      final labels = [context.targetLabel, args['label']].whereType<String>();
      for (final label in labels) {
        final normalized = label.toLowerCase();
        if (highRiskKeywords.any(
          (keyword) =>
              keyword.isNotEmpty && normalized.contains(keyword.toLowerCase()),
        )) {
          return RiskLevel.high;
        }
      }
    }
    return declaredRisk;
  }

  static RiskLevel _maximum(RiskLevel a, RiskLevel b) =>
      a.index >= b.index ? a : b;

  /// Deliberately conservative: shell expansion, substitutions, redirection,
  /// compound commands, executable find predicates, and date mutation all ask.
  static bool isReadOnlyShell(String command) {
    if (command.trim().isEmpty ||
        RegExp(r'[\n\r\x00<>;&`$(){}\\#!]').hasMatch(command) ||
        command.contains('||')) {
      return false;
    }
    for (final segment in command.split('|')) {
      final tokens = _tokens(segment);
      if (tokens == null || tokens.isEmpty) return false;
      if (!const {
        'ls',
        'cat',
        'head',
        'tail',
        'grep',
        'find',
        'df',
        'du',
        'uname',
        'ps',
        'pwd',
        'wc',
        'date',
        'echo',
      }.contains(tokens.first)) {
        return false;
      }
      if (tokens.first == 'find' &&
          tokens.any(
            (value) => const {
              '-exec',
              '-execdir',
              '-ok',
              '-okdir',
              '-delete',
              '-fprint',
              '-fprint0',
              '-fprintf',
              '-fls',
            }.contains(value.toLowerCase()),
          )) {
        return false;
      }
      if (tokens.first == 'date' &&
          tokens
              .skip(1)
              .any(
                (value) =>
                    value.startsWith('-s') ||
                    value.startsWith('--set') ||
                    (!value.startsWith('-') && !value.startsWith('+')),
              )) {
        return false;
      }
    }
    return true;
  }

  static List<String>? _tokens(String value) {
    final tokens = <String>[];
    final current = StringBuffer();
    String? quote;
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      if (quote != null) {
        if (char == quote) {
          quote = null;
        } else {
          current.write(char);
        }
      } else if (char == '"' || char == "'") {
        quote = char;
      } else if (char.trim().isEmpty) {
        if (current.isNotEmpty) {
          tokens.add(current.toString());
          current.clear();
        }
      } else {
        current.write(char);
      }
    }
    if (quote != null) return null;
    if (current.isNotEmpty) tokens.add(current.toString());
    return tokens;
  }
}
