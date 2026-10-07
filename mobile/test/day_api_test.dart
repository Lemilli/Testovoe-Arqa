import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:driver_shift_diary/api/day_api.dart';
import 'package:driver_shift_diary/api/dio_provider.dart';
import 'package:driver_shift_diary/models/day.dart';
import 'package:driver_shift_diary/models/diary_date.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final date = DiaryDate(2026, 10, 1);

  test(
    'GET uses selected date and reads the complete server response',
    () async {
      late RequestOptions request;
      final api = _api((options, _) async {
        request = options;
        return _response(_controlDay);
      });

      final day = await api.getDay(date);

      expect(request.method, 'GET');
      expect(request.path, '/api/v1/days/2026-10-01');
      expect(request.queryParameters, isEmpty);
      expect(request.responseType, ResponseType.plain);
      expect(day.date, date);
      expect(day.trips.map((trip) => trip.id), ['t2', 't1']);
      final trip = day.trips.first;
      expect(trip.start, DateTime.utc(2026, 10, 1, 4, 5));
      expect(trip.end, DateTime.utc(2026, 10, 1, 4, 20));
      expect(trip.start.isUtc, isTrue);
      expect(trip.amount, BigInt.from(1500));
      expect(trip.commission, BigInt.from(225));
      expect(trip.payment, PaymentMethod.cash);
      expect(day.trips.last.payment, PaymentMethod.card);
      expect(day.summary.tripCount, 2);
      expect(day.summary.revenue, BigInt.from(3900));
      expect(day.summary.commission, BigInt.from(585));
      expect(day.summary.netIncome, BigInt.from(3315));
      expect(day.summary.cash, BigInt.from(1500));
      expect(day.summary.card, BigInt.from(2400));
    },
  );

  test(
    'raw JSON preserves exact totals above the signed int64 maximum',
    () async {
      final api = _api((_, _) async => _response(_largeDay));

      final day = await api.getDay(date);

      expect(day.trips.first.amount, BigInt.parse('9223372036854775807'));
      expect(day.trips.first.commission, BigInt.parse('9223372036854775806'));
      expect(day.summary.revenue, BigInt.parse('18446744073709551614'));
      expect(day.summary.commission, BigInt.parse('18446744073709551612'));
      expect(day.summary.netIncome, BigInt.from(2));
      expect(day.summary.cash, BigInt.parse('9223372036854775807'));
      expect(day.summary.card, BigInt.parse('9223372036854775807'));
    },
  );

  test(
    'summary is the server result rather than a client calculation',
    () async {
      final api = _api(
        (_, _) async => _response(
          _controlDay.replaceFirst('"net_income":3315', '"net_income":-500'),
        ),
      );

      expect((await api.getDay(date)).summary.netIncome, BigInt.from(-500));
    },
  );

  test('empty day has an empty list and zero summary values', () async {
    final api = _api((_, _) async => _response(_emptyDay));

    final day = await api.getDay(date);

    expect(day.trips, isEmpty);
    expect(day.summary.tripCount, 0);
    expect(day.summary.revenue, BigInt.zero);
    expect(day.summary.commission, BigInt.zero);
    expect(day.summary.netIncome, BigInt.zero);
    expect(day.summary.cash, BigInt.zero);
    expect(day.summary.card, BigInt.zero);
  });

  test('provider uses the shared replaceable Dio client', () async {
    var called = false;
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
    addTearDown(dio.close);
    dio.httpClientAdapter = _Adapter((_, _) async {
      called = true;
      return _response(_emptyDay);
    });
    final container = ProviderContainer.test(
      overrides: [dioProvider.overrideWithValue(dio)],
    );

    await container.read(dayApiProvider).getDay(date);

    expect(called, isTrue);
  });

  for (final type in [
    DioExceptionType.connectionTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.receiveTimeout,
  ]) {
    test('$type has an understandable timeout message', () async {
      final api = _api((options, _) async {
        throw DioException(requestOptions: options, type: type);
      });

      await expectLater(
        api.getDay(date),
        throwsA(
          isA<DayApiException>().having(
            (error) => error.message,
            'message',
            contains('не ответил вовремя'),
          ),
        ),
      );
    });
  }

  for (final type in [
    DioExceptionType.connectionError,
    DioExceptionType.unknown,
    DioExceptionType.badCertificate,
  ]) {
    test('$type has an understandable connection message', () async {
      final api = _api((options, _) async {
        throw DioException(requestOptions: options, type: type);
      });

      await expectLater(
        api.getDay(date),
        throwsA(
          isA<DayApiException>().having(
            (error) => error.message,
            'message',
            contains('Проверьте соединение'),
          ),
        ),
      );
    });
  }

  for (final status in [201, 422, 500]) {
    test(
      'HTTP $status shows a server failure without reading its body',
      () async {
        final api = _api(
          (_, _) async => _response('Internal details are not UI text', status),
        );

        await expectLater(
          api.getDay(date),
          throwsA(
            isA<DayApiException>().having(
              (error) => error.message,
              'message',
              'Не удалось загрузить день. Попробуйте ещё раз.',
            ),
          ),
        );
      },
    );
  }

  test('an active cancelled request remains a Dio cancellation', () async {
    final started = Completer<void>();
    final body = Completer<ResponseBody>();
    final token = CancelToken();
    final api = _api((_, cancelFuture) {
      expect(cancelFuture, isNotNull);
      started.complete();
      return body.future;
    });
    final result = api.getDay(date, cancelToken: token);
    final expectation = expectLater(
      result,
      throwsA(
        isA<DioException>().having(CancelToken.isCancel, 'cancel', isTrue),
      ),
    );

    await started.future;
    token.cancel('Selected day changed');
    await expectation;
    body.complete(_response(_emptyDay));
  });

  final malformedResponses = <String, String>{
    'empty response': '',
    'HTML': '<html>Server unavailable</html>',
    'invalid JSON': '{"date":',
    'array instead of object': '[]',
    'null instead of object': 'null',
    'different day': _emptyDay.replaceFirst('2026-10-01', '2026-10-02'),
    'invalid calendar date': _emptyDay.replaceFirst('2026-10-01', '2026-02-30'),
    'missing summary': '{"date":"2026-10-01","trips":[]}',
    'wrong trips type': _emptyDay.replaceFirst('"trips":[]', '"trips":{}'),
    'string money': _controlDay.replaceFirst(
      '"amount":1500',
      '"amount":"1500"',
    ),
    'boolean money': _controlDay.replaceFirst('"amount":1500', '"amount":true'),
    'fractional money': _controlDay.replaceFirst(
      '"amount":1500',
      '"amount":1500.0',
    ),
    'exponent money': _controlDay.replaceFirst(
      '"amount":1500',
      '"amount":15e2',
    ),
    'null money': _controlDay.replaceFirst('"amount":1500', '"amount":null'),
    'nonpositive amount': _controlDay.replaceFirst(
      '"amount":1500',
      '"amount":0',
    ),
    'negative commission': _controlDay.replaceFirst(
      '"commission":225',
      '"commission":-1',
    ),
    'fractional summary': _emptyDay.replaceFirst(
      '"revenue":0',
      '"revenue":0.0',
    ),
    'negative revenue': _emptyDay.replaceFirst('"revenue":0', '"revenue":-1'),
    'boolean count': _emptyDay.replaceFirst(
      '"trip_count":0',
      '"trip_count":false',
    ),
    'negative count': _emptyDay.replaceFirst(
      '"trip_count":0',
      '"trip_count":-1',
    ),
    'out of range count': _emptyDay.replaceFirst(
      '"trip_count":0',
      '"trip_count":18446744073709551614',
    ),
    'unknown payment': _controlDay.replaceFirst(
      '"payment":"cash"',
      '"payment":"bank"',
    ),
    'missing offset': _controlDay.replaceFirst(
      '2026-10-01T09:05:00+05:00',
      '2026-10-01T09:05:00',
    ),
    'invalid calendar time': _controlDay.replaceFirst(
      '2026-10-01T09:05:00+05:00',
      '2026-02-30T09:05:00+05:00',
    ),
    'invalid hour': _controlDay.replaceFirst(
      '2026-10-01T09:05:00+05:00',
      '2026-10-01T24:05:00+05:00',
    ),
    'invalid offset': _controlDay.replaceFirst(
      '2026-10-01T09:05:00+05:00',
      '2026-10-01T09:05:00+05:99',
    ),
    'end before start': _controlDay.replaceFirst(
      '2026-10-01T09:20:00+05:00',
      '2026-10-01T09:04:00+05:00',
    ),
    'end equals start': _controlDay.replaceFirst(
      '2026-10-01T09:20:00+05:00',
      '2026-10-01T09:05:00+05:00',
    ),
    'empty ID': _controlDay.replaceFirst('"id":"t2"', '"id":""'),
  };
  for (final entry in malformedResponses.entries) {
    test('${entry.key} produces an invalid-response message', () async {
      final api = _api((_, _) async => _response(entry.value));

      await expectLater(
        api.getDay(date),
        throwsA(
          isA<DayApiException>().having(
            (error) => error.message,
            'message',
            'Сервер вернул некорректные данные. Попробуйте ещё раз.',
          ),
        ),
      );
    });
  }
}

DayApi _api(
  Future<ResponseBody> Function(RequestOptions, Future<void>?) handler,
) {
  final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
  addTearDown(dio.close);
  dio.httpClientAdapter = _Adapter(handler);
  return DayApi(dio);
}

ResponseBody _response(String body, [int status = 200]) =>
    ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions, Future<void>?) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options, cancelFuture);
}

const _controlDay = '''
{"date":"2026-10-01","trips":[
{"id":"t2","start":"2026-10-01T09:05:00+05:00","end":"2026-10-01T09:20:00+05:00","amount":1500,"payment":"cash","commission":225},
{"id":"t1","start":"2026-10-01T08:10:00+05:00","end":"2026-10-01T08:32:00+05:00","amount":2400,"payment":"card","commission":360}
],"summary":{"trip_count":2,"revenue":3900,"commission":585,"net_income":3315,"cash":1500,"card":2400}}
''';

const _emptyDay = '''
{"date":"2026-10-01","trips":[],"summary":{"trip_count":0,"revenue":0,"commission":0,"net_income":0,"cash":0,"card":0}}
''';

const _largeDay = '''
{"date":"2026-10-01","trips":[
{"id":"large-card","start":"2026-10-01T09:05:00+05:00","end":"2026-10-01T09:20:00+05:00","amount":9223372036854775807,"payment":"card","commission":9223372036854775806},
{"id":"large-cash","start":"2026-10-01T08:10:00+05:00","end":"2026-10-01T08:32:00+05:00","amount":9223372036854775807,"payment":"cash","commission":9223372036854775806}
],"summary":{"trip_count":2,"revenue":18446744073709551614,"commission":18446744073709551612,"net_income":2,"cash":9223372036854775807,"card":9223372036854775807}}
''';
