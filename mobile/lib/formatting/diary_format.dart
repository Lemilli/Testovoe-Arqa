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
