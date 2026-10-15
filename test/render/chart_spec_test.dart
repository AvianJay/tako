import 'package:flutter_test/flutter_test.dart';
import 'package:tako/ui/render/visuals/chart_layout.dart';
import 'package:tako/ui/render/visuals/chart_scale.dart';
import 'package:tako/ui/render/visuals/chart_spec.dart';

import 'fake_measurer.dart';

void main() {
  group('ChartSpec.parse', () {
    test('reads the documented shape', () {
      final spec = ChartSpec.parse(
        '{"type":"bar","title":"Requests","labels":["Jan","Feb"],'
        '"series":[{"name":"API","data":[120,210]}],"unit":"ms",'
        '"stacked":true,"horizontal":false,"source":"Logs"}',
      );
      expect(spec.type, ChartType.bar);
      expect(spec.title, 'Requests');
      expect(spec.labels, ['Jan', 'Feb']);
      expect(spec.series.single.name, 'API');
      expect(spec.series.single.data, [120, 210]);
      expect(spec.unit, 'ms');
      expect(spec.stacked, isTrue);
      expect(spec.horizontal, isFalse);
      expect(spec.source, 'Logs');
    });

    test('accepts Chart.js, value lists, numeric strings and gaps', () {
      final chartJs = ChartSpec.parse(
        '{"type":"line","data":{"labels":["a","b","c"],'
        '"datasets":[{"label":"x","data":[1,null,"3"]},'
        '{"label":"y","data":["1,200","45%"]}]}}',
      );
      expect(chartJs.type, ChartType.line);
      expect(chartJs.series.map((s) => s.name), ['x', 'y']);
      expect(chartJs.series.first.data, [1, null, 3]);
      expect(chartJs.series.last.data, [1200, 45, null]);

      final values = ChartSpec.parse('{"type":"column","values":[3,4]}');
      expect(values.type, ChartType.bar);
      expect(values.labels, ['1', '2']);

      final pie = ChartSpec.parse(
        '{"type":"doughnut","data":[{"label":"A","value":2},'
        '{"label":"B","value":3}]}',
      );
      expect(pie.type, ChartType.donut);
      expect(pie.labels, ['A', 'B']);
      expect(pie.series.single.data, [2, 3]);
    });

    test('names unnamed series and pads short ones', () {
      final spec = ChartSpec.parse(
        '{"labels":["a","b","c"],"series":[{"data":[1]},{"data":[2,3]}]}',
      );
      expect(spec.series.map((s) => s.name), ['#1', '#2']);
      expect(spec.series.first.data, [1, null, null]);
      expect(ChartSpec.parse('{"type":"hbar","data":[1]}').horizontal, isTrue);
    });

    test('rejects what cannot be drawn honestly', () {
      for (final source in [
        '[1,2,3]',
        '{"type":"scatter","data":[1]}',
        '{"labels":["a"]}',
        '{"data":[null,"x"]}',
        '{"type":"pie","labels":["a","b"],"data":[3,-1]}',
        '{"type":"pie","data":[0,0]}',
        '{"data":[${List.filled(201, 1).join(',')}]}',
        'not json',
      ]) {
        expect(
          () => ChartSpec.parse(source),
          throwsFormatException,
          reason: source,
        );
      }
    });

    test('only up to eight series are drawn', () {
      final series = [for (var i = 0; i < 9; i++) '{"data":[$i]}'];
      expect(
        ChartSpec.parse('{"series":[${series.join(',')}]}').drawable,
        isFalse,
      );
    });
  });

  group('NiceScale', () {
    test('uses clean steps with headroom and zero when asked', () {
      final scale = NiceScale.of(120, 320, includeZero: true);
      expect(scale.ticks, [0, 100, 200, 300, 400]);
      expect(NiceScale.of(0, 1, includeZero: true).ticks, [0, .25, .5, .75, 1]);
      expect(NiceScale.of(12.3, 45.6).ticks, [10, 20, 30, 40, 50]);
      expect(NiceScale.of(-30, 70, includeZero: true).ticks.first, -50);
    });

    test('flat data still gets a range', () {
      expect(NiceScale.of(0, 0, includeZero: true).max, greaterThan(0));
      final scale = NiceScale.of(5, 5);
      expect(scale.min, lessThan(5));
      expect(scale.max, greaterThan(5));
    });
  });

  group('ChartFormat', () {
    test('formats compactly per locale and keeps symbols on axes', () {
      final english = ChartFormat('en', '');
      expect(english.compact(1500), '1.5K');
      expect(english.full(1234.5), '1,234.5');
      expect(english.percent(.425), '42.5%');
      expect(ChartFormat('zh_TW', '').compact(12000), '1.2萬');
      expect(ChartFormat('en', 'ms').compact(120), '120 ms');
      expect(ChartFormat('en', 'ms').axis(120), '120');
      expect(ChartFormat('en', '%').axis(50), '50%');
      expect(ChartFormat('en', r'$').full(-3), r'-$3');
      expect(ChartFormat('zh_TW', '次').compact(120), '120次');
      expect(ChartFormat('xx_unknown', '').compact(2), '2');
    });
  });

  test('time labels are recognised', () {
    expect(looksTemporal(['2023', '2024', '2025']), isTrue);
    expect(looksTemporal(['1 月', '2 月', '3 月', '4 月']), isTrue);
    expect(looksTemporal(['Jan', 'Feb', 'Mar']), isTrue);
    expect(looksTemporal(['Q1', 'Q2', 'Q3', 'Q4']), isTrue);
    expect(looksTemporal(['週一', '週二', '週三']), isTrue);
    expect(looksTemporal(['Apples', 'Pears', 'Plums']), isFalse);
    expect(looksTemporal(['2024', '2025']), isFalse);
  });

  group('layoutChart', () {
    final text = FakeMeasurer();
    final format = ChartFormat('en', '');
    ChartLayout layout(String json, [double width = 320]) => layoutChart(
      ChartSpec.parse(json),
      width,
      text,
      format,
      other: 'Other',
      sourcePrefix: 'Source: ',
    );

    test('columns stay inside the chart and label every short value', () {
      final chart = layout(
        '{"labels":["Jan","Feb","Mar","Apr"],"data":[120,210,170,320]}',
      );
      expect(chart.form, ChartForm.columns);
      expect(chart.bars, hasLength(4));
      for (final bar in chart.bars) {
        expect(bar.rect.width, lessThanOrEqualTo(24));
        expect(bar.end, BarEnd.up);
        expect((Offset.zero & chart.size).contains(bar.rect.topLeft), isTrue);
      }
      expect(chart.texts.map((t) => t.text), containsAll(['120', '320']));
      // A single series needs no legend.
      expect(chart.keys, isEmpty);
    });

    test('long category names turn into rows, time labels do not', () {
      final rows = layout(
        '{"labels":["Smartphones","Laptop computers","Tablets",'
        '"Smart watches"],"data":[86,64,38,22]}',
      );
      expect(rows.form, ChartForm.rows);
      expect(rows.bars.every((bar) => bar.end == BarEnd.right), isTrue);
      final years = layout(
        '{"labels":[${[for (var y = 2000; y < 2020; y++) '"$y"'].join(',')}],'
        '"data":[${List.filled(20, 5).join(',')}]}',
      );
      expect(years.form, ChartForm.columns);
      final labels = years.texts
          .where((t) => RegExp(r'^20\d\d$').hasMatch(t.text))
          .toList();
      expect(labels.length, lessThan(20));
    });

    test('stacks separate segments and round only the outer end', () {
      final chart = layout(
        '{"labels":["a"],"stacked":true,'
        '"series":[{"name":"x","data":[2]},{"name":"y","data":[3]}]}',
      );
      expect(chart.bars, hasLength(2));
      final lower = chart.bars.firstWhere((bar) => bar.series == 0);
      final upper = chart.bars.firstWhere((bar) => bar.series == 1);
      expect(lower.end, BarEnd.none);
      expect(upper.end, BarEnd.up);
      expect(lower.rect.top - upper.rect.bottom, closeTo(2, .01));
      // Two series get a legend.
      expect(chart.keys, hasLength(2));
    });

    test('lines keep gaps and tap targets by category', () {
      final chart = layout(
        '{"type":"line","labels":["a","b","c"],"data":[1,null,3]}',
      );
      expect(chart.form, ChartForm.lines);
      expect(chart.lines.single.points[1], isNull);
      final middle = chart.centers[1];
      expect(chart.categoryAt(Offset(middle + 2, chart.plot.center.dy)), 1);
      expect(chart.categoryAt(const Offset(-50, -50)), isNull);
    });

    test('pies fold the tail into Other and hit-test slices', () {
      final chart = layout(
        '{"type":"pie","labels":["a","b","c","d","e","f","g"],'
        '"data":[40,20,15,10,8,4,3]}',
      );
      expect(chart.form, ChartForm.pie);
      expect(chart.slices, hasLength(6));
      expect(chart.slices.last.label, 'Other');
      expect(chart.slices.last.categories, [5, 6]);
      expect(chart.slices.last.color, -1);
      final total = chart.slices.fold<double>(0, (sum, s) => sum + s.sweep);
      expect(total, closeTo(2 * 3.14159265, 1e-6));
      // Just right of the top centre lies in the first, largest slice.
      expect(chart.sliceAt(chart.center + Offset(4, -chart.radius / 2)), 0);
      expect(chart.sliceAt(chart.center + Offset(chart.radius * 3, 0)), isNull);
    });

    test('a source adds a caption below the chart', () {
      final plain = layout('{"data":[1,2]}');
      final sourced = layout('{"data":[1,2],"source":"Example"}');
      expect(sourced.size.height, greaterThan(plain.size.height));
      expect(sourced.texts.last.text, 'Source: Example');
    });
  });
}
