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

    test('reads radar charts and their aliases', () {
      final spec = ChartSpec.parse(
        '{"type":"radar","title":"Phones","labels":["Speed","Price",'
        '"Battery","Camera","Screen"],"series":[{"name":"A","data":'
        '[8,6,9,7,8]},{"name":"B","data":[7,9,null,8,7]}],"max":10,'
        '"unit":"pts"}',
      );
      expect(spec.type, ChartType.radar);
      expect(spec.labels, hasLength(5));
      expect(spec.series.last.data[2], isNull);
      expect(spec.max, 10);
      expect(spec.unit, 'pts');
      for (final alias in ['spider', 'Spider Web', 'web']) {
        expect(
          ChartSpec.parse(
            '{"type":"$alias","labels":["a","b","c"],"data":[1,2,3]}',
          ).type,
          ChartType.radar,
          reason: alias,
        );
      }
      final chartJs = ChartSpec.parse(
        '{"type":"radar","data":{"labels":["a","b","c"],"datasets":'
        '[{"label":"x","data":[1,2,3]}]},'
        '"options":{"scales":{"r":{"suggestedMax":5}}}}',
      );
      expect(chartJs.max, 5);
    });

    test('a radar that cannot be drawn honestly becomes bars', () {
      for (final source in [
        '{"type":"radar","labels":["a","b"],"data":[1,2]}',
        '{"type":"radar","data":[${List.filled(13, 1).join(',')}]}',
        '{"type":"radar","labels":["a","b","c"],"data":[1,-2,3],"max":5}',
      ]) {
        final spec = ChartSpec.parse(source);
        expect(spec.type, ChartType.bar, reason: source);
        expect(spec.max, isNull, reason: source);
      }
      expect(
        ChartSpec.parse(
          '{"type":"radar","labels":["a","b","c"],"data":[1,2,3],"max":-1}',
        ).max,
        isNull,
      );
    });

    test('reads scatter points in every shape', () {
      final spec = ChartSpec.parse(
        '{"type":"scatter","title":"Price and rating","xLabel":"Price",'
        '"yLabel":"Rating","series":[{"name":"Phones","data":[[12900,4.5],'
        '{"x":8990,"y":"4.1","label":"Pixel"},[15900,4.4,"Pixel Pro"],'
        '["Galaxy",24900,4.7],[1,null],"x"]}]}',
      );
      expect(spec.type, ChartType.scatter);
      expect(spec.labels, isEmpty);
      expect(spec.xLabel, 'Price');
      expect(spec.yLabel, 'Rating');
      final points = spec.series.single.points;
      expect(points.map((p) => (p.x, p.y, p.label)), [
        (12900, 4.5, null),
        (8990, 4.1, 'Pixel'),
        (15900, 4.4, 'Pixel Pro'),
        (24900, 4.7, 'Galaxy'),
      ]);

      final chartJs = ChartSpec.parse(
        '{"type":"scatter","data":{"datasets":[{"label":"A","data":'
        '[{"x":1,"y":2}]},{"data":[{"x":3,"y":4}]}]},"options":{"scales":'
        '{"x":{"title":{"display":true,"text":"Time"}},'
        '"yAxes":[{"scaleLabel":{"labelString":"Signal"}}]}}}',
      );
      expect(chartJs.series.map((s) => s.name), ['A', '#2']);
      expect(chartJs.xLabel, 'Time');
      expect(chartJs.yLabel, 'Signal');

      final parallel = ChartSpec.parse(
        '{"type":"xy","series":[{"name":"S","x":[1,2],"y":[3,4],'
        '"labels":["p","q"]}],"xAxis":{"title":"Width"},"xUnit":"cm"}',
      );
      expect(parallel.series.single.points.map((p) => (p.x, p.y, p.label)), [
        (1, 3, 'p'),
        (2, 4, 'q'),
      ]);
      expect(parallel.xLabel, 'Width');
      expect(parallel.xUnit, 'cm');

      final numericLabels = ChartSpec.parse(
        '{"type":"points","labels":[10,20,30],"data":[1,2,3]}',
      );
      expect(numericLabels.series.single.points.map((p) => p.x), [10, 20, 30]);
      final named = ChartSpec.parse(
        '{"type":"scatterplot","labels":["a","b"],"data":[[1,2],[3,4]]}',
      );
      expect(named.series.single.points.map((p) => p.label), ['a', 'b']);
    });

    test('scatter charts keep their limits', () {
      String points(int count) =>
          [for (var i = 0; i < count; i++) '[$i,$i]'].join(',');
      expect(
        ChartSpec.parse(
          '{"type":"scatter","data":[${points(500)}]}',
        ).series.single.points,
        hasLength(500),
      );
      for (final source in [
        '{"type":"scatter","data":[${points(501)}]}',
        '{"type":"scatter","series":'
            '[${List.filled(25, '{"data":[[1,2]]}').join(',')}]}',
        '{"type":"scatter","data":[[1,null],["a","b"]]}',
        '{"type":"scatter","labels":["a","b"],"data":[1,2]}',
        '{"type":"scatter"}',
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

    test('a given top stays the top, on whole steps when whole', () {
      expect(NiceScale.upTo(10).ticks, [0, 2, 4, 6, 8, 10]);
      expect(NiceScale.upTo(100).ticks, [0, 25, 50, 75, 100]);
      expect(NiceScale.upTo(7).ticks, [0, 1, 2, 3, 4, 5, 6, 7]);
      expect(NiceScale.upTo(7.5).ticks, [0, 2.5, 5, 7.5]);
      expect(NiceScale.upTo(1).max, 1);
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
      expect(ChartFormat('en', 'kg').withUnit('cm').full(170), '170 cm');
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

    void expectInside(ChartLayout chart) {
      final bounds = (Offset.zero & chart.size).inflate(.5);
      for (final placed in [...chart.texts, ...chart.underlay]) {
        final size = text.measure(
          placed.text,
          placed.role,
          maxWidth: placed.maxWidth,
          maxLines: placed.maxLines,
        );
        expect(
          bounds.contains(placed.offset) &&
              bounds.contains((placed.offset & size).bottomRight),
          isTrue,
          reason: '${placed.text} at ${placed.offset} in ${chart.size}',
        );
      }
    }

    test('radar labels clear the web, each other and the edges', () {
      for (final (json, width) in [
        (
          '{"type":"radar","labels":["Speed","Price","Battery life",'
              '"Camera","Screen"],"series":[{"name":"A","data":[8,6,9,7,8]},'
              '{"name":"B","data":[7,9,null,8,7]}],"max":10}',
          320.0,
        ),
        (
          '{"type":"radar","labels":["Keyboard and trackpad","Display",'
              '"Software updates","Charging speed","Price","Performance",'
              '"Build quality","Battery life"],"data":[1,2,3,4,5,6,7,8]}',
          240.0,
        ),
        (
          '{"type":"radar","labels":[${List.generate(12, (i) => '"第${i + 1}項營收成長率"').join(',')}],'
              '"data":[${List.filled(12, 3).join(',')}]}',
          286.0,
        ),
      ]) {
        final chart = layout(json, width);
        expect(chart.form, ChartForm.radar);
        expect(chart.spokes, hasLength(chart.targets.length));
        expectInside(chart);
        for (final (i, a) in chart.targets.indexed) {
          final offset = a.center - chart.center;
          expect(offset.distance, greaterThan(chart.radius), reason: '$i');
          for (final b in chart.targets.skip(i + 1)) {
            expect(a.overlaps(b), isFalse, reason: '$a $b');
          }
        }
      }
    });

    test('radars scale from the centre and pick spokes by angle', () {
      final chart = layout(
        '{"type":"radar","labels":["a","b","c","d"],"series":'
        '[{"name":"x","data":[10,5,null,0]},{"name":"y","data":[1,2,3,4]}],'
        '"max":10}',
      );
      final web = chart.lines.first.points;
      expect((web[0]! - chart.spokes[0]).distance, lessThan(.01));
      expect((web[1]! - chart.center).distance, closeTo(chart.radius / 2, .01));
      expect(web[2], isNull);
      expect((web[3]! - chart.center).distance, lessThan(.01));
      expect(chart.rings.last, chart.radius);
      expect(chart.keys.every((key) => key.line), isTrue);
      final east = chart.center + Offset(chart.radius * .7, 6);
      expect(chart.axisAt(east), 1);
      expect(chart.axisAt(chart.targets[2].center), 2);
      expect(chart.axisAt(chart.center + Offset(0, -chart.radius * 3)), isNull);
    });

    test('scatter dots fill fitted axes and are found by proximity', () {
      final chart = layout(
        '{"type":"scatter","xLabel":"Price","yLabel":"Rating","series":'
        '[{"name":"A","data":[[5990,3.8],[24900,4.7]]},'
        '{"name":"B","data":[[12900,4.5]]}]}',
      );
      expect(chart.form, ChartForm.scatter);
      expect(chart.dots, hasLength(3));
      expect(chart.dots.map((d) => (d.series, d.index)), [
        (0, 0),
        (0, 1),
        (1, 0),
      ]);
      for (final dot in chart.dots) {
        expect(chart.plot.inflate(.5).contains(dot.center), isTrue);
      }
      // Fitted, not stretched to zero.
      expect(chart.dots.first.center.dx - chart.plot.left, lessThan(30));
      expect(chart.verticals, isNotEmpty);
      expect(chart.keys.every((key) => key.dot), isTrue);
      expect(chart.texts.map((t) => t.text), containsAll(['Price', 'Rating']));
      expectInside(chart);
      expect(chart.dotAt(chart.dots[2].center + const Offset(10, 8)), 2);
      expect(chart.dotAt(chart.dots[2].center + const Offset(40, 0)), isNull);
    });

    test('a source adds a caption below the chart', () {
      final plain = layout('{"data":[1,2]}');
      final sourced = layout('{"data":[1,2],"source":"Example"}');
      expect(sourced.size.height, greaterThan(plain.size.height));
      expect(sourced.texts.last.text, 'Source: Example');
    });
  });
}
