import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:json_bigint/json_bigint.dart';

import '../models/day.dart';
import 'dio_provider.dart';

final tripApiProvider = Provider<TripApi>(
  (ref) => TripApi(ref.watch(dioProvider)),
);

class TripApi {
  TripApi(this._dio);

  final Dio _dio;

  Future<Trip> createTrip(Trip trip) async {
    late final Response<String> response;
    try {
      response = await _dio.post<String>(
        '/api/v1/trips',
        // Encoding the raw body preserves integer JSON tokens above 2**53.
        data: encodeJson({
          'id': trip.id,
          'start': trip.start.toIso8601String(),
          'end': trip.end.toIso8601String(),
          'amount': trip.amount,
          'payment': trip.payment.name,
          'commission': trip.commission,
        }),
        options: Options(
          contentType: Headers.jsonContentType,
          responseType: ResponseType.plain,
          validateStatus: (status) => status == 200 || status == 201,
        ),
      );
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 422) {
        throw const TripApiException(
          'Сервер отклонил данные поездки. Проверьте поля и отправьте снова.',
          outcome: TripFailureOutcome.validation,
        );
      }
      if (status == 409) {
        throw const TripApiException(
          'Поездка уже существует с другими данными. '
          'Вернитесь к форме, чтобы сохранить новую поездку.',
          outcome: TripFailureOutcome.conflict,
        );
      }
      throw TripApiException(switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          'Сервер не ответил вовремя. Результат отправки неизвестен. '
              'Повторите отправку этой поездки.',
        DioExceptionType.badResponse =>
          'Сервер не подтвердил сохранение. Результат отправки неизвестен. '
              'Повторите отправку этой поездки.',
        _ =>
          'Не удалось подтвердить сохранение. Проверьте соединение '
              'и повторите отправку этой поездки.',
      });
    } catch (_) {
      throw const TripApiException(
        'Не удалось подтвердить сохранение. Повторите отправку этой поездки.',
      );
    }
    try {
      final body = response.data;
      if (body == null) throw const FormatException('Empty response.');
      final saved = Trip.fromJson(
        decodeJson(body, settings: const DecoderSettings()),
      );
      if (saved.id != trip.id ||
          saved.start != trip.start ||
          saved.end != trip.end ||
          saved.amount != trip.amount ||
          saved.commission != trip.commission ||
          saved.payment != trip.payment) {
        throw const FormatException('Response does not match the sent trip.');
      }
      return saved;
    } catch (_) {
      throw const TripApiException(
        'Сервер вернул некорректное подтверждение. '
        'Повторите отправку этой поездки.',
      );
    }
  }
}

enum TripFailureOutcome { uncertain, validation, conflict }

class TripApiException implements Exception {
  const TripApiException(
    this.message, {
    this.outcome = TripFailureOutcome.uncertain,
  });

  final String message;
  final TripFailureOutcome outcome;

  @override
  String toString() => message;
}
