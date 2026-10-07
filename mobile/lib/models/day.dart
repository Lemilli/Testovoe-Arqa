import 'diary_date.dart';

enum PaymentMethod { cash, card }

class DiaryDay {
  DiaryDay({
    required this.date,
    required List<Trip> trips,
    required this.summary,
  }) : trips = List.unmodifiable(trips);

  factory DiaryDay.fromJson(Object? value) {
    final json = _object(value);
    final trips = json['trips'];
    if (trips is! List) {
      throw const FormatException('Expected a list of trips.');
    }
    return DiaryDay(
      date: DiaryDate.parse(_string(json['date'])),
      trips: trips.map(Trip.fromJson).toList(),
      summary: DaySummary.fromJson(json['summary']),
    );
  }

  final DiaryDate date;
  final List<Trip> trips;
  final DaySummary summary;
}

class Trip {
  Trip({
    required this.id,
    required DateTime start,
    required DateTime end,
    required this.amount,
    required this.commission,
    required this.payment,
  }) : start = start.toUtc(),
       end = end.toUtc();

  factory Trip.fromJson(Object? value) {
    final json = _object(value);
    final id = _string(json['id']);
    if (id.isEmpty) {
      throw const FormatException('Expected a nonempty trip ID.');
    }
    final start = _timestamp(json['start']);
    final end = _timestamp(json['end']);
    if (!end.isAfter(start)) {
      throw const FormatException('Trip end must be after its start.');
    }
    return Trip(
      id: id,
      start: start,
      end: end,
      amount: _integer(json['amount'], minimum: BigInt.one),
      commission: _integer(json['commission'], minimum: BigInt.zero),
      payment: switch (json['payment']) {
        'cash' => PaymentMethod.cash,
        'card' => PaymentMethod.card,
        _ => throw const FormatException('Unknown payment method.'),
      },
    );
  }

  final String id;
  final DateTime start;
  final DateTime end;
  final BigInt amount;
  final BigInt commission;
  final PaymentMethod payment;
}

class DaySummary {
  const DaySummary({
    required this.tripCount,
    required this.revenue,
    required this.commission,
    required this.netIncome,
    required this.cash,
    required this.card,
  });

  factory DaySummary.fromJson(Object? value) {
    final json = _object(value);
    final tripCount = _integer(json['trip_count'], minimum: BigInt.zero);
    if (!tripCount.isValidInt) {
      throw const FormatException('Trip count is out of range.');
    }
    return DaySummary(
      tripCount: tripCount.toInt(),
      revenue: _integer(json['revenue'], minimum: BigInt.zero),
      commission: _integer(json['commission'], minimum: BigInt.zero),
      netIncome: _integer(json['net_income']),
      cash: _integer(json['cash'], minimum: BigInt.zero),
      card: _integer(json['card'], minimum: BigInt.zero),
    );
  }

  final int tripCount;
  final BigInt revenue;
  final BigInt commission;
  final BigInt netIncome;
  final BigInt cash;
  final BigInt card;
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

String _string(Object? value) {
  if (value is! String) {
    throw const FormatException('Expected a string.');
  }
  return value;
}

BigInt _integer(Object? value, {BigInt? minimum}) {
  final integer = switch (value) {
    BigInt() => value,
    int() => BigInt.from(value),
    _ => throw const FormatException('Expected an integer.'),
  };
  if (minimum != null && integer < minimum) {
    throw const FormatException('Integer is below its minimum.');
  }
  return integer;
}

final _timestampPattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})[Tt](\d{2}):(\d{2}):(\d{2})'
  r'(?:[.,](\d{1,6}))?([Zz]|[+-]\d{2}:\d{2})$',
);

DateTime _timestamp(Object? value) {
  final text = _string(value);
  final match = _timestampPattern.firstMatch(text);
  if (match == null) {
    throw const FormatException('Expected ISO 8601 time with a UTC offset.');
  }
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final hour = int.parse(match[4]!);
  final minute = int.parse(match[5]!);
  final second = int.parse(match[6]!);
  final local = DateTime.utc(year, month, day, hour, minute, second);
  if (year < 1 ||
      local.year != year ||
      local.month != month ||
      local.day != day ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    throw const FormatException('Invalid calendar time.');
  }
  final offset = match[8]!;
  if (offset.length > 1 &&
      (int.parse(offset.substring(1, 3)) > 23 ||
          int.parse(offset.substring(4, 6)) > 59)) {
    throw const FormatException('Invalid UTC offset.');
  }
  final timestamp = DateTime.parse(text).toUtc();
  if (timestamp.year < 1 || timestamp.year > 9999) {
    throw const FormatException('UTC time is out of range.');
  }
  return timestamp;
}
