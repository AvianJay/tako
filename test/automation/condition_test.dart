import 'package:flutter_test/flutter_test.dart';
import 'package:tako/core/automation/automation.dart';
import 'package:tako/core/automation/condition.dart';

void main() {
  test('package and Chinese title match; missing fields are empty', () {
    final condition = NotificationCondition(
      'package == "jp.naver.line" and "班群" in title',
    );
    expect(
      condition.matches({'package': 'jp.naver.line', 'title': '三年甲班群'}),
      isTrue,
    );
    expect(condition.matches({'package': 'other', 'title': '班群'}), isFalse);
    expect(condition.matches({'package': 'jp.naver.line'}), isFalse);
  });
  test('boolean precedence, grouping, lists, escapes and negation', () {
    final condition = NotificationCondition(
      '(package in ["a", "b"] or "urgent" in text) and not ongoing and "spam" not in title',
    );
    expect(condition.matches({'package': 'a'}), isTrue);
    expect(condition.matches({'package': 'a', 'ongoing': true}), isFalse);
    expect(
      condition.matches({'text': 'urgent: action', 'title': 'spam'}),
      isFalse,
    );
    expect(
      NotificationCondition(r'''"a\"b" in title''').matches({'title': 'a"b'}),
      isTrue,
    );
  });
  test(
    'form round trip preserves special text and cannot erase advanced filters',
    () {
      final expression = NotificationCondition.form(
        package: 'app.id',
        title: '班群 "a" and b',
        text: 'a\nb\\c',
      );
      expect(NotificationCondition.formValues(expression), {
        'package': 'app.id',
        'title': '班群 "a" and b',
        'text': 'a\nb\\c',
      });
      expect(
        NotificationCondition.formValues('"a" in title or "b" in text'),
        isNull,
      );
      expect(NotificationCondition.formValues('title == "a"'), isNull);
    },
  );
  test(
    'invalid syntax, unknown fields, calls, access and excessive nesting fail',
    () {
      for (final expression in [
        'exec("x")',
        'title.contains("x")',
        'package = "x"',
        '"unterminated',
        'unknown == "x"',
        'true; false',
        '${'(' * 40}true${')' * 40}',
      ]) {
        expect(
          () => NotificationCondition(expression),
          throwsFormatException,
          reason: expression,
        );
      }
    },
  );
  test('silent sentinel is a complete, case-sensitive final answer', () {
    expect(isSilentAutomationResult(' \n[SILENT]\t'), isTrue);
    for (final value in ['', '[silent]', 'hello [SILENT]', '[SILENT]\nhello']) {
      expect(isSilentAutomationResult(value), isFalse);
    }
  });
  test('daily/weekly schedules and interval preserve the intended timing', () {
    final now = DateTime(2026, 10, 16, 20, 0);
    expect(
      const AutomationSchedule().nextAfter(now),
      DateTime(2026, 10, 17, 20).toUtc(),
    );
    expect(
      const AutomationSchedule(
        frequency: 'weekly',
        weekdays: [1],
        hour: 9,
      ).nextAfter(now),
      DateTime(2026, 10, 19, 9).toUtc(),
    );
    expect(
      const AutomationSchedule(
        frequency: 'interval',
        everyMinutes: 15,
      ).nextAfter(now),
      now.add(const Duration(minutes: 15)).toUtc(),
    );
    expect(
      AutomationSchedule(frequency: 'once', at: now).nextAfter(now),
      isNull,
    );
    expect(
      () => const AutomationSchedule(
        frequency: 'interval',
        everyMinutes: 1,
      ).validate(),
      throwsFormatException,
    );
  });
}
