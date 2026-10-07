import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/diary_date.dart';

final _almaty = _loadAlmaty();

tz.Location _loadAlmaty() {
  tz_data.initializeTimeZones();
  return tz.getLocation('Asia/Almaty');
}

DateTime almatyTime(DateTime instant) => tz.TZDateTime.from(instant, _almaty);

DiaryDate almatyDay(DateTime instant) =>
    DiaryDate.fromDateTime(almatyTime(instant));

/// The picker components describe Almaty wall time, never the phone's timezone.
DateTime almatyWallTime(DiaryDate date, int hour, int minute) {
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    throw const FormatException('Неверное время.');
  }
  final local = tz.TZDateTime(
    _almaty,
    date.year,
    date.month,
    date.day,
    hour,
    minute,
  );
  // DST gaps in historical dates must not silently shift the user's time.
  // For a repeated historical time, timezone chooses a deterministic offset.
  if (local.year != date.year ||
      local.month != date.month ||
      local.day != date.day ||
      local.hour != hour ||
      local.minute != minute) {
    throw const FormatException(
      'Такого времени нет в часовом поясе Алматы. Выберите другое время.',
    );
  }
  final utc = local.toUtc();
  if (utc.year < 1 || utc.year > 9999) {
    throw const FormatException('Дата и время выходят за допустимый диапазон.');
  }
  return utc;
}

DateTime nextAlmatyMidnight(DateTime instant) {
  final local = almatyTime(instant);
  return tz.TZDateTime(_almaty, local.year, local.month, local.day + 1).toUtc();
}

/// String grouping preserves every tenge, including summaries beyond int64.
String formatMoney(BigInt amount) {
  final digits = amount.abs().toString();
  final grouped = digits.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ' ',
  );
  return '${amount.isNegative ? '−' : ''}$grouped ₸';
}

const _months = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

String formatDay(DiaryDate date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';

String formatTripTime(DateTime instant) {
  final time = almatyTime(instant);
  return '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

String formatTripRange(DateTime start, DateTime end) {
  final endDay = almatyDay(end);
  final suffix = almatyDay(start) == endDay ? '' : ' (${formatDay(endDay)})';
  return '${formatTripTime(start)} – ${formatTripTime(end)}$suffix';
}
