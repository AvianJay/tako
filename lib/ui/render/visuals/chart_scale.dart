import 'dart:math' as math;

import 'package:intl/intl.dart';

/// Axis bounds on clean steps (1, 2, 2.5 or 5 × 10ⁿ), with 2–6 intervals.
class NiceScale {
  const NiceScale(this.min, this.max, this.step);

  factory NiceScale.of(double low, double high, {bool includeZero = false}) {
    if (includeZero) {
      low = math.min(low, 0);
      high = math.max(high, 0);
    }
    if (high - low < 1e-9) {
      final pad = low == 0 ? 1.0 : low.abs() * .1;
      high += pad;
      if (!(includeZero && low == 0)) low -= pad;
    }
    final span = high - low;
    final base = math
        .pow(10, (math.log(span / 4) / math.ln10).floor())
        .toDouble();
    NiceScale? best;
    var bestScore = double.infinity;
    for (final exponent in [base / 10, base, base * 10]) {
      for (final multiplier in const [1, 2, 2.5, 5]) {
        final step = exponent * multiplier;
        final min = (low / step).floorToDouble() * step;
        final max = (high / step).ceilToDouble() * step;
        final intervals = ((max - min) / step).round();
        if (intervals < 2 || intervals > 6) continue;
        final score = (max - min - span) / span + (intervals - 4).abs() * .08;
        if (score < bestScore - 1e-9) {
          bestScore = score;
          best = NiceScale(min, max, step);
        }
      }
    }
    return best ?? NiceScale(low, high, span);
  }

  final double min;
  final double max;
  final double step;

  List<double> get ticks {
    final decimals = math.max(0, -(math.log(step) / math.ln10).floor() + 1);
    final count = ((max - min) / step).round();
    return [
      for (var i = 0; i <= count; i++)
        double.parse((min + i * step).toStringAsFixed(decimals)),
    ];
  }

  /// 0 at [min], 1 at [max].
  double fraction(double value) => max == min ? 0 : (value - min) / (max - min);
}

/// Locale-aware chart numbers with the spec's unit attached.
class ChartFormat {
  factory ChartFormat(String localeName, String unit) {
    final locale =
        Intl.verifiedLocale(
          localeName,
          NumberFormat.localeExists,
          onFailure: (_) => 'en',
        ) ??
        'en';
    return ChartFormat._(
      unit,
      NumberFormat.compact(locale: locale),
      NumberFormat.decimalPattern(locale)..maximumFractionDigits = 2,
      NumberFormat.percentPattern(locale)..maximumFractionDigits = 1,
    );
  }

  ChartFormat._(this.unit, this._compact, this._decimal, this._percent);

  final String unit;
  final NumberFormat _compact;
  final NumberFormat _decimal;
  final NumberFormat _percent;

  /// Labels on marks: 1.2K, 3.4萬.
  String compact(double value) => _attach(_compact.format(value));

  /// Axis ticks keep only symbols (%, currency); a word unit on every tick
  /// is noise, and the marks and tooltips still carry it.
  String axis(double value) =>
      unit == '%' || _prefixed ? compact(value) : _compact.format(value);

  bool get _prefixed =>
      unit.endsWith(r'$') ||
      const {'€', '£', '¥', '₩', '₹', '₫', '฿'}.contains(unit);

  /// Tooltips and tables.
  String full(double value) => _attach(_decimal.format(value));

  String percent(double ratio) => _percent.format(ratio);

  String _attach(String number) {
    if (unit.isEmpty) return number;
    if (_prefixed) {
      return number.startsWith('-')
          ? '-$unit${number.substring(1)}'
          : '$unit$number';
    }
    return RegExp(r'^[A-Za-z]').hasMatch(unit)
        ? '$number $unit'
        : '$number$unit';
  }
}

final _temporal = RegExp(
  r'^(?:'
  r'(?:19|20)\d{2}(?:\s*[-/.年]\s*\d{1,2}(?:\s*[-/.月]\s*\d{1,2}\s*日?)?\s*月?|\s*年)?'
  r'|\d{1,2}\s*[-/.]\s*\d{1,2}'
  r'|\d{1,2}\s*月(?:\s*\d{1,2}\s*日)?'
  r'|Q[1-4](?:\s*(?:19|20)?\d{2})?|(?:19|20)\d{2}\s*Q[1-4]'
  r'|第?\s*[一二三四1-4]\s*季度?'
  r'|\d{1,2}:\d{2}'
  r'|(?:週|周|星期|禮拜)[一二三四五六日天]'
  r'|(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?(?:\s*\d{2,4})?'
  r'|(?:mon|tue|wed|thu|fri|sat|sun)[a-z]*\.?'
  r'|w(?:ee)?k\s*\d{1,2}|第\s*\d{1,2}\s*週'
  r')$',
  caseSensitive: false,
);

/// Years, months, dates and similar labels keep their columns in order;
/// they skip labels instead of turning into horizontal bars.
bool looksTemporal(List<String> labels) =>
    labels.length >= 3 &&
    labels.where((label) => _temporal.hasMatch(label.trim())).length >=
        labels.length * .8;
