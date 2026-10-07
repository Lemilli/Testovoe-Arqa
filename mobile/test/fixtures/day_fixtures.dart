import 'package:driver_shift_diary/models/day.dart';
import 'package:driver_shift_diary/models/diary_date.dart';

final sampleDate = DiaryDate(2026, 10, 1);

DiaryDay emptyDay(DiaryDate date) => DiaryDay(
  date: date,
  trips: [],
  summary: DaySummary(
    tripCount: 0,
    revenue: BigInt.zero,
    commission: BigInt.zero,
    netIncome: BigInt.zero,
    cash: BigInt.zero,
    card: BigInt.zero,
  ),
);

DiaryDay sampleDay({DiaryDate? date}) {
  final day = date ?? sampleDate;
  return DiaryDay(
    date: day,
    trips: [
      Trip(
        id: 't2',
        start: DateTime.parse('${day.iso8601}T09:05:00+05:00'),
        end: DateTime.parse('${day.iso8601}T09:20:00+05:00'),
        amount: BigInt.from(1500),
        commission: BigInt.from(225),
        payment: PaymentMethod.cash,
      ),
      Trip(
        id: 't1',
        start: DateTime.parse('${day.iso8601}T08:10:00+05:00'),
        end: DateTime.parse('${day.iso8601}T08:32:00+05:00'),
        amount: BigInt.from(2400),
        commission: BigInt.from(360),
        payment: PaymentMethod.card,
      ),
    ],
    summary: DaySummary(
      tripCount: 2,
      revenue: BigInt.from(3900),
      commission: BigInt.from(585),
      netIncome: BigInt.from(3315),
      cash: BigInt.from(1500),
      card: BigInt.from(2400),
    ),
  );
}
