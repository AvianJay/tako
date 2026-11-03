import 'dart:convert';

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

/// An HTML formatting tag such as `<mark>`, `</span>` or `<br>`. The parser
/// pairs openers with closers into [element]s, so renderers never see one.
class RenderFormat extends MarkupFragment {
  const RenderFormat(
    super.source, {
    required this.element,
    this.attributes = const {},
    this.closing = false,
  });

  /// The Markdown element it becomes: `<b>` becomes `strong`, for example.
  final String element;

  /// For `mark` and `span`: `color` for the text, `background` for the
  /// highlighter.
  final Map<String, String> attributes;
  final bool closing;
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
      // `\[!NOTE\]` is valid on GitHub; unescape it before `\[` becomes math.
      final escapedCallout = RegExp(
        r'^((?:[ \t]*>)+[ \t]*)\\\[!([A-Za-z]+)\\\]',
      ).firstMatch(rest);
      if (escapedCallout != null) {
        output.write('${escapedCallout[1]}[!${escapedCallout[2]}]');
        position += escapedCallout[0]!.length;
        continue;
      }
      // A callout marker split between network chunks would otherwise show
      // as a plain quote for a moment.
      if (isStreaming &&
          RegExp(r'^(?:[ \t]*>)+[ \t]*\\?\[(?:!\w*)?$').hasMatch(rest)) {
        buffered = rest;
        break;
      }
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
          r'^<(?:https?://|mailto:|tel:|sms:|geo:)',
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
            : customTags.contains(closing)
            ? const RenderLiteral('')
            : _formatTag(
                    source,
                    tag ?? _parseTag(source, lenient: true),
                    closing,
                  ) ??
                  RenderLiteral(source),
      );
      position += source.length;
      continue;
    }

    output.write(data[position]);
    position++;
  }

  final fragmentSyntax = _FragmentSyntax(prefix, fragments);
  final document = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
    blockSyntaxes: [
      const _CalloutSyntax(),
      _DetailsSyntax(fragmentSyntax.pattern, fragments),
      const _FootnoteSyntax(),
    ],
    inlineSyntaxes: [fragmentSyntax, _HighlightSyntax(), _SpoilerSyntax()],
  );
  return ParsedMessage(
    nodes: _pairFormats(document.parse(output.toString()), fragments),
    fragments: Map.unmodifiable(fragments),
    buffered: buffered,
  );
}

/// HTML formatting tags models write, and the element each one becomes.
const _formatElements = {
  'mark': 'mark',
  'span': 'span',
  'font': 'span',
  'u': 'u',
  'ins': 'u',
  'sub': 'sub',
  'sup': 'sup',
  'small': 'small',
  'kbd': 'kbd',
  'b': 'strong',
  'strong': 'strong',
  'i': 'em',
  'em': 'em',
  's': 'del',
  'del': 'del',
  'strike': 'del',
  'ruby': 'ruby',
  'rt': 'rt',
  'rp': 'rp',
  'badge': 'badge',
  'spoiler': 'spoiler',
  'details': 'details',
  'summary': 'summary',
};

/// The formatting tag [source] is, or null for any other tag. Colours are
/// read from `color`, `background` and inline CSS alike.
RenderFormat? _formatTag(String source, RenderTag? tag, String? closing) {
  if (closing == 'br' || tag?.name == 'br') {
    return RenderFormat(source, element: 'br');
  }
  if (closing != null) {
    final element = _formatElements[closing];
    return element == null
        ? null
        : RenderFormat(source, element: element, closing: true);
  }
  final element = _formatElements[tag?.name];
  if (tag == null || element == null) return null;
  if (element == 'details') {
    return RenderFormat(
      source,
      element: element,
      attributes: {if (tag.attributes.containsKey('open')) 'open': ''},
    );
  }
  if (element != 'mark' && element != 'span' && element != 'badge') {
    return RenderFormat(source, element: element);
  }
  final css = {
    for (final declaration in (tag.attributes['style'] ?? '').split(';'))
      if (declaration.indexOf(':') case final colon when colon > 0)
        declaration.substring(0, colon).trim().toLowerCase(): declaration
            .substring(colon + 1)
            .trim(),
  };
  final mark = element == 'mark';
  final color = mark ? css['color'] : tag.attributes['color'] ?? css['color'];
  final background =
      (mark ? tag.attributes['color'] : null) ??
      tag.attributes['background'] ??
      tag.attributes['bg'] ??
      tag.attributes['highlight'] ??
      css['background-color'] ??
      css['background'];
  return RenderFormat(
    source,
    element: element,
    // A badge has a single hue, whichever way it was given.
    attributes: element == 'badge'
        ? {'color': ?color ?? background}
        : {'color': ?color, 'background': ?background},
  );
}

/// Pairs formatting tags among siblings as a browser does: an opener without
/// a closer runs to the end of its parent, and a stray closer is dropped.
/// Children pair first, so a tag never reaches outside its parent.
List<md.Node> _pairFormats(
  List<md.Node> nodes,
  Map<String, MarkupFragment> fragments,
) {
  final open = <(RenderFormat?, List<md.Node>)>[(null, [])];
  void closeLast() {
    final (format, children) = open.removeLast();
    open.last.$2.add(
      md.Element(format!.element, children)
        ..attributes.addAll(format.attributes),
    );
  }

  for (final node in nodes) {
    final format = node is md.Element && node.tag == 'tako-fragment'
        ? fragments[node.attributes['marker']]
        : null;
    if (format is! RenderFormat) {
      // Some child lists are fixed-length, so the element is rebuilt.
      open.last.$2.add(
        node is md.Element && (node.children?.isNotEmpty ?? false)
            ? (md.Element(node.tag, _pairFormats(node.children!, fragments))
                ..attributes.addAll(node.attributes)
                ..generatedId = node.generatedId
                ..footnoteLabel = node.footnoteLabel)
            : node,
      );
    } else if (format.element == 'br') {
      open.last.$2.add(md.Element.empty('br'));
    } else if (!format.closing) {
      // As in HTML, a new annotation ends the one before it.
      if ({'rt', 'rp'}.contains(format.element) &&
          {'rt', 'rp'}.contains(open.last.$1?.element)) {
        closeLast();
      }
      open.add((format, []));
    } else {
      final index = open.lastIndexWhere(
        (entry) => entry.$1?.element == format.element,
      );
      if (index > 0) {
        while (open.length > index) {
          closeLast();
        }
      }
    }
  }
  while (open.length > 1) {
    closeLast();
  }
  return open.single.$2;
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
///
/// Formatting tags are parsed [lenient]ly: their values may also be bare, as
/// in `<font color=red>`, or missing, as in `<details open>`. Host tags such
/// as `<image>` must quote every value.
RenderTag? _parseTag(String source, {bool lenient = false}) {
  final head = RegExp(r'^<([A-Za-z][A-Za-z0-9_-]*)\b').firstMatch(source);
  if (head == null) return null;
  final attributes = <String, String>{};
  final contents = source
      .substring(head.end, source.length - 1)
      .replaceFirst(RegExp(r'/\s*$'), '');
  final attribute = lenient
      ? RegExp(
          r'''\s+([A-Za-z_][A-Za-z0-9_:.-]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?''',
        )
      : RegExp(
          r'''\s+([A-Za-z_][A-Za-z0-9_:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
        );
  var position = 0;
  while (position < contents.length) {
    if (contents.substring(position).trim().isEmpty) break;
    final match = attribute.matchAsPrefix(contents, position);
    if (match == null) return null;
    attributes[match[1]!.toLowerCase()] =
        match[2] ?? match[3] ?? match[4] ?? '';
    position = match.end;
  }
  return RenderTag(
    source,
    name: head[1]!.toLowerCase(),
    attributes: Map.unmodifiable(attributes),
  );
}

/// Callout types and the aliases models borrow from other Markdown flavours.
const calloutTypes = {
  'note': 'note',
  'info': 'note',
  'todo': 'note',
  'abstract': 'note',
  'summary': 'note',
  'tip': 'tip',
  'hint': 'tip',
  'success': 'tip',
  'check': 'tip',
  'done': 'tip',
  'important': 'important',
  'question': 'important',
  'warning': 'warning',
  'warn': 'warning',
  'attention': 'warning',
  'caution': 'caution',
  'danger': 'caution',
  'error': 'caution',
  'failure': 'caution',
  'bug': 'caution',
};

/// `> [!NOTE] Optional title` quotes, parsed as `tako-callout` elements with
/// an optional `tako-callout-title` first child. Built on the blockquote
/// syntax, so nested lists, code and the end of the quote behave as in any
/// other quote.
class _CalloutSyntax extends md.BlockquoteSyntax {
  const _CalloutSyntax();

  static final _marker = RegExp(r'^ {0,3}>[ \t]*\[!([A-Za-z]+)\][ \t]*(.*)$');

  @override
  bool canParse(md.BlockParser parser) {
    final match = _marker.firstMatch(parser.current.content);
    return match != null && calloutTypes.containsKey(match[1]!.toLowerCase());
  }

  @override
  List<md.Line> parseChildLines(md.BlockParser parser) =>
      super.parseChildLines(parser).sublist(1);

  @override
  md.Node parse(md.BlockParser parser) {
    final match = _marker.firstMatch(parser.current.content)!;
    final quote = super.parse(parser) as md.Element;
    final title = match[2]!.trim();
    return md.Element('tako-callout', [
      if (title.isNotEmpty)
        md.Element('tako-callout-title', [md.UnparsedContent(title)]),
      ...?quote.children,
    ])..attributes['type'] = calloutTypes[match[1]!.toLowerCase()]!;
  }
}

/// `==text==` marks text with a highlighter, as in Obsidian and many other
/// editors. Like `~~`, it may sit inside a word, which Chinese needs.
class _HighlightSyntax extends md.DelimiterSyntax {
  _HighlightSyntax()
    : super(
        '=+',
        requiresDelimiterRun: true,
        allowIntraWord: true,
        startCharacter: 0x3d,
        tags: [md.DelimiterTag('mark', 2)],
      );
}

/// `||text||` hides text until it is tapped, as in Discord.
class _SpoilerSyntax extends md.DelimiterSyntax {
  _SpoilerSyntax()
    : super(
        r'\|+',
        requiresDelimiterRun: true,
        allowIntraWord: true,
        startCharacter: 0x7c,
        tags: [md.DelimiterTag('spoiler', 2)],
      );
}

/// A `<details>` that starts a line, as a `details` element whose first child
/// may be a `tako-summary`. The lines up to the matching `</details>` are
/// parsed as blocks, so lists, code and quotes inside keep working. A
/// `<details>` inside a line stays inline and simply shows its content.
class _DetailsSyntax extends md.BlockSyntax {
  _DetailsSyntax(this._marker, this.fragments)
    : pattern = RegExp('^[ \t]{0,3}(?:${_marker.pattern})');

  /// Matches any fragment marker, as [_FragmentSyntax] does.
  final RegExp _marker;
  final Map<String, MarkupFragment> fragments;

  @override
  final RegExp pattern;

  RenderFormat? _format(Match match, String element) =>
      switch (fragments[match[0]]) {
        final RenderFormat format when format.element == element => format,
        _ => null,
      };

  @override
  bool canParse(md.BlockParser parser) {
    final line = parser.current.content.trimLeft();
    final match = pattern.hasMatch(parser.current.content)
        ? _marker.matchAsPrefix(line)
        : null;
    final format = match == null ? null : _format(match, 'details');
    return format != null && !format.closing;
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final lines = <String>[];
    String? summary;
    var open = false;
    var depth = 0;
    while (!parser.isDone) {
      var line = parser.current.content;
      if (depth == 0) {
        final opener = _marker.firstMatch(line)!;
        open = _format(opener, 'details')!.attributes.containsKey('open');
        line = line.substring(opener.end);
        depth = 1;
      }
      // The summary comes before any content, on this line or the next.
      final trimmed = line.trimLeft();
      if (summary == null && lines.every((l) => l.trim().isEmpty)) {
        final summaryOpen = _marker.matchAsPrefix(trimmed);
        if (summaryOpen != null &&
            !(_format(summaryOpen, 'summary')?.closing ?? true)) {
          final close = _marker
              .allMatches(trimmed, summaryOpen.end)
              .where((m) => _format(m, 'summary')?.closing ?? false)
              .firstOrNull;
          summary = trimmed.substring(summaryOpen.end, close?.start).trim();
          line = close == null ? '' : trimmed.substring(close.end);
        }
      }
      String? leftover;
      for (final match in _marker.allMatches(line)) {
        final format = _format(match, 'details');
        if (format == null) continue;
        depth += format.closing ? -1 : 1;
        if (depth == 0) {
          leftover = line.substring(match.end);
          line = line.substring(0, match.start);
          break;
        }
      }
      if (line.trim().isNotEmpty || lines.isNotEmpty) lines.add(line);
      if (depth == 0 && leftover != null && leftover.trim().isNotEmpty) {
        // Text after the closing tag is put back as the next line, so it
        // starts the next block instead of disappearing.
        try {
          parser.lines[parser.lines.indexOf(parser.current)] = md.Line(
            leftover.trimLeft(),
          );
          break;
        } on UnsupportedError {
          lines.add(leftover);
        }
      }
      parser.advance();
      if (depth == 0) break;
    }
    final children = md.BlockParser(
      lines.map(md.Line.new).toList(),
      parser.document,
    ).parseLines();
    return md.Element('details', [
      if (summary != null && summary.isNotEmpty)
        md.Element('tako-summary', [md.UnparsedContent(summary)]),
      ...children,
    ])..attributes.addAll({if (open) 'open': ''});
  }
}

/// Footnote definitions that keep their Markdown in a `source` attribute,
/// so a tapped reference can show the note on its own.
class _FootnoteSyntax extends md.FootnoteDefSyntax {
  const _FootnoteSyntax();

  @override
  md.Node? parse(md.BlockParser parser) {
    final start = parser.lines.indexOf(parser.current);
    final node = super.parse(parser);
    final end = parser.isDone
        ? parser.lines.length
        : parser.lines.indexOf(parser.current);
    if (node is md.Element && start >= 0 && end > start) {
      final lines = [
        for (final (i, line) in parser.lines.sublist(start, end).indexed)
          i == 0
              ? line.content.substring(pattern.firstMatch(line.content)!.end)
              : line.content.replaceFirst(RegExp('^ {1,4}|^\t'), ''),
      ];
      node.attributes['source'] = lines.join('\n').trim();
    }
    return node;
  }
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

/// The suggestions in a ` ```replies ` block: a JSON array of strings, or
/// one per line with any list markers and quotes dropped. At most four.
List<String> parseReplies(String source) {
  Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    decoded = null;
  }
  final values = decoded is List
      ? [
          for (final item in decoded)
            if (item is Map)
              '${item['text'] ?? item['label'] ?? ''}'
            else
              '$item',
        ]
      : source
            .split('\n')
            .map(
              (line) =>
                  line.replaceFirst(RegExp(r'^\s*(?:[-*+•]|\d+[.)])\s+'), ''),
            );
  return {
    for (final value in values)
      if (value.trim().replaceAll(RegExp('^["“「]|["”」]\$'), '').trim()
          case final text when text.isNotEmpty)
        text.length > 120 ? '${text.substring(0, 119)}…' : text,
  }.take(4).toList();
}
