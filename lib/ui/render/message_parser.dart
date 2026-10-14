import 'package:markdown/markdown.dart' as md;

/// Non-Markdown content is retained separately so it cannot become raw HTML.
sealed class MarkupFragment {
  const MarkupFragment(this.source);
  final String source;
}

class RenderMath extends MarkupFragment {
  const RenderMath(super.source, {required this.tex, required this.display});
  final String tex;
  final bool display;
}

class RenderTag extends MarkupFragment {
  const RenderTag(super.source, {required this.name, required this.attributes});
  final String name;
  final Map<String, String> attributes;
}

class RenderLiteral extends MarkupFragment {
  const RenderLiteral(super.source);
}

class ParsedMessage {
  const ParsedMessage({
    required this.nodes,
    required this.fragments,
    required this.buffered,
  });

  final List<md.Node> nodes;
  final Map<String, MarkupFragment> fragments;

  /// The incomplete suffix, withheld until it closes or streaming ends.
  final String buffered;

  String restoreLiteralTokens(String value) {
    for (final entry in fragments.entries) {
      value = value.replaceAll(entry.key, entry.value.source);
    }
    return value;
  }
}

/// Parses a complete snapshot of a message, including snapshots during SSE.
/// Code and escaped dollars take precedence over the custom math/tag syntax.
ParsedMessage parseMessageMarkup(
  String data, {
  bool isStreaming = false,
  Set<String> customTags = const {'image', 'file'},
}) {
  var prefix = '\uE000tako';
  while (data.contains(prefix)) {
    prefix += '_';
  }
  final fragments = <String, MarkupFragment>{};
  final output = StringBuffer();
  var buffered = '';
  var position = 0;

  void addFragment(MarkupFragment fragment) {
    final marker = '$prefix${fragments.length}\uE001';
    fragments[marker] = fragment;
    output.write(marker);
  }

  while (position < data.length) {
    final atLineStart = position == 0 || data[position - 1] == '\n';
    final char = data[position];
    if (char != r'$' &&
        char != r'\' &&
        char != '`' &&
        char != '<' &&
        !atLineStart) {
      output.write(char);
      position++;
      continue;
    }
    final rest = data.substring(position);
    if (atLineStart) {
      final fence = RegExp(
        r'^(?:[ \t]*>[ \t]?)*[ \t]*(?:(?:[-+*]|\d+[.)])[ \t]+)?(`{3,}|~{3,})([^\n]*)',
      ).firstMatch(rest);
      if (fence != null) {
        final run = fence[1]!;
        final firstNewline = rest.indexOf('\n');
        final closer = RegExp(
          '^[ \\t>]*${RegExp.escape(run[0])}{${run.length},}[ \\t]*\\r?\$',
          multiLine: true,
        );
        final match = firstNewline < 0
            ? null
            : closer.firstMatch(rest.substring(firstNewline + 1));
        if (match == null) {
          if (isStreaming) {
            buffered = rest;
          } else {
            output.write(rest);
          }
          break;
        }
        final length = firstNewline + 1 + match.end;
        output.write(rest.substring(0, length));
        position += length;
        continue;
      }
      // A fence may itself be split between network chunks.
      if (isStreaming &&
          RegExp(
            r'^(?:[ \t]*>[ \t]?)*[ \t]*(?:(?:[-+*]|\d+[.)])[ \t]+)?[`~]{1,2}$',
          ).hasMatch(rest)) {
        buffered = rest;
        break;
      }
    }

    if (rest.startsWith('`')) {
      final run = RegExp(r'^`+').firstMatch(rest)![0]!;
      var end = rest.indexOf(run, run.length);
      while (end >= 0 &&
          ((end > 0 && rest[end - 1] == '`') ||
              (end + run.length < rest.length &&
                  rest[end + run.length] == '`'))) {
        end = rest.indexOf(run, end + run.length);
      }
      if (end < 0) {
        if (isStreaming) {
          buffered = rest;
        } else {
          addFragment(RenderLiteral(rest));
        }
        break;
      }
      final length = end + run.length;
      output.write(rest.substring(0, length));
      position += length;
      continue;
    }

    String? opener;
    String? closer;
    var display = false;
    if (rest.startsWith(r'\(')) {
      opener = r'\(';
      closer = r'\)';
    } else if (rest.startsWith(r'\[')) {
      opener = r'\[';
      closer = r'\]';
      display = true;
    } else if (rest.startsWith(r'$$')) {
      opener = closer = r'$$';
      display = true;
    } else if (rest.startsWith(r'$') &&
        (rest.length == 1 || !_isWhitespace(rest[1]))) {
      opener = closer = r'$';
    }
    if (opener != null) {
      final end = _mathEnd(rest, opener.length, closer!, opener == r'$');
      if (end < 0) {
        if (isStreaming) {
          buffered = rest;
          break;
        }
        // Retain unmatched delimiters exactly, including backslashes.
        addFragment(RenderLiteral(opener));
        position += opener.length;
        continue;
      }
      final length = end + closer.length;
      addFragment(
        RenderMath(
          rest.substring(0, length),
          tex: rest.substring(opener.length, end),
          display: display,
        ),
      );
      position += length;
      continue;
    }

    if (rest.startsWith(r'\')) {
      final length = rest.length >= 2 ? 2 : 1;
      // Let Markdown's escape syntax consume escaped punctuation.
      output.write(rest.substring(0, length));
      position += length;
      continue;
    }

    if (rest.startsWith('<') &&
        (rest.length == 1 || RegExp(r'^</?[A-Za-z!]').hasMatch(rest)) &&
        !RegExp(
          r'^<(?:https?://|mailto:)',
          caseSensitive: false,
        ).hasMatch(rest)) {
      final end = _tagEnd(rest);
      if (end < 0) {
        if (isStreaming) {
          buffered = rest;
        } else {
          addFragment(RenderLiteral(rest));
        }
        break;
      }
      final source = rest.substring(0, end + 1);
      final tag = _parseTag(source);
      final closing = RegExp(
        r'^</([A-Za-z][A-Za-z0-9_-]*)\s*>$',
      ).firstMatch(source)?[1]?.toLowerCase();
      addFragment(
        tag != null && customTags.contains(tag.name)
            ? tag
            // Models sometimes close a custom tag like HTML; drop the closer.
            : RenderLiteral(customTags.contains(closing) ? '' : source),
      );
      position += source.length;
      continue;
    }

    output.write(data[position]);
    position++;
  }

  final document = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
    inlineSyntaxes: [_FragmentSyntax(prefix, fragments)],
  );
  return ParsedMessage(
    nodes: document.parse(output.toString()),
    fragments: Map.unmodifiable(fragments),
    buffered: buffered,
  );
}

bool _isWhitespace(String value) => value.trim().isEmpty;
bool _isDigit(String value) => RegExp(r'^[0-9]$').hasMatch(value);

int _mathEnd(
  String source,
  int start,
  String delimiter,
  bool dollarHeuristics,
) {
  for (var index = start; index < source.length; index++) {
    if (source.startsWith(delimiter, index)) {
      if (!dollarHeuristics ||
          (index > start &&
              !_isWhitespace(source[index - 1]) &&
              (index + 1 == source.length || !_isDigit(source[index + 1])))) {
        return index;
      }
    }
    if (source[index] == r'\') index++;
  }
  return -1;
}

int _tagEnd(String source) {
  String? quote;
  for (var index = 1; index < source.length; index++) {
    final char = source[index];
    if (quote != null) {
      if (char == quote) quote = null;
    } else if (char == '"' || char == "'") {
      quote = char;
    } else if (char == '>') {
      return index;
    }
  }
  return -1;
}

/// Self-closing is canonical, but `<image src="x">` is accepted as well.
RenderTag? _parseTag(String source) {
  final head = RegExp(r'^<([A-Za-z][A-Za-z0-9_-]*)\b').firstMatch(source);
  if (head == null) return null;
  final attributes = <String, String>{};
  final contents = source
      .substring(head.end, source.length - 1)
      .replaceFirst(RegExp(r'/\s*$'), '');
  final attribute = RegExp(
    r'''\s+([A-Za-z_][A-Za-z0-9_:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
  );
  var position = 0;
  while (position < contents.length) {
    if (contents.substring(position).trim().isEmpty) break;
    final match = attribute.matchAsPrefix(contents, position);
    if (match == null) return null;
    attributes[match[1]!.toLowerCase()] = match[2] ?? match[3]!;
    position = match.end;
  }
  return RenderTag(
    source,
    name: head[1]!.toLowerCase(),
    attributes: Map.unmodifiable(attributes),
  );
}

class _FragmentSyntax extends md.InlineSyntax {
  _FragmentSyntax(String prefix, this.fragments)
    : super('${RegExp.escape(prefix)}[0-9]+\uE001');
  final Map<String, MarkupFragment> fragments;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final marker = match[0]!;
    final fragment = fragments[marker]!;
    if (fragment is RenderLiteral) {
      parser.addNode(md.Text(fragment.source));
    } else {
      parser.addNode(
        md.Element.empty('tako-fragment')..attributes['marker'] = marker,
      );
    }
    return true;
  }
}
