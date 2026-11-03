import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tako/ui/render/text_colors.dart';

void main() {
  test('names, CSS names, hex and rgb() all parse', () {
    for (final (value, expected) in [
      ('red', textColors['red']),
      (' Blue ', textColors['blue']),
      ('grey', textColors['gray']),
      ('lightgreen', textColors['green']),
      ('dark-red', textColors['red']),
      ('hotpink', textColors['pink']),
      ('deepskyblue', textColors['blue']),
      ('fuchsia', textColors['pink']),
      ('yellow !important', textColors['yellow']),
      ('#f80', const Color(0xffff8800)),
      ('#FF8800', const Color(0xffff8800)),
      ('#ff880080', const Color(0xffff8800)),
      ('rgb(255, 136, 0)', const Color(0xffff8800)),
      ('rgba(255,136,0,0.5)', const Color(0xffff8800)),
      ('black', const Color(0xff000000)),
      ('white', const Color(0xffffffff)),
    ]) {
      expect(parseTextColor(value), expected, reason: value);
    }
    for (final value in ['', 'banana', '#12', '#12345', 'rgb(1,2)', 'dark']) {
      expect(parseTextColor(value), isNull, reason: value);
    }
  });

  // Tako's scaffold backgrounds and the text drawn on them.
  final themes = {
    'light': (
      const Color(0xfffafbf7),
      ColorScheme.fromSeed(seedColor: const Color(0xff466953)).onSurface,
    ),
    'dark': (
      const Color(0xff121713),
      ColorScheme.fromSeed(
        seedColor: const Color(0xff466953),
        brightness: Brightness.dark,
      ).onSurface,
    ),
  };
  final colors = {
    ...textColors,
    'black': const Color(0xff000000),
    'white': const Color(0xffffffff),
  };

  test('every colour is readable as text in both themes', () {
    for (final MapEntry(key: theme, value: (background, _)) in themes.entries) {
      for (final MapEntry(key: name, value: color) in colors.entries) {
        final text = readableTextColor(color, background);
        expect(
          contrastRatio(text, background),
          greaterThanOrEqualTo(4.5),
          reason: '$name on $theme',
        );
      }
    }
    // Colours that are already readable keep their exact value.
    expect(
      readableTextColor(textColors['blue']!, const Color(0xff121713)),
      textColors['blue'],
    );
  });

  test('every highlighter keeps text readable and stays visible', () {
    for (final MapEntry(key: theme, value: (background, ink))
        in themes.entries) {
      for (final MapEntry(key: name, value: color) in textColors.entries) {
        final fill = highlightColor(color, background, ink);
        expect(
          contrastRatio(ink, fill),
          greaterThanOrEqualTo(4.5),
          reason: '$name on $theme',
        );
        expect(
          contrastRatio(fill, background),
          greaterThan(1.15),
          reason: '$name on $theme',
        );
      }
    }
  });
}
