import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

import 'code_block.dart';
import 'message_parser.dart';
import 'revealing_text.dart';
import 'visuals/cards.dart';
import 'visuals/visual_block.dart';
import 'visuals/visual_image.dart';
import 'visuals/visual_labels.dart';
import 'visuals/visual_palette.dart';

export 'message_parser.dart' show RenderTag;
export 'visuals/visual_image.dart' show VisualImage;
export 'visuals/visual_labels.dart' show VisualLabels;

typedef CustomTagBuilder = Widget Function(BuildContext context, RenderTag tag);

/// Returns a widget for an image the host can show locally, or null to keep
/// the default chip.
typedef InlineImageBuilder =
    Widget? Function(BuildContext context, String source, String alt);

/// Local-only rendering. The host supplies every platform action explicitly.
/// In particular, neither Markdown images nor image tags fetch remote content,
/// and charts, diagrams and cards are drawn from their source alone.
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
    this.imageBuilder,
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

  /// Like the callbacks, read whenever the content is rendered again.
  final InlineImageBuilder? imageBuilder;
  final Map<String, CustomTagBuilder> tagBuilders;

  @override
  State<MessageMarkdown> createState() => _MessageMarkdownState();
}

class _MessageMarkdownState extends State<MessageMarkdown> {
  final _recognizers = <TapGestureRecognizer>[];
  late ParsedMessage _parsed;
  Widget? _rendered;

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
        (oldWidget.onLink == null) != (widget.onLink == null)) {
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
        return _paragraph(children);
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
          RenderLiteral() => Text(fragment.source),
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
      case 'a':
        final target = Uri.tryParse(node.attributes['href'] ?? '');
        final supported =
            target != null &&
            const {'http', 'https', 'mailto'}.contains(target.scheme);
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

  Widget _image(String source, String alt) =>
      widget.imageBuilder?.call(context, source, alt) ??
      _attachment(
        source,
        alt.isEmpty ? widget.imageLabel : alt,
        Icons.image_outlined,
        widget.onImage == null ? null : (path) => widget.onImage?.call(path),
      );

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
                      child: Text.rich(
                        TextSpan(
                          children:
                              (cell is md.Element
                                      ? cell.children ?? <md.Node>[]
                                      : [cell])
                                  .map(_inline)
                                  .toList(),
                        ),
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
