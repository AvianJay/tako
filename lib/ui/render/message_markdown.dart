import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

import '../../core/web/web_links.dart';
import 'code_block.dart';
import 'message_parser.dart';
import 'revealing_text.dart';
import 'text_colors.dart';
import 'visuals/cards.dart';
import 'visuals/visual_block.dart';
import 'visuals/visual_image.dart';
import 'visuals/visual_labels.dart';
import 'visuals/visual_palette.dart';
import 'web_embeds.dart';

export 'message_parser.dart' show RenderTag;
export 'visuals/visual_image.dart' show VisualImage;
export 'visuals/visual_labels.dart' show VisualLabels;
export 'web_embeds.dart' show WebEmbeds;

typedef CustomTagBuilder = Widget Function(BuildContext context, RenderTag tag);

/// Returns a widget for an image the host can show locally, or null to keep
/// the default chip.
typedef InlineImageBuilder =
    Widget? Function(BuildContext context, String source, String alt);

/// Local-only rendering. The host supplies every platform action explicitly.
/// In particular, nothing is fetched from the web unless the host passes
/// [web], and then only as [WebEmbeds] allows. Charts, diagrams and cards
/// are drawn from their source alone.
class MessageMarkdown extends StatefulWidget {
  const MessageMarkdown({
    required this.data,
    required this.copyLabel,
    required this.imageLabel,
    required this.fileLabel,
    this.visualLabels = const VisualLabels(),
    this.isStreaming = false,
    this.visuals = true,
    this.onCopy,
    this.onLink,
    this.onFile,
    this.onImage,
    this.onShareImage,
    this.onReply,
    this.imageBuilder,
    this.web,
    this.tagBuilders = const {},
    super.key,
  });

  final String data;
  final bool isStreaming;

  /// Draws ` ```chart `, ` ```mermaid ` and ` ```cards ` blocks. When false
  /// they stay code, as in the user's own messages.
  final bool visuals;
  final String copyLabel;
  final String imageLabel;
  final String fileLabel;
  final VisualLabels visualLabels;
  final ValueChanged<String>? onCopy;
  final ValueChanged<Uri>? onLink;
  final ValueChanged<String>? onFile;
  final ValueChanged<String>? onImage;

  /// Offered on charts and diagrams; hidden when null.
  final ValueChanged<VisualImage>? onShareImage;

  /// Sends a suggested reply from a ` ```replies ` block. The suggestions
  /// are hidden when null, as they are once the conversation moved on.
  final ValueChanged<String>? onReply;

  /// Like the callbacks, read whenever the content is rendered again.
  final InlineImageBuilder? imageBuilder;

  /// Previews of links, images, videos and places. Without it they stay
  /// links and chips.
  final WebEmbeds? web;
  final Map<String, CustomTagBuilder> tagBuilders;

  @override
  State<MessageMarkdown> createState() => _MessageMarkdownState();
}

class _MessageMarkdownState extends State<MessageMarkdown> {
  final _recognizers = <TapGestureRecognizer>[];
  late ParsedMessage _parsed;
  Widget? _rendered;

  /// Footnotes by the `href` their references use: number and Markdown.
  final _footnotes = <String, (int, String)>{};

  /// Spoilers are numbered in reading order on every render.
  final _revealed = <int>{};
  var _spoilers = 0;
  var _details = 0;

  /// Inside the footnote list, links stay links instead of previews.
  var _inFootnotes = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rendered = null;
  }

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(covariant MessageMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        oldWidget.isStreaming != widget.isStreaming ||
        oldWidget.tagBuilders != widget.tagBuilders) {
      _parse();
    }
    if (oldWidget.copyLabel != widget.copyLabel ||
        oldWidget.imageLabel != widget.imageLabel ||
        oldWidget.fileLabel != widget.fileLabel ||
        oldWidget.visualLabels != widget.visualLabels ||
        oldWidget.visuals != widget.visuals ||
        (oldWidget.onCopy == null) != (widget.onCopy == null) ||
        (oldWidget.onImage == null) != (widget.onImage == null) ||
        (oldWidget.onShareImage == null) != (widget.onShareImage == null) ||
        (oldWidget.imageBuilder == null) != (widget.imageBuilder == null) ||
        (oldWidget.onFile == null) != (widget.onFile == null) ||
        (oldWidget.onLink == null) != (widget.onLink == null) ||
        (oldWidget.onReply == null) != (widget.onReply == null) ||
        (oldWidget.web == null) != (widget.web == null) ||
        oldWidget.web?.autoLoad != widget.web?.autoLoad) {
      _rendered = null;
    }
  }

  void _parse() {
    _rendered = null;
    _parsed = parseMessageMarkup(
      widget.data,
      isStreaming: widget.isStreaming,
      customTags: {'image', 'file', ...widget.tagBuilders.keys},
    );
    _footnotes.clear();
    for (final section in _parsed.nodes) {
      if (section is! md.Element || section.tag != 'section') continue;
      for (final list in section.children ?? const <md.Node>[]) {
        if (list is! md.Element || list.tag != 'ol') continue;
        for (final (index, item)
            in (list.children ?? const <md.Node>[]).indexed) {
          if (item is md.Element && item.attributes['id'] != null) {
            _footnotes['#${item.attributes['id']}'] = (
              index + 1,
              _parsed.restoreLiteralTokens(
                item.attributes['source'] ?? item.textContent,
              ),
            );
          }
        }
      }
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_rendered case final rendered?) return rendered;
    _disposeRecognizers();
    _spoilers = 0;
    _details = 0;
    final pending = widget.visuals && widget.isStreaming
        ? pendingVisualLanguage(_parsed.buffered)
        : null;
    return _rendered = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ..._parsed.nodes.map(_block),
        if (pending != null)
          VisualPlaceholder(label: widget.visualLabels.drawing),
      ],
    );
  }

  Widget _block(md.Node node) {
    if (node is! md.Element) return _paragraph([node]);
    final children = node.children ?? const <md.Node>[];
    switch (node.tag) {
      case 'p':
        return _embed(children) ?? _paragraph(children);
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final level = int.parse(node.tag.substring(1));
        return _paragraph(
          children,
          style: TextStyle(
            fontSize: 26 - level * 2,
            fontWeight: FontWeight.bold,
          ),
        );
      case 'pre':
        final code = children.isNotEmpty ? children.first : node;
        final language = code is md.Element
            ? (code.attributes['class'] ?? '')
                  .replaceFirst('language-', '')
                  .toLowerCase()
            : '';
        final source = _parsed.restoreLiteralTokens(code.textContent);
        final onCopy = widget.onCopy == null
            ? null
            : (String text) => widget.onCopy?.call(text);
        if (widget.visuals && visualLanguages.contains(language)) {
          return VisualBlock(
            language: language,
            source: source,
            labels: widget.visualLabels,
            copyLabel: widget.copyLabel,
            streaming: widget.isStreaming,
            onCopy: onCopy,
            onShareImage: widget.onShareImage == null
                ? null
                : (image) => widget.onShareImage?.call(image),
          );
        }
        if (widget.visuals && language == 'cards') {
          if (_cards(source) case final cards?) return cards;
        }
        if (widget.visuals &&
            const {'replies', 'suggestions'}.contains(language)) {
          return _replies(source);
        }
        return CodeBlock(
          code: source,
          language: language,
          copyLabel: widget.copyLabel,
          onCopy: onCopy,
          note: widget.visuals && language == 'cards'
              ? widget.visualLabels.failed
              : null,
        );
      case 'ul':
      case 'ol':
        final start = int.tryParse(node.attributes['start'] ?? '') ?? 1;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < children.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 30,
                        child: Text(node.tag == 'ol' ? '${start + i}.' : '•'),
                      ),
                      Expanded(child: _block(children[i])),
                    ],
                  ),
                ),
            ],
          ),
        );
      case 'li':
        return _flow(children);
      case 'blockquote':
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 3,
              ),
            ),
          ),
          child: _flow(children),
        );
      case 'tako-callout':
        return _callout(node);
      case 'details':
        return _detailsBlock(node);
      case 'section' when node.attributes['class'] == 'footnotes':
        return _footnoteList(node);
      case 'hr':
        return const Divider();
      case 'table':
        return _table(node);
      default:
        return _paragraph([node]);
    }
  }

  Widget _flow(List<md.Node> nodes) {
    final blocks = <Widget>[];
    var inline = <md.Node>[];
    void flush() {
      if (inline.isNotEmpty) blocks.add(_paragraph(inline));
      inline = [];
    }

    for (final node in nodes) {
      if (node is md.Element &&
          const {
            'p',
            'h1',
            'h2',
            'h3',
            'h4',
            'h5',
            'h6',
            'ul',
            'ol',
            'pre',
            'blockquote',
            'tako-callout',
            'details',
            'section',
            'hr',
            'table',
          }.contains(node.tag)) {
        flush();
        blocks.add(_block(node));
      } else {
        inline.add(node);
      }
    }
    flush();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: blocks,
    );
  }

  Widget _callout(md.Element node) {
    final kind =
        CalloutKind.values.asNameMap()[node.attributes['type']] ??
        CalloutKind.note;
    final color = VisualPalette.of(context).callouts[kind]!;
    final labels = widget.visualLabels;
    final (icon, title) = switch (kind) {
      CalloutKind.note => (Icons.info_outline, labels.note),
      CalloutKind.tip => (Icons.lightbulb_outline, labels.tip),
      CalloutKind.important => (Icons.feedback_outlined, labels.important),
      CalloutKind.warning => (Icons.warning_amber_rounded, labels.warning),
      CalloutKind.caution => (Icons.report_outlined, labels.caution),
    };
    var children = node.children ?? const <md.Node>[];
    md.Element? custom;
    if (children.firstOrNull case final md.Element first
        when first.tag == 'tako-callout-title') {
      custom = first;
      children = children.sublist(1);
    }
    final style = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w600);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.fromLTRB(12, 8, 8, children.isEmpty ? 8 : 0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .06),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: custom == null
                    ? Text(title, style: style)
                    : Text.rich(
                        TextSpan(
                          children: (custom.children ?? const <md.Node>[])
                              .map(_inline)
                              .toList(),
                        ),
                        style: style,
                      ),
              ),
            ],
          ),
          if (children.isNotEmpty) ...[
            const SizedBox(height: 4),
            _flow(children),
          ],
        ],
      ),
    );
  }

  /// Cards, or null when [source] is not a cards specification.
  Widget? _cards(String source) {
    final CardsSpec spec;
    try {
      spec = CardsSpec.parse(source);
    } on Object {
      return null;
    }
    InlineSpan? span(String? text) => text == null ? null : _inlineText(text);
    return CardsView(
      layout: spec.layout,
      items: [
        for (final item in spec.items)
          CardContent(
            icon: item.icon,
            title: span(item.title),
            subtitle: span(item.subtitle),
            text: span(item.text),
            value: item.value,
            delta: item.delta,
          ),
      ],
    );
  }

  /// Inline Markdown for a card field. Tags stay text, so a generated image
  /// is never shown inside a card as well as after the reply.
  InlineSpan _inlineText(String text) {
    final parsed = parseMessageMarkup(text, customTags: const {});
    final spans = <InlineSpan>[];
    void inlineAll(Iterable<md.Node> nodes) {
      for (final node in nodes) {
        if (node is md.Element && node.tag == 'p') {
          inlineAll(node.children ?? const []);
        } else {
          spans.add(_inline(node, parsed: parsed));
        }
      }
    }

    for (final (index, node) in parsed.nodes.indexed) {
      if (index > 0) spans.add(const TextSpan(text: '\n'));
      if (node is md.Element && (node.tag == 'ul' || node.tag == 'ol')) {
        for (final (i, item) in (node.children ?? const <md.Node>[]).indexed) {
          if (i > 0) spans.add(const TextSpan(text: '\n'));
          spans.add(TextSpan(text: node.tag == 'ol' ? '${i + 1}. ' : '• '));
          inlineAll(item is md.Element ? item.children ?? const [] : [item]);
        }
      } else if (node is md.Element &&
          (node.tag == 'p' || RegExp(r'^h[1-6]$').hasMatch(node.tag))) {
        inlineAll(node.children ?? const []);
      } else {
        spans.add(_inline(node, parsed: parsed));
      }
    }
    return TextSpan(children: spans);
  }

  Widget _paragraph(List<md.Node> nodes, {TextStyle? style}) {
    final spans = <InlineSpan>[];
    final blocks = <Widget>[];
    void flush() {
      if (spans.isEmpty) return;
      blocks.add(
        RevealingText(
          span: TextSpan(children: List.of(spans)),
          streaming: widget.isStreaming,
          style: style,
        ),
      );
      spans.clear();
    }

    for (final node in nodes) {
      final fragment = _fragment(node, _parsed);
      if (fragment is RenderMath && fragment.display) {
        flush();
        blocks.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _math(fragment),
            ),
          ),
        );
      } else {
        spans.add(_inline(node));
      }
    }
    flush();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: blocks,
      ),
    );
  }

  MarkupFragment? _fragment(md.Node node, ParsedMessage parsed) =>
      node is md.Element && node.tag == 'tako-fragment'
      ? parsed.fragments[node.attributes['marker']]
      : null;

  InlineSpan _inline(
    md.Node node, {
    TapGestureRecognizer? linkRecognizer,
    ParsedMessage? parsed,
  }) {
    final source = parsed ?? _parsed;
    if (node is md.Text) {
      return TextSpan(
        text: source.restoreLiteralTokens(node.text),
        recognizer: linkRecognizer,
      );
    }
    if (node is! md.Element) return TextSpan(text: node.textContent);
    final fragment = _fragment(node, source);
    if (fragment != null) {
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: switch (fragment) {
          RenderMath() => FittedBox(
            fit: BoxFit.scaleDown,
            child: _math(fragment),
          ),
          RenderTag() => _tag(fragment),
          RenderLiteral() || RenderFormat() => Text(fragment.source),
        },
      );
    }
    final children = node.children ?? const <md.Node>[];
    List<InlineSpan> renderChildren() => children
        .map(
          (child) =>
              _inline(child, linkRecognizer: linkRecognizer, parsed: source),
        )
        .toList();
    final scheme = Theme.of(context).colorScheme;
    switch (node.tag) {
      case 'br':
        return const TextSpan(text: '\n');
      case 'code':
        return TextSpan(
          text: source.restoreLiteralTokens(node.textContent),
          recognizer: linkRecognizer,
          style: TextStyle(
            fontFamily: 'monospace',
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        );
      case 'img':
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _image(
            node.attributes['src'] ?? '',
            node.attributes['alt'] ?? '',
          ),
        );
      case 'a' when node.attributes['class'] == 'footnote-backref':
        // The ↩ links of a web page; the list here has nothing to go back to.
        return const TextSpan();
      case 'a':
        final target = Uri.tryParse(node.attributes['href'] ?? '');
        final supported =
            target != null &&
            const {
              'http',
              'https',
              'mailto',
              'tel',
              'sms',
              'geo',
            }.contains(target.scheme);
        TapGestureRecognizer? recognizer;
        if (supported && widget.onLink != null) {
          recognizer = TapGestureRecognizer()
            ..onTap = () => widget.onLink?.call(target);
          _recognizers.add(recognizer);
        }
        return TextSpan(
          children: children
              .map(
                (child) =>
                    _inline(child, linkRecognizer: recognizer, parsed: source),
              )
              .toList(),
          style: TextStyle(
            color: scheme.primary,
            decoration: TextDecoration.underline,
          ),
          recognizer: recognizer,
        );
      case 'strong':
        return TextSpan(
          children: renderChildren(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        );
      case 'em':
        return TextSpan(
          children: renderChildren(),
          style: const TextStyle(fontStyle: FontStyle.italic),
        );
      case 'del':
        return TextSpan(
          children: renderChildren(),
          style: const TextStyle(decoration: TextDecoration.lineThrough),
        );
      case 'u':
        return TextSpan(
          children: renderChildren(),
          style: const TextStyle(decoration: TextDecoration.underline),
        );
      case 'mark':
      case 'span':
        return TextSpan(
          children: renderChildren(),
          style: _colors(node.attributes, highlight: node.tag == 'mark'),
        );
      case 'small':
        return TextSpan(
          children: renderChildren(),
          style: TextStyle(fontSize: _fontSize * .85),
        );
      case 'kbd':
        return TextSpan(
          children: renderChildren(),
          style: TextStyle(
            fontFamily: 'monospace',
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        );
      case 'sup' when node.attributes['class'] == 'footnote-ref':
        return _footnoteReference(node);
      case 'ruby':
        return _ruby(children, source);
      case 'rp':
        // Parentheses for readers that cannot show annotations.
        return const TextSpan();
      case 'badge':
        return _badge(node, renderChildren());
      case 'spoiler':
        return _spoiler(node, renderChildren, source);
      case 'tako-summary' || 'summary':
        return TextSpan(
          children: renderChildren(),
          style: const TextStyle(fontWeight: FontWeight.w600),
        );
      case 'sub':
      case 'sup':
        // Text styles cannot shift the baseline, so the smaller text is
        // aligned on it and then painted up or down.
        return WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Transform.translate(
            offset: Offset(0, _fontSize * (node.tag == 'sup' ? -.35 : .2)),
            child: Text.rich(
              TextSpan(children: renderChildren()),
              style: TextStyle(fontSize: _fontSize * .75),
              // The span already scales with the text around it.
              textScaler: TextScaler.noScaling,
            ),
          ),
        );
      case 'input':
        return WidgetSpan(
          child: Icon(
            node.attributes.containsKey('checked')
                ? Icons.check_box_outlined
                : Icons.check_box_outline_blank,
            size: 18,
          ),
        );
      default:
        return TextSpan(children: renderChildren());
    }
  }

  double get _fontSize => DefaultTextStyle.of(context).style.fontSize ?? 14;

  /// The text and highlighter colours a `span` or `mark` asks for, moved as
  /// far as needed to stay readable in the current theme.
  TextStyle _colors(Map<String, String> attributes, {required bool highlight}) {
    final theme = Theme.of(context);
    final surface = theme.scaffoldBackgroundColor;
    final ink =
        DefaultTextStyle.of(context).style.color ?? theme.colorScheme.onSurface;
    final background =
        parseTextColor(attributes['background'] ?? '') ??
        (highlight ? textColors['yellow'] : null);
    final fill = background == null
        ? null
        : highlightColor(background, surface, ink);
    final color = parseTextColor(attributes['color'] ?? '');
    return TextStyle(
      color: color == null ? null : readableTextColor(color, fill ?? surface),
      backgroundColor: fill,
    );
  }

  /// Ruby text above its base, for pinyin, zhuyin or furigana. Each run of
  /// base text takes the annotation that follows it.
  InlineSpan _ruby(List<md.Node> nodes, ParsedMessage source) {
    List<InlineSpan> spans(List<md.Node> nodes) =>
        nodes.map((node) => _inline(node, parsed: source)).toList();
    final result = <InlineSpan>[];
    var base = <md.Node>[];
    for (final node in nodes) {
      if (node is md.Element && node.tag == 'rt') {
        result.add(
          WidgetSpan(
            // Bottoms align, and with them the baselines of the base text.
            alignment: PlaceholderAlignment.bottom,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(
                  TextSpan(children: spans(node.children ?? const [])),
                  style: TextStyle(fontSize: _fontSize * .6, height: 1.2),
                  textScaler: TextScaler.noScaling,
                  softWrap: false,
                ),
                Text.rich(
                  TextSpan(children: spans(base)),
                  textScaler: TextScaler.noScaling,
                  softWrap: false,
                ),
              ],
            ),
          ),
        );
        base = [];
      } else if (node is! md.Element || node.tag != 'rp') {
        base.add(node);
      }
    }
    return TextSpan(children: [...result, ...spans(base)]);
  }

  /// A short label in a tinted pill, such as a status.
  InlineSpan _badge(md.Element node, List<InlineSpan> children) {
    final theme = Theme.of(context);
    final hue =
        parseTextColor(node.attributes['color'] ?? '') ?? textColors['gray']!;
    final fill = Color.alphaBlend(
      hue.withValues(alpha: theme.brightness == Brightness.dark ? .3 : .16),
      theme.scaffoldBackgroundColor,
    );
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text.rich(
          TextSpan(children: children),
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: _fontSize * .8,
            fontWeight: FontWeight.w600,
            color: readableTextColor(hue, fill),
          ),
        ),
      ),
    );
  }

  /// Text hidden behind a bar until it is tapped.
  InlineSpan _spoiler(
    md.Element node,
    List<InlineSpan> Function() children,
    ParsedMessage source,
  ) {
    final index = _spoilers++;
    final scheme = Theme.of(context).colorScheme;
    if (_revealed.contains(index)) {
      return TextSpan(
        children: children(),
        style: TextStyle(backgroundColor: scheme.surfaceContainerHighest),
      );
    }
    final recognizer = TapGestureRecognizer()
      ..onTap = () => setState(() {
        _revealed.add(index);
        _rendered = null;
      });
    _recognizers.add(recognizer);
    // Plain text, so no colour or link inside shows through the bar.
    return TextSpan(
      text: source.restoreLiteralTokens(node.textContent),
      recognizer: recognizer,
      semanticsLabel: widget.visualLabels.spoiler,
      style: TextStyle(color: scheme.outline, backgroundColor: scheme.outline),
    );
  }

  InlineSpan _footnoteReference(md.Element node) {
    final link = (node.children ?? const <md.Node>[])
        .whereType<md.Element>()
        .firstOrNull;
    final note = _footnotes[link?.attributes['href']];
    final number = link?.textContent ?? '';
    final scheme = Theme.of(context).colorScheme;
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Transform.translate(
        offset: Offset(0, -_fontSize * .35),
        child: Semantics(
          button: note != null,
          label: '${widget.visualLabels.footnote} $number',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: note == null ? null : () => _showFootnote(note.$1, note.$2),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                number,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: _fontSize * .7,
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One footnote in a sheet, drawn like a short reply of its own.
  void _showFootnote(int number, String markdown) {
    final parent = widget;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${parent.visualLabels.footnote} $number',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              MessageMarkdown(
                data: markdown,
                copyLabel: parent.copyLabel,
                imageLabel: parent.imageLabel,
                fileLabel: parent.fileLabel,
                visualLabels: parent.visualLabels,
                visuals: parent.visuals,
                onCopy: parent.onCopy,
                onLink: parent.onLink,
                onFile: parent.onFile,
                onImage: parent.onImage,
                imageBuilder: parent.imageBuilder,
                web: parent.web,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Footnotes as a numbered list after the reply.
  Widget _footnoteList(md.Element section) {
    final items = [
      for (final list in section.children ?? const <md.Node>[])
        if (list is md.Element && list.tag == 'ol')
          ...(list.children ?? const <md.Node>[]).whereType<md.Element>(),
    ];
    final outer = _inFootnotes;
    _inFootnotes = true;
    try {
      return DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: _fontSize * .875,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(height: 16),
            for (final (index, item) in items.indexed)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 24, child: Text('${index + 1}.')),
                  Expanded(child: _flow(item.children ?? const [])),
                ],
              ),
          ],
        ),
      );
    } finally {
      _inFootnotes = outer;
    }
  }

  Widget _detailsBlock(md.Element node) {
    var children = node.children ?? const <md.Node>[];
    md.Element? summary;
    if (children.firstOrNull case final md.Element first
        when first.tag == 'tako-summary') {
      summary = first;
      children = children.sublist(1);
    }
    return _Details(
      key: ValueKey('details-${_details++}'),
      open: node.attributes.containsKey('open'),
      summary: Text.rich(
        TextSpan(
          children: summary == null
              ? [TextSpan(text: widget.visualLabels.details)]
              : (summary.children ?? const <md.Node>[]).map(_inline).toList(),
        ),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      content: _flow(children),
    );
  }

  /// Suggested replies the user can send with a tap.
  Widget _replies(String source) {
    final options = parseReplies(source);
    if (widget.onReply == null || options.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in options)
            ActionChip(
              avatar: const Icon(Icons.reply_outlined, size: 18),
              label: Text(option),
              onPressed: () => widget.onReply?.call(option),
            ),
        ],
      ),
    );
  }

  /// A preview for a paragraph that holds nothing but a link, as chat apps
  /// show one; null for any other paragraph.
  Widget? _embed(List<md.Node> nodes) {
    final web = widget.web;
    if (web == null || !widget.visuals || _inFootnotes) return null;
    final content = [
      for (final node in nodes)
        if (node is! md.Text || node.text.trim().isNotEmpty) node,
    ];
    if (content case [md.Element(tag: 'a') && final link]) {
      final href = link.attributes['href'] ?? '';
      final uri = Uri.tryParse(href);
      if (uri == null) return null;
      final text = _parsed.restoreLiteralTokens(link.textContent).trim();
      final label = text == href ? '' : text;
      final open = widget.onLink == null
          ? null
          : () => widget.onLink?.call(uri);
      if (mapPoint(uri) case final point?) {
        return MapCard(
          key: ValueKey(href),
          point: point,
          label: label,
          web: web,
          labels: widget.visualLabels,
          onOpen: open,
          onAttribution: widget.onLink == null
              ? null
              : () => widget.onLink?.call(
                  Uri.parse('https://www.openstreetmap.org/copyright'),
                ),
        );
      }
      if (!{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
        return null;
      }
      if (isImageUrl(uri)) {
        return RemoteImage(
          key: ValueKey(href),
          uri: uri,
          alt: label,
          web: web,
          labels: widget.visualLabels,
          onOpen: open,
        );
      }
      return LinkPreviewCard(
        key: ValueKey(href),
        uri: uri,
        label: label.isEmpty ? href : label,
        web: web,
        labels: widget.visualLabels,
        onOpen: open,
      );
    }
    return null;
  }

  Widget _math(RenderMath fragment) => Math.tex(
    fragment.tex,
    mathStyle: fragment.display ? MathStyle.display : MathStyle.text,
    textStyle: DefaultTextStyle.of(context).style,
    onErrorFallback: (_) => Text(fragment.source),
  );

  Widget _tag(RenderTag tag) {
    final customBuilder = widget.tagBuilders[tag.name];
    if (customBuilder != null) return customBuilder(context, tag);
    switch (tag.name) {
      case 'image':
        final src = tag.attributes['src'] ?? tag.attributes['path'];
        return src == null
            ? Text(tag.source)
            : _image(src, tag.attributes['alt'] ?? '');
      case 'file':
        final path = tag.attributes['path'] ?? tag.attributes['src'];
        if (path == null) return Text(tag.source);
        return widget.imageBuilder?.call(context, path, '') ??
            _attachment(
              path,
              '${widget.fileLabel} · ${path.replaceAll(r'\', '/').split('/').last}',
              Icons.insert_drive_file_outlined,
              widget.onFile == null
                  ? null
                  : (path) => widget.onFile?.call(path),
            );
      default:
        return Text(tag.source);
    }
  }

  Widget _image(String source, String alt) {
    if (widget.imageBuilder?.call(context, source, alt) case final image?) {
      return image;
    }
    final uri = Uri.tryParse(source);
    if (widget.web case final web?
        when widget.visuals &&
            uri != null &&
            {'http', 'https'}.contains(uri.scheme) &&
            uri.host.isNotEmpty) {
      return RemoteImage(
        key: ValueKey(source),
        uri: uri,
        alt: alt,
        web: web,
        labels: widget.visualLabels,
        onOpen: widget.onImage == null
            ? null
            : () => widget.onImage?.call(source),
      );
    }
    return _attachment(
      source,
      alt.isEmpty ? widget.imageLabel : alt,
      Icons.image_outlined,
      widget.onImage == null ? null : (path) => widget.onImage?.call(path),
    );
  }

  Widget _attachment(
    String source,
    String label,
    IconData icon,
    ValueChanged<String>? onTap,
  ) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 280),
    child: Tooltip(
      message: source,
      child: ActionChip(
        avatar: Icon(icon, size: 18),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        onPressed: onTap == null ? null : () => onTap(source),
      ),
    ),
  );

  Widget _table(md.Element table) {
    final rows = <md.Element>[];
    void collect(md.Node node) {
      if (node is! md.Element) return;
      if (node.tag == 'tr') {
        rows.add(node);
      } else {
        for (final child in node.children ?? <md.Node>[]) {
          collect(child);
        }
      }
    }

    collect(table);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          children: [
            for (final row in rows)
              TableRow(
                children: [
                  for (final cell in row.children ?? <md.Node>[])
                    Container(
                      constraints: const BoxConstraints(
                        minWidth: 64,
                        maxWidth: 280,
                      ),
                      padding: const EdgeInsets.all(8),
                      alignment: switch (_align(cell)) {
                        TextAlign.center => Alignment.topCenter,
                        TextAlign.right => Alignment.topRight,
                        _ => Alignment.topLeft,
                      },
                      child: Text.rich(
                        TextSpan(
                          children:
                              (cell is md.Element
                                      ? cell.children ?? <md.Node>[]
                                      : [cell])
                                  .map(_inline)
                                  .toList(),
                        ),
                        textAlign: _align(cell),
                        style: cell is md.Element && cell.tag == 'th'
                            ? const TextStyle(fontWeight: FontWeight.bold)
                            : null,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

TextAlign _align(md.Node cell) =>
    switch (cell is md.Element ? cell.attributes['align'] : null) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    };

/// A collapsed section from `<details>`: its summary until tapped open.
class _Details extends StatefulWidget {
  const _Details({
    required this.summary,
    required this.content,
    required this.open,
    super.key,
  });

  final Widget summary;
  final Widget content;
  final bool open;

  @override
  State<_Details> createState() => _DetailsState();
}

class _DetailsState extends State<_Details> {
  late bool _open = widget.open;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: _open ? .25 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.chevron_right,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(child: widget.summary),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    child: widget.content,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
