import 'package:driver_shift_diary/formatting/diary_format.dart';
import 'package:driver_shift_diary/models/day.dart';
import 'package:driver_shift_diary/models/diary_date.dart';
import 'package:driver_shift_diary/models/trip_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('validated input normalizes UTC and retains exact integer money', () {
    final input = TripInput(
      start: DateTime.parse('2026-10-01T23:50:00+05:00'),
      end: DateTime.parse('2026-10-02T00:15:00+05:00'),
      amount: TripInput.moneyMaximum,
      commission: TripInput.moneyMaximum,
      payment: PaymentMethod.card,
    );
    final trip = input.withId('stable-id');
    expect(trip.id, 'stable-id');
    expect(trip.start, DateTime.utc(2026, 10, 1, 18, 50));
    expect(trip.end, DateTime.utc(2026, 10, 1, 19, 15));
    expect(trip.start.isUtc, isTrue);
    expect(trip.amount, BigInt.parse('9223372036854775807'));
    expect(trip.commission, trip.amount);
    expect(trip.payment, PaymentMethod.card);
    expect(almatyDay(trip.start), DiaryDate(2026, 10, 1));
  });

  for (final amount in [
    BigInt.zero,
    -BigInt.one,
    TripInput.moneyMaximum + BigInt.one,
  ]) {
    test('rejects amount $amount', () {
      expect(() => _input(amount: amount), throwsFormatException);
    });
  }
  for (final commission in [-BigInt.one, TripInput.moneyMaximum + BigInt.one]) {
    test('rejects commission $commission', () {
      expect(() => _input(commission: commission), throwsFormatException);
    });
  }
  test('commission can be zero or exceed amount', () {
    expect(_input(commission: BigInt.zero).commission, BigInt.zero);
    expect(_input(commission: BigInt.from(5000)).commission, BigInt.from(5000));
  });

  for (final end in [
    DateTime.utc(2026, 10, 1, 3),
    DateTime.utc(2026, 10, 1, 2),
  ]) {
    test('rejects end $end at or before start', () {
      expect(() => _input(end: end), throwsFormatException);
    });
  }
  test('rejects UTC timestamps outside backend representation', () {
    expect(() => _input(start: DateTime.utc(0, 12, 31)), throwsFormatException);
    expect(() => _input(end: DateTime.utc(10000)), throwsFormatException);
  });
  test('rejects start dates outside the readable diary interval', () {
    expect(
      () => _input(
        start: DateTime.utc(1, 1, 1, 12),
        end: DateTime.utc(1, 1, 1, 13),
      ),
      throwsFormatException,
    );
    expect(
      () => _input(
        start: DateTime.utc(9999, 12, 31, 3),
        end: DateTime.utc(9999, 12, 31, 4),
      ),
      throwsFormatException,
    );
  });
  test('start at the upper diary bound can end on the next day', () {
    final input = _input(
      start: almatyWallTime(DiaryDate.last, 23, 55),
      end: almatyWallTime(DiaryDate(9999, 12, 31), 0, 15),
    );
    expect(almatyDay(input.start), DiaryDate.last);
    expect(input.end.isAfter(input.start), isTrue);
  });

  for (final text in ['', '-1', '+1', '1.5', '1,5', '1e3', '1 000', 'abc']) {
    test('money validator rejects $text without numeric rounding', () {
      expect(TripInput.moneyError(text, isCommission: false), isNotNull);
      expect(TripInput.moneyError(text, isCommission: true), isNotNull);
      expect(() => TripInput.parseMoney(text), throwsFormatException);
    });
  }
  test('money validator accepts exact bounds and distinguishes zero', () {
    expect(TripInput.moneyError('0', isCommission: false), isNotNull);
    expect(TripInput.moneyError('0', isCommission: true), isNull);
    expect(TripInput.moneyError(' 0001 ', isCommission: false), isNull);
    expect(
      TripInput.moneyError('9223372036854775807', isCommission: false),
      isNull,
    );
    expect(
      TripInput.moneyError('9223372036854775808', isCommission: true),
      isNotNull,
    );
    expect(
      TripInput.parseMoney('9007199254740993'),
      BigInt.parse('9007199254740993'),
    );
  });

  test(
    'picker wall time uses Almaty historical offsets, independent of device',
    () {
      expect(
        almatyWallTime(DiaryDate(2026, 10, 1), 8, 10),
        DateTime.utc(2026, 10, 1, 3, 10),
      );
      expect(
        almatyWallTime(DiaryDate(2023, 10, 1), 8, 10),
        DateTime.utc(2023, 10, 1, 2, 10),
      );
      expect(
        almatyWallTime(DiaryDate(2026, 10, 1), 0, 0),
        DateTime.utc(2026, 9, 30, 19),
      );
    },
  );
  test('picker rejects historical nonexistent wall time', () {
    expect(
      () => almatyWallTime(DiaryDate(2004, 3, 28), 2, 30),
      throwsFormatException,
    );
  });
  test(
    'repeated historical wall time uses a deterministic valid occurrence',
    () {
      final date = DiaryDate(2024, 2, 29);
      final instant = almatyWallTime(date, 23, 30);
      expect(almatyWallTime(date, 23, 30), instant);
      expect(almatyDay(instant), date);
      expect(formatTripTime(instant), '23:30');
      expect([
        DateTime.utc(2024, 2, 29, 17, 30),
        DateTime.utc(2024, 2, 29, 18, 30),
      ], contains(instant));
    },
  );
  test('picker rejects invalid clock components and unrepresentable UTC', () {
    final date = DiaryDate(2026, 10, 1);
    expect(() => almatyWallTime(date, 24, 0), throwsFormatException);
    expect(() => almatyWallTime(date, -1, 0), throwsFormatException);
    expect(() => almatyWallTime(date, 12, 60), throwsFormatException);
    expect(
      () => almatyWallTime(DiaryDate(1, 1, 1), 0, 0),
      throwsFormatException,
    );
  });
}

TripInput _input({
  DateTime? start,
  DateTime? end,
  BigInt? amount,
  BigInt? commission,
}) => TripInput(
  start: start ?? DateTime.utc(2026, 10, 1, 3),
  end: end ?? DateTime.utc(2026, 10, 1, 3, 20),
  amount: amount ?? BigInt.from(1500),
  commission: commission ?? BigInt.from(225),
  payment: PaymentMethod.cash,
);
