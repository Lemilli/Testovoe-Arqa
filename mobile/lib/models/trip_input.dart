import '../formatting/diary_format.dart';
import 'day.dart';
import 'diary_date.dart';

/// Validated form data before the submission assigns its stable trip ID.
class TripInput {
  factory TripInput({
    required DateTime start,
    required DateTime end,
    required BigInt amount,
    required BigInt commission,
    required PaymentMethod payment,
  }) {
    final utcStart = start.toUtc();
    final utcEnd = end.toUtc();
    if (utcStart.year < 1 ||
        utcStart.year > 9999 ||
        utcEnd.year < 1 ||
        utcEnd.year > 9999) {
      throw const FormatException(
        'Дата и время выходят за допустимый диапазон.',
      );
    }
    final day = almatyDay(utcStart);
    if (day.compareTo(DiaryDate.first) < 0 ||
        day.compareTo(DiaryDate.last) > 0) {
      throw const FormatException(
        'Дата начала выходит за допустимый диапазон.',
      );
    }
    if (!utcEnd.isAfter(utcStart)) {
      throw const FormatException('Окончание должно быть позже начала.');
    }
    if (amount < BigInt.one || amount > moneyMaximum) {
      throw const FormatException(
        'Сумма должна быть от 1 до 9223372036854775807 ₸.',
      );
    }
    if (commission < BigInt.zero || commission > moneyMaximum) {
      throw const FormatException(
        'Комиссия должна быть от 0 до 9223372036854775807 ₸.',
      );
    }
    return TripInput._(utcStart, utcEnd, amount, commission, payment);
  }

  const TripInput._(
    this.start,
    this.end,
    this.amount,
    this.commission,
    this.payment,
  );

  static final moneyMaximum = BigInt.parse('9223372036854775807');

  final DateTime start;
  final DateTime end;
  final BigInt amount;
  final BigInt commission;
  final PaymentMethod payment;

  static String? moneyError(String text, {required bool isCommission}) {
    final value = text.trim();
    if (!RegExp(r'^\d+$').hasMatch(value)) {
      return isCommission
          ? 'Введите комиссию целыми тенге, от 0.'
          : 'Введите сумму целыми тенге, больше 0.';
    }
    final money = BigInt.parse(value);
    if (money > moneyMaximum) return 'Максимум 9223372036854775807 ₸.';
    if (!isCommission && money == BigInt.zero) {
      return 'Сумма должна быть больше 0.';
    }
    return null;
  }

  static BigInt parseMoney(String text) {
    final value = text.trim();
    if (!RegExp(r'^\d+$').hasMatch(value)) {
      throw const FormatException('Введите целое число тенге.');
    }
    return BigInt.parse(value);
  }

  Trip withId(String id) => Trip(
    id: id,
    start: start,
    end: end,
    amount: amount,
    commission: commission,
    payment: payment,
  );
}
