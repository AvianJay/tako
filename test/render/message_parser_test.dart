import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:tako/ui/render/message_parser.dart';

String textOf(ParsedMessage parsed) =>
    parsed.nodes.map((e) => e.textContent).join('\n');
Iterable<RenderMath> mathOf(ParsedMessage parsed) =>
    parsed.fragments.values.whereType<RenderMath>();

Iterable<md.Element> elements(Iterable<md.Node> nodes) sync* {
  for (final node in nodes) {
    if (node is md.Element) {
      yield node;
      yield* elements(node.children ?? const []);
    }
  }
}

void main() {
  test('all math delimiters and escaped dollars', () {
    final parsed = parseMessageMarkup(r'\$5 and $x+1$; $$x^2$$; \(y\); \[z\]');
    expect(mathOf(parsed).map((e) => e.tex), ['x+1', 'x^2', 'y', 'z']);
    expect(mathOf(parsed).map((e) => e.display), [false, true, false, true]);
    expect(textOf(parsed), contains(r'$5 and'));
  });

  test(
    'inline dollars require adjoining nonspace and no digit after close',
    () {
      for (final source in [r'$ x$', r'$x $', r'$x$2', r'cost $5 and $10']) {
        final parsed = parseMessageMarkup(source);
        expect(mathOf(parsed), isEmpty, reason: source);
        expect(textOf(parsed), source);
      }
      expect(mathOf(parseMessageMarkup(r'$x$ then 2')).single.tex, 'x');
    },
  );

  test('escaped delimiters do not end math', () {
    expect(mathOf(parseMessageMarkup(r'$x+\$y$')).single.tex, r'x+\$y');
    expect(mathOf(parseMessageMarkup(r'\\$x$')).single.tex, 'x');
  });

  test('every incomplete math suffix is withheld until closed', () {
    for (final source in [r'$x', r'$$x', r'\(x', r'\[x']) {
      final parsed = parseMessageMarkup('Before $source', isStreaming: true);
      expect(textOf(parsed), 'Before');
      expect(parsed.buffered, source);
      expect(mathOf(parsed), isEmpty);
    }
    final parsed = parseMessageMarkup(r'Before $x$ after', isStreaming: true);
    expect(parsed.buffered, isEmpty);
    expect(mathOf(parsed).single.tex, 'x');
  });

  test('unmatched finished math stays literal', () {
    for (final source in [r'$x', r'$$x', r'\(x', r'\[x']) {
      final parsed = parseMessageMarkup(source);
      expect(textOf(parsed), source);
      expect(parsed.buffered, isEmpty);
    }
  });

  test('fences with shorter apparent close stay buffered', () {
    const source = 'Before\n\n````dart\nfinal value = 1;\n```\n';
    final pending = parseMessageMarkup(source, isStreaming: true);
    expect(textOf(pending), 'Before');
    expect(pending.buffered, startsWith('````dart'));
    final completed = parseMessageMarkup('$source````', isStreaming: true);
    expect(completed.buffered, isEmpty);
    expect(
      elements(completed.nodes).where((e) => e.tag == 'pre'),
      hasLength(1),
    );
    expect(textOf(completed), contains('final value = 1;\n```'));
  });

  test('code contents cannot turn into math or custom tags', () {
    final parsed = parseMessageMarkup(
      '```html\n\$x\$ <image src="x"/>\n```\n\n`\$y\$ <file path="x"/>`',
    );
    expect(parsed.fragments, isEmpty);
    expect(textOf(parsed), contains(r'$x$ <image src="x"/>'));
    expect(textOf(parsed), contains(r'$y$ <file path="x"/>'));
  });

  test('fences nested in quotes and lists are also streaming-safe', () {
    for (final source in [
      '> ~~~text\n> \$x\$ <image src="x"/>\n',
      '- ~~~text\n  \$x\$ <image src="x"/>\n',
      '1. ```text\n   \$x\$ <image src="x"/>\n',
    ]) {
      final parsed = parseMessageMarkup(source, isStreaming: true);
      expect(parsed.buffered, source);
      expect(parsed.fragments, isEmpty);
      expect(parsed.nodes, isEmpty);
    }
    final parsed = parseMessageMarkup(
      '> ~~~text\n> \$x\$ <image src="x"/>\n> ~~~',
      isStreaming: true,
    );
    expect(parsed.fragments, isEmpty);
    expect(parsed.buffered, isEmpty);
    expect(elements(parsed.nodes).where((e) => e.tag == 'pre'), hasLength(1));
  });

  test(
    'partial tags are buffered and quote-contained > does not close them',
    () {
      const source = '<image src="https://example.com/a?value=>" alt="A"/>';
      for (var i = 1; i < source.length; i++) {
        final pending = parseMessageMarkup(
          'Before ${source.substring(0, i)}',
          isStreaming: true,
        );
        expect(pending.fragments.values.whereType<RenderTag>(), isEmpty);
        expect(pending.buffered, source.substring(0, i));
      }
      final parsed = parseMessageMarkup(source, isStreaming: true);
      final tag = parsed.fragments.values.whereType<RenderTag>().single;
      expect(tag.name, 'image');
      expect(tag.attributes['src'], 'https://example.com/a?value=>');
      expect(tag.attributes['alt'], 'A');
    },
  );

  test(
    'unknown and malformed tags remain literal and registry is extensible',
    () {
      for (final source in [
        '<script>alert(1)</script>',
        '<image src=x/>',
        '<file path="a" hidden/>',
      ]) {
        expect(textOf(parseMessageMarkup(source)), source);
      }
      final parsed = parseMessageMarkup(
        '<badge value="ok"/>',
        customTags: {'badge'},
      );
      expect(
        parsed.fragments.values.whereType<RenderTag>().single.name,
        'badge',
      );
    },
  );

  test('HTML-style custom tags are tolerated and their closers dropped', () {
    for (final source in [
      '<image src="a.png">',
      '<image src="a.png"></image>',
      '<image src="a.png" / >',
      "<Image SRC='a.png'/>",
    ]) {
      final parsed = parseMessageMarkup('Look $source here');
      final tag = parsed.fragments.values.whereType<RenderTag>().single;
      expect(tag.name, 'image', reason: source);
      expect(tag.attributes, {'src': 'a.png'}, reason: source);
      expect(textOf(parsed), isNot(contains('</')), reason: source);
    }
    expect(
      textOf(parseMessageMarkup('<b>bold</b> </span>')),
      '<b>bold</b> </span>',
    );
  });

  test(
    'GFM tables, nested lists, strikethrough and autolinks keep their AST',
    () {
      final parsed = parseMessageMarkup(
        '| A | B |\n|---|---|\n| 1 | 2 |\n\n- one\n  - two\n\n~~old~~ <https://example.com>',
      );
      final tags = elements(parsed.nodes).map((e) => e.tag);
      expect(
        tags,
        containsAll([
          'table',
          'thead',
          'tbody',
          'tr',
          'th',
          'td',
          'ul',
          'li',
          'del',
          'a',
        ]),
      );
    },
  );

  test('partial fence itself is withheld and final text recovered', () {
    for (final source in ['`', '``', '~', '~~']) {
      expect(parseMessageMarkup(source, isStreaming: true).buffered, source);
      expect(textOf(parseMessageMarkup(source)), source);
    }
  });

  test('literal marker-like user content cannot impersonate a fragment', () {
    const source = '\uE000tako0\uE001';
    expect(textOf(parseMessageMarkup('$source \$x\$')), contains(source));
  });

  group('callouts', () {
    md.Element callout(String source) => elements(
      parseMessageMarkup(source).nodes,
    ).firstWhere((e) => e.tag == 'tako-callout');

    test('types, aliases and an optional title', () {
      expect(callout('> [!NOTE]\n> Body').attributes['type'], 'note');
      expect(callout('> [!info]\n> Body').attributes['type'], 'note');
      expect(callout('> [!DANGER]\n> Body').attributes['type'], 'caution');
      final titled = callout('> [!TIP] Try *this*\n> Body');
      expect(titled.attributes['type'], 'tip');
      final title = titled.children!.first as md.Element;
      expect(title.tag, 'tako-callout-title');
      expect(title.textContent, 'Try this');
      expect(titled.children!.last.textContent, 'Body');
      // Unknown types stay ordinary quotes.
      expect(
        elements(
          parseMessageMarkup('> [!FOO]\n> Body').nodes,
        ).map((e) => e.tag),
        contains('blockquote'),
      );
    });

    test('nested blocks keep their indentation, and the quote ends', () {
      final node = callout(
        '> [!WARNING]\n> - one\n>   - two\n>\n> ```dart\n>   indented();\n> ```\n'
        '# After',
      );
      final inner = elements(node.children!).map((e) => e.tag).toList();
      expect(inner, containsAll(['ul', 'li', 'pre']));
      expect(
        elements(node.children!).where((e) => e.tag == 'ul'),
        hasLength(2),
      );
      expect(node.textContent, contains('  indented();'));
      final parsed = parseMessageMarkup('> [!WARNING]\n> Careful\n# After');
      expect(parsed.nodes.last, isA<md.Element>());
      expect((parsed.nodes.last as md.Element).tag, 'h1');
    });

    test('an escaped marker is a callout, not math', () {
      final parsed = parseMessageMarkup(
        r'> \[!NOTE\]'
        '\n> Body',
      );
      expect(mathOf(parsed), isEmpty);
      expect(
        elements(parsed.nodes).map((e) => e.tag),
        contains('tako-callout'),
      );
    });

    test('a half-arrived marker is held back while streaming', () {
      for (final partial in ['> [', '> [!', '> [!NO', r'> \[!NO']) {
        final parsed = parseMessageMarkup(
          'Before\n\n$partial',
          isStreaming: true,
        );
        expect(parsed.buffered, partial, reason: partial);
      }
      // A link in a quote is released as soon as it is not a marker.
      expect(
        parseMessageMarkup('> [link', isStreaming: true).buffered,
        isEmpty,
      );
    });
  });
}
