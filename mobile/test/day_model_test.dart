import 'package:driver_shift_diary/models/day.dart';
import 'package:driver_shift_diary/models/diary_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trip normalizes equivalent offsets and retains microseconds', () {
    final trip = Trip.fromJson({
      'id': 'overnight',
      'start': '2026-10-01T23:59:59.123456+05:00',
      'end': '2026-10-01T19:00:01.654321Z',
      'amount': 100,
      'commission': 0,
      'payment': 'cash',
    });

    expect(trip.start, DateTime.utc(2026, 10, 1, 18, 59, 59, 123, 456));
    expect(trip.end, DateTime.utc(2026, 10, 1, 19, 0, 1, 654, 321));
    expect(trip.commission, BigInt.zero);
  });

  test('negative net income remains an exact signed integer', () {
    final summary = DaySummary.fromJson({
      'trip_count': BigInt.from(1),
      'revenue': 1,
      'commission': BigInt.parse('18446744073709551615'),
      'net_income': BigInt.parse('-18446744073709551614'),
      'cash': 1,
      'card': 0,
    });

    expect(summary.tripCount, 1);
    expect(summary.netIncome, BigInt.parse('-18446744073709551614'));
  });

  test('UTC normalization accepts negative offsets across midnight', () {
    final trip = Trip.fromJson({
      'id': 'offset',
      'start': '2026-10-01T23:59:00-03:00',
      'end': '2026-10-02T03:00:00Z',
      'amount': 1,
      'commission': 0,
      'payment': 'card',
    });

    expect(trip.start, DateTime.utc(2026, 10, 2, 2, 59));
    expect(trip.end, DateTime.utc(2026, 10, 2, 3));
  });

  test('timestamps reject a UTC value outside the server calendar range', () {
    for (final start in [
      '0001-01-01T00:00:00+05:00',
      '9999-12-31T23:00:00-03:00',
    ]) {
      expect(
        () => Trip.fromJson({
          'id': 'range',
          'start': start,
          'end': '2026-10-01T10:00:00Z',
          'amount': 1,
          'commission': 0,
          'payment': 'cash',
        }),
        throwsFormatException,
      );
    }
  });

  test('day owns an immutable copy of the trips', () {
    final trips = <Trip>[];
    final day = DiaryDay(
      date: DiaryDate(2026, 10, 1),
      trips: trips,
      summary: DaySummary(
        tripCount: 0,
        revenue: BigInt.zero,
        commission: BigInt.zero,
        netIncome: BigInt.zero,
        cash: BigInt.zero,
        card: BigInt.zero,
      ),
    );
    trips.add(
      Trip(
        id: 'new',
        start: DateTime.utc(2026, 10, 1),
        end: DateTime.utc(2026, 10, 1, 1),
        amount: BigInt.one,
        commission: BigInt.zero,
        payment: PaymentMethod.card,
      ),
    );

    expect(day.trips, isEmpty);
    expect(() => day.trips.clear(), throwsUnsupportedError);
  });
}
