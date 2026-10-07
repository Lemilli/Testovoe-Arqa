/// A calendar day, independent of the device's timezone and daylight saving.
class DiaryDate implements Comparable<DiaryDate> {
  factory DiaryDate(int year, int month, int day) {
    final value = DateTime.utc(year, month, day);
    if (year < 1 ||
        year > 9999 ||
        value.year != year ||
        value.month != month ||
        value.day != day) {
      throw const FormatException('Неверная календарная дата');
    }
    return DiaryDate._(value);
  }

  const DiaryDate._(this.toDateTime);

  factory DiaryDate.fromDateTime(DateTime value) =>
      DiaryDate(value.year, value.month, value.day);

  factory DiaryDate.parse(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw const FormatException('Дата должна быть в формате YYYY-MM-DD');
    }
    return DiaryDate(
      int.parse(value.substring(0, 4)),
      int.parse(value.substring(5, 7)),
      int.parse(value.substring(8, 10)),
    );
  }

  // The API needs representable UTC midnights on both sides of the day.
  static final first = DiaryDate(1, 1, 2);
  static final last = DiaryDate(9999, 12, 30);

  /// UTC is only a carrier for calendar components, not the day's API boundary.
  final DateTime toDateTime;
  int get year => toDateTime.year;
  int get month => toDateTime.month;
  int get day => toDateTime.day;
  String get iso8601 =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  DiaryDate get previous =>
      DiaryDate.fromDateTime(toDateTime.subtract(const Duration(days: 1)));
  DiaryDate get next =>
      DiaryDate.fromDateTime(toDateTime.add(const Duration(days: 1)));

  @override
  int compareTo(DiaryDate other) => toDateTime.compareTo(other.toDateTime);
  @override
  bool operator ==(Object other) =>
      other is DiaryDate && toDateTime == other.toDateTime;
  @override
  int get hashCode => toDateTime.hashCode;
  @override
  String toString() => iso8601;
}
