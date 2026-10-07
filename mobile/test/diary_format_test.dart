import 'package:driver_shift_diary/formatting/diary_format.dart';
import 'package:driver_shift_diary/models/diary_date.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  test(
    'calendar dates are strict, stable keys and traverse month/year/leap days',
    () {
      expect(DiaryDate.parse('2026-10-01'), DiaryDate(2026, 10, 1));
      expect(
        DiaryDate(2026, 10, 1).hashCode,
        DiaryDate.parse('2026-10-01').hashCode,
      );
      expect(DiaryDate(2026, 1, 1).previous, DiaryDate(2025, 12, 31));
      expect(DiaryDate(2024, 2, 28).next, DiaryDate(2024, 2, 29));
      expect(DiaryDate(2024, 2, 29).next, DiaryDate(2024, 3, 1));
      expect(DiaryDate(2026, 12, 31).next, DiaryDate(2027, 1, 1));
      expect(DiaryDate(1, 1, 2).iso8601, '0001-01-02');
      expect(formatDay(DiaryDate(2026, 10, 1)), '1 октября 2026');
      for (final value in [
        '2026-2-01',
        '2026-02-29',
        '2026-13-01',
        '0000-01-01',
      ]) {
        expect(() => DiaryDate.parse(value), throwsFormatException);
      }
    },
  );

  test(
    'money is grouped exactly with zero, negatives and integers beyond int64',
    () {
      expect(formatMoney(BigInt.zero), '0 ₸');
      expect(formatMoney(BigInt.from(3315)), '3 315 ₸');
      expect(formatMoney(BigInt.from(-5)), '−5 ₸');
      expect(
        formatMoney(BigInt.parse('18446744073709551614')),
        '18 446 744 073 709 551 614 ₸',
      );
    },
  );

  test('today and trip times use Almaty rather than the device/local zone', () {
    final before = DateTime.parse('2026-10-01T18:59:59.999999Z');
    final midnight = DateTime.parse('2026-10-01T19:00:00Z');
    expect(almatyDay(before), DiaryDate(2026, 10, 1));
    expect(almatyDay(midnight), DiaryDate(2026, 10, 2));
    final original = tz.local;
    tz.setLocalLocation(tz.getLocation('America/New_York'));
    addTearDown(() => tz.setLocalLocation(original));
    expect(almatyDay(midnight), DiaryDate(2026, 10, 2));
    expect(formatTripTime(DateTime.parse('2026-10-01T03:10:00Z')), '08:10');
    expect(
      formatTripTime(DateTime.parse('2026-10-01T08:10:00+05:00')),
      '08:10',
    );
    expect(formatTripRange(before, midnight), '23:59 – 00:00 (2 октября 2026)');
    expect(
      formatTripRange(
        DateTime.parse('2026-10-01T03:10Z'),
        DateTime.parse('2026-10-01T03:32Z'),
      ),
      '08:10 – 08:32',
    );
  });

  test(
    'historic Almaty offset follows IANA rather than a fixed five hours',
    () {
      final beforeChange = almatyTime(DateTime.parse('2024-02-29T17:30:00Z'));
      final afterChange = almatyTime(DateTime.parse('2024-02-29T18:30:00Z'));
      expect(beforeChange.hour, 23);
      expect(beforeChange.timeZoneOffset, const Duration(hours: 6));
      expect(afterChange.hour, 23);
      expect(afterChange.timeZoneOffset, const Duration(hours: 5));
      expect(
        almatyDay(DateTime.parse('2024-02-29T18:59:59Z')),
        DiaryDate(2024, 2, 29),
      );
      expect(
        almatyDay(DateTime.parse('2024-02-29T19:00:00Z')),
        DiaryDate(2024, 3, 1),
      );
    },
  );
}
