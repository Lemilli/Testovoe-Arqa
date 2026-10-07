import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:json_bigint/json_bigint.dart';

import '../models/day.dart';
import '../models/diary_date.dart';
import 'dio_provider.dart';

final dayApiProvider = Provider<DayApi>(
  (ref) => DayApi(ref.watch(dioProvider)),
);

class DayApi {
  DayApi(this._dio);

  final Dio _dio;

  Future<DiaryDay> getDay(DiaryDate date, {CancelToken? cancelToken}) async {
    late final Response<String> response;
    try {
      response = await _dio.get<String>(
        '/api/v1/days/${date.iso8601}',
        cancelToken: cancelToken,
        // Dio's default decoder converts integers outside int64 to double.
        // Decode the raw JSON ourselves so every tenge remains exact.
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (status) => status == 200,
        ),
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      throw DayApiException(switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          'Сервер не ответил вовремя. Попробуйте ещё раз.',
        DioExceptionType.badResponse =>
          'Не удалось загрузить день. Попробуйте ещё раз.',
        _ =>
          'Не удалось подключиться к серверу. '
              'Проверьте соединение и повторите попытку.',
      });
    }
    try {
      final body = response.data;
      if (body == null) throw const FormatException('Empty response.');
      final day = DiaryDay.fromJson(
        decodeJson(body, settings: const DecoderSettings()),
      );
      if (day.date != date) {
        throw const FormatException('The response belongs to another day.');
      }
      return day;
    } catch (_) {
      throw const DayApiException(
        'Сервер вернул некорректные данные. Попробуйте ещё раз.',
      );
    }
  }
}

class DayApiException implements Exception {
  const DayApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
