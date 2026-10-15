import 'package:flutter/material.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';

final _highlighter = Highlight()
  ..registerLanguages({
    'bash': langBash,
    'css': langCss,
    'dart': langDart,
    'java': langJava,
    'javascript': langJavascript,
    'json': langJson,
    'kotlin': langKotlin,
    'python': langPython,
    'sql': langSql,
    'swift': langSwift,
    'typescript': langTypescript,
    'xml': langXml,
    'yaml': langYaml,
  });

/// Highlighted, copyable code. [note] explains why a visual block fell back
/// to its source.
class CodeBlock extends StatelessWidget {
  const CodeBlock({
    required this.code,
    required this.language,
    required this.copyLabel,
    this.onCopy,
    this.note,
    this.margin = const EdgeInsets.only(bottom: 8),
    super.key,
  });

  final String code;
  final String language;
  final String copyLabel;
  final ValueChanged<String>? onCopy;
  final String? note;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontFamily: 'monospace',
      color: scheme.onSurface,
      fontSize: 13,
    );
    var span = TextSpan(text: code, style: style);
    if (code.length <= 100000 && _highlighter.getLanguage(language) != null) {
      try {
        final renderer = TextSpanRenderer(style, {
          'keyword': TextStyle(color: scheme.primary),
          'built_in': TextStyle(color: scheme.primary),
          'string': TextStyle(color: scheme.tertiary),
          'number': TextStyle(color: scheme.secondary),
          'comment': TextStyle(
            color: scheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
          'title': TextStyle(
            color: scheme.primary,
            fontWeight: FontWeight.bold,
          ),
          'attr': TextStyle(color: scheme.secondary),
        });
        _highlighter.highlight(code: code, language: language).render(renderer);
        span = renderer.span ?? span;
      } on Object {
        // Invalid or pathological syntax remains readable as plain code.
      }
    }
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    language,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: copyLabel,
                  onPressed: onCopy == null ? null : () => onCopy!(code),
                  icon: const Icon(Icons.copy_outlined, size: 18),
                ),
              ],
            ),
          ),
          if (note case final note?)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      note,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text.rich(span),
          ),
        ],
      ),
    );
  }
}
