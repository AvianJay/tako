import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/screen/screen_capability.dart';

/// Parses iCTRL's text hierarchy without exposing its verbose hints to models.
ScreenTree parseIctrlTree(
  Map<String, Object?> result, {
  required int token,
  required int width,
  required int height,
}) {
  final nodes = <ScreenNode>[];
  final parents = <(int, int)>[];
  final frames = RegExp(
    r'\{\{(-?[\d.]+),\s*(-?[\d.]+)\},\s*\{([\d.]+),\s*([\d.]+)\}\}',
  );
  final source = result['source'] as String? ?? '';
  var label = '';
  var dialog = false;
  for (final line in _sourceRecords(source)) {
    final frame = frames.allMatches(line).lastOrNull;
    if (frame == null || nodes.length >= 400) continue;
    final indent = line.length - line.trimLeft().length;
    final type = line.trimLeft().split(',').first;
    String field(String name) {
      final start = line.indexOf("$name: '");
      if (start < 0) return '';
      final offset = start + name.length + 3;
      final end = line.indexOf("', ", offset);
      return end < 0 ? '' : line.substring(offset, end);
    }

    final text = field('label');
    final value = field('value');
    final identifier = field('id');
    final x = double.parse(frame[1]!);
    final y = double.parse(frame[2]!);
    final w = double.parse(frame[3]!);
    final h = double.parse(frame[4]!);
    if (type == 'Application') {
      label = text.trim();
      if (w > 0 && h > 0) {
        width = w.round();
        height = h.round();
      }
    }
    while (parents.isNotEmpty && parents.last.$1 >= indent) {
      parents.removeLast();
    }
    final parent = parents.isEmpty ? -1 : parents.last.$2;
    final editable = {
      'TextField',
      'SearchField',
      'SecureTextField',
      'TextView',
    }.contains(type);
    final password = type == 'SecureTextField';
    final clickable = {
      'Button',
      'Link',
      'Cell',
      'Icon',
      'Key',
      'Switch',
      'Picker',
      'PickerWheel',
      'SegmentedControl',
    }.contains(type);
    final scrollable = {
      'ScrollView',
      'Table',
      'CollectionView',
      'WebView',
    }.contains(type);
    dialog |= type == 'Alert' || type == 'Sheet';
    nodes.add(
      ScreenNode(
        parent: parent,
        className: ictrlNodeClass(type),
        text: password
            ? null
            : value.isNotEmpty
            ? value
            : text,
        description: text.isEmpty ? null : text,
        viewId: identifier.isEmpty ? null : identifier,
        flags:
            ScreenFlags.enabled |
            (clickable ? ScreenFlags.clickable : 0) |
            (editable ? ScreenFlags.editable | ScreenFlags.clickable : 0) |
            (password ? ScreenFlags.password : 0) |
            (scrollable ? ScreenFlags.scrollable : 0) |
            (type == 'Switch' ? ScreenFlags.checkable : 0) |
            (type == 'Switch' && value == '1' ? ScreenFlags.checked : 0),
        bounds: ScreenBounds(
          x.round(),
          y.round(),
          (x + w).round(),
          (y + h).round(),
        ),
        check: ictrlNodeCheck(type, text, identifier),
      ),
    );
    parents.add((indent, nodes.length - 1));
  }
  // Unnamed containers are identified by their contents, not just "Cell|".
  final ends = List<int>.generate(nodes.length, (index) => index);
  for (var i = nodes.length - 1; i >= 0; i--) {
    final parent = nodes[i].parent;
    if (parent >= 0 && ends[i] > ends[parent]) ends[parent] = ends[i];
  }
  for (var i = 0; i < nodes.length; i++) {
    final n = nodes[i];
    // iCTRL's container labels may repeat all descendants. Keep leaf text and
    // actionable controls; omit repeated wrapper summaries from model input.
    if ((!n.actionable && n.className == 'Other' || n.scrollable) &&
        ends[i] > i &&
        nodes
            .sublist(i + 1, ends[i] + 1)
            .any((c) => c.description?.isNotEmpty == true)) {
      nodes[i] = ScreenNode(
        parent: n.parent,
        className: n.className,
        flags: n.flags,
        bounds: n.bounds,
        check: n.check,
        viewId: n.viewId,
      );
      continue;
    }
    if (!n.actionable &&
        n.description?.isNotEmpty == true &&
        nodes
            .sublist(0, i)
            .any(
              (p) =>
                  p.description == n.description &&
                  (p.bounds.left - n.bounds.left).abs() < 3 &&
                  (p.bounds.top - n.bounds.top).abs() < 3,
            )) {
      nodes[i] = ScreenNode(
        parent: n.parent,
        className: n.className,
        flags: n.flags,
        bounds: n.bounds,
        check: n.check,
        viewId: n.viewId,
      );
      continue;
    }
    if (!n.actionable ||
        n.viewId != null ||
        n.description != null ||
        n.text?.isNotEmpty == true ||
        ends[i] == i) {
      continue;
    }
    final children = nodes.sublist(i + 1, ends[i] + 1);
    nodes[i] = ScreenNode(
      parent: n.parent,
      className: n.className,
      flags: n.flags,
      bounds: n.bounds,
      check: ictrlNodeCheck(
        n.className,
        children.map((c) => c.check).join('|'),
        '',
      ),
    );
  }
  final ocr = result['ocr_items'] as List? ?? const [];
  for (final item in ocr.take(100)) {
    if (item is! Map) continue;
    final x = (item['x'] as num?)?.round() ?? 0;
    final y = (item['y'] as num?)?.round() ?? 0;
    final text = item['label'] as String? ?? '';
    if (text.isEmpty) continue;
    final ow = (item['width'] as num?)?.round() ?? 0;
    final oh = (item['height'] as num?)?.round() ?? 0;
    final cx = x + ow / 2;
    final cy = y + oh / 2;
    if (nodes.any(
      (n) =>
          (normalizeIctrlOcr(n.description ?? '') == normalizeIctrlOcr(text) &&
              (n.bounds.left - x).abs() < 8 &&
              (n.bounds.top - y).abs() < 8) ||
          // A small labeled AX control already names the action at this point.
          // OCR fragments and recognition typos must not create extra targets.
          (n.clickable &&
              n.description?.isNotEmpty == true &&
              n.bounds.area < width * height * .15 &&
              cx >= n.bounds.left &&
              cx < n.bounds.right &&
              cy >= n.bounds.top &&
              cy < n.bounds.bottom),
    )) {
      continue;
    }
    nodes.add(
      ScreenNode(
        className: 'OCRText',
        text: text,
        flags: ScreenFlags.enabled | ScreenFlags.clickable,
        bounds: ScreenBounds(x, y, x + ow, y + oh),
        check: ictrlNodeCheck('OCRText', normalizeIctrlOcr(text), ''),
      ),
    );
  }
  final bundle = result['bundle_id'] as String? ?? '';
  final own = bundle.startsWith('tw.avianjay.tako');
  return ScreenTree(
    token: token,
    packageName: bundle,
    appLabel: label,
    width: width,
    height: height,
    ownAppInFront: own,
    nodes: own ? const [] : nodes,
    windows: [
      ScreenWindow(
        id: 0,
        packageName: bundle,
        own: own,
        type: dialog ? 2 : 1,
        bounds: ScreenBounds(0, 0, width, height),
      ),
    ],
    truncated: result['truncated'] == true || nodes.length >= 400,
  );
}

/// Native accessibility labels and values can contain literal newlines.
/// Their trailing frame closes a record; splitting on every newline loses the
/// control type, indentation and text (including password-field protection).
Iterable<String> _sourceRecords(String source) sync* {
  final end = RegExp(
    r'\{\{[-\d.]+,\s*[-\d.]+\},\s*\{[-\d.]+,\s*[-\d.]+\}\}\s*$',
  );
  final start = RegExp(r'^[ \t]*[A-Za-z][A-Za-z0-9]*,');
  StringBuffer? pending;
  for (final line in source.split('\n')) {
    if (pending == null) {
      if (!start.hasMatch(line)) continue;
      pending = StringBuffer(line);
    } else {
      pending.write('\n$line');
    }
    if (end.hasMatch(line)) {
      yield pending.toString();
      pending = null;
    }
  }
}

// OCR changes spacing and full-width punctuation between identical frames.
// Normalize only those presentation differences; never fuzzy-match words.
String normalizeIctrlOcr(String text) => String.fromCharCodes(
  text.runes.map((r) => r >= 0xff01 && r <= 0xff5e ? r - 0xfee0 : r),
).replaceAll(RegExp(r'\s+'), '');

String ictrlNodeClass(String type) => switch (type) {
  'TextField' || 'SearchField' || 'SecureTextField' => 'EditText',
  'ScrollView' || 'Table' || 'CollectionView' || 'WebView' => 'ScrollView',
  'StaticText' => 'Text',
  _ => type,
};

// The server's filters use broad lowercase roles, unlike the returned AX type.
// A labeled wrapper must not shadow a real button with the same label.
String? ictrlFindType(String className) => switch (className) {
  'Button' => 'button',
  'EditText' => 'textfield',
  'Text' => 'label',
  'Image' => 'image',
  'Cell' => 'cell',
  'Switch' => 'switch',
  'Icon' => 'icon',
  _ => null,
};

String ictrlNodeCheck(String type, String label, String identifier) => sha256
    .convert(utf8.encode('$type|$identifier|$label'))
    .toString()
    .substring(0, 16);
