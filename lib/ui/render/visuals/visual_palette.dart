import 'package:flutter/material.dart';

/// The categorical order is the colour-blind safety mechanism: assign slots
/// in order and never cycle them. Both modes were validated against Tako's
/// scaffold backgrounds (#fafbf7 and #121713). In light mode aqua, yellow
/// and magenta stay below 3:1, so charts always offer a table view.
const _lightSeries = [
  Color(0xff2a78d6),
  Color(0xffeb6834),
  Color(0xff1baf7a),
  Color(0xffeda100),
  Color(0xffe87ba4),
  Color(0xff008300),
  Color(0xff4a3aa7),
  Color(0xffe34948),
];

const _darkSeries = [
  Color(0xff3987e5),
  Color(0xffd95926),
  Color(0xff199e70),
  Color(0xffc98500),
  Color(0xffd55181),
  Color(0xff008300),
  Color(0xff9085e9),
  Color(0xffe66767),
];

enum CalloutKind { note, tip, important, warning, caution }

/// Colours for charts, diagrams and callouts. Marks take series colours;
/// text always takes ink colours.
@immutable
class VisualPalette {
  const VisualPalette({
    required this.series,
    required this.neutral,
    required this.surface,
    required this.ink,
    required this.mutedInk,
    required this.grid,
    required this.baseline,
    required this.tooltip,
    required this.onTooltip,
    required this.nodeFill,
    required this.nodeStroke,
    required this.decisionFill,
    required this.onDecision,
    required this.terminalFill,
    required this.onTerminal,
    required this.clusterFill,
    required this.noteFill,
    required this.onNote,
    required this.edge,
    required this.callouts,
  });

  factory VisualPalette.of(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return VisualPalette(
      series: dark ? _darkSeries : _lightSeries,
      neutral: const Color(0xff898781),
      surface: theme.scaffoldBackgroundColor,
      ink: scheme.onSurface,
      mutedInk: scheme.onSurfaceVariant,
      grid: scheme.outlineVariant.withValues(alpha: .55),
      baseline: scheme.outlineVariant,
      tooltip: scheme.inverseSurface,
      onTooltip: scheme.onInverseSurface,
      nodeFill: scheme.surfaceContainerHighest,
      nodeStroke: scheme.outlineVariant,
      decisionFill: scheme.secondaryContainer,
      onDecision: scheme.onSecondaryContainer,
      terminalFill: scheme.primaryContainer,
      onTerminal: scheme.onPrimaryContainer,
      clusterFill: scheme.surfaceContainerLow,
      noteFill: scheme.tertiaryContainer,
      onNote: scheme.onTertiaryContainer,
      edge: scheme.onSurfaceVariant,
      // GitHub's alert colours, readable on either surface.
      callouts: dark
          ? const {
              CalloutKind.note: Color(0xff4493f8),
              CalloutKind.tip: Color(0xff3fb950),
              CalloutKind.important: Color(0xffab7df8),
              CalloutKind.warning: Color(0xffd29922),
              CalloutKind.caution: Color(0xfff85149),
            }
          : const {
              CalloutKind.note: Color(0xff0969da),
              CalloutKind.tip: Color(0xff1a7f37),
              CalloutKind.important: Color(0xff8250df),
              CalloutKind.warning: Color(0xff9a6700),
              CalloutKind.caution: Color(0xffd1242f),
            },
    );
  }

  final List<Color> series;

  /// "Other" slices and branches past the eighth series slot.
  final Color neutral;

  /// The background behind visuals: surface gaps and marker rings use it.
  final Color surface;
  final Color ink;
  final Color mutedInk;
  final Color grid;
  final Color baseline;
  final Color tooltip;
  final Color onTooltip;
  final Color nodeFill;
  final Color nodeStroke;
  final Color decisionFill;
  final Color onDecision;
  final Color terminalFill;
  final Color onTerminal;
  final Color clusterFill;
  final Color noteFill;
  final Color onNote;
  final Color edge;
  final Map<CalloutKind, Color> callouts;

  /// Slots past the palette fold into [neutral] rather than repeating a hue.
  Color seriesColor(int index) =>
      index >= 0 && index < series.length ? series[index] : neutral;

  @override
  bool operator ==(Object other) =>
      other is VisualPalette &&
      identical(other.series, series) &&
      other.surface == surface &&
      other.ink == ink &&
      other.mutedInk == mutedInk &&
      other.grid == grid &&
      other.nodeFill == nodeFill &&
      other.decisionFill == decisionFill &&
      other.terminalFill == terminalFill &&
      other.noteFill == noteFill &&
      other.tooltip == tooltip;

  @override
  int get hashCode => Object.hash(
    series,
    surface,
    ink,
    mutedInk,
    grid,
    nodeFill,
    decisionFill,
    terminalFill,
    noteFill,
    tooltip,
  );
}
