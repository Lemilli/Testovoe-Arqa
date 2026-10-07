import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:driver_shift_diary/api/dio_provider.dart';
import 'package:driver_shift_diary/api/trip_api.dart';
import 'package:driver_shift_diary/models/day.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final status in [201, 200]) {
    test(
      'POST handles HTTP $status and sends exact integer JSON with UTC',
      () async {
        late RequestOptions request;
        final trip = _trip(amount: BigInt.parse('9223372036854775807'));
        final api = _api((options) async {
          request = options;
          return _response(
            _json.replaceFirst('"amount":1500', '"amount":9223372036854775807'),
            status,
          );
        });
        final saved = await api.createTrip(trip);
        expect(request.method, 'POST');
        expect(request.path, '/api/v1/trips');
        expect(request.responseType, ResponseType.plain);
        expect(request.contentType, Headers.jsonContentType);
        expect(request.data, contains('"amount":9223372036854775807'));
        expect(request.data, contains('"start":"2026-10-01T03:05:00.123456Z"'));
        expect(request.data, contains('"commission":225'));
        expect(request.data, contains('"payment":"cash"'));
        expect(request.data, contains('"id":"trip-id"'));
        expect(saved.id, trip.id);
        expect(saved.start, trip.start);
        expect(saved.amount, trip.amount);
      },
    );
  }
  test(
    'response may normalize timestamps with a different UTC offset',
    () async {
      final api = _api(
        (_) async => _response(
          _json.replaceFirst(
            '2026-10-01T08:05:00.123456+05:00',
            '2026-10-01T03:05:00.123456Z',
          ),
        ),
      );
      expect((await api.createTrip(_trip())).start, _trip().start);
    },
  );
  test('provider uses the replaceable shared Dio client', () async {
    var called = false;
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
    addTearDown(dio.close);
    dio.httpClientAdapter = _Adapter((_) async {
      called = true;
      return _response(_json);
    });
    final container = ProviderContainer.test(
      overrides: [dioProvider.overrideWithValue(dio)],
    );
    await container.read(tripApiProvider).createTrip(_trip());
    expect(called, isTrue);
  });

  for (final (status, outcome) in [
    (422, TripFailureOutcome.validation),
    (409, TripFailureOutcome.conflict),
    (500, TripFailureOutcome.uncertain),
    (503, TripFailureOutcome.uncertain),
    (204, TripFailureOutcome.uncertain),
    (400, TripFailureOutcome.uncertain),
  ]) {
    test(
      'HTTP $status is classified as $outcome with safe user text',
      () async {
        final api = _api(
          (_) async => _response('internal SQL diagnostics', status),
        );
        await expectLater(
          api.createTrip(_trip()),
          throwsA(
            isA<TripApiException>()
                .having((error) => error.outcome, 'outcome', outcome)
                .having(
                  (error) => error.message,
                  'message',
                  isNot(contains('SQL')),
                ),
          ),
        );
      },
    );
  }
  for (final type in [
    DioExceptionType.connectionTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.receiveTimeout,
    DioExceptionType.connectionError,
    DioExceptionType.badCertificate,
    DioExceptionType.cancel,
    DioExceptionType.unknown,
  ]) {
    test('$type retains an uncertain submission outcome', () async {
      final api = _api((options) async {
        throw DioException(requestOptions: options, type: type);
      });
      await expectLater(api.createTrip(_trip()), throwsA(_uncertain));
    });
  }

  final malformed = <String, String>{
    'empty response': '',
    'invalid JSON': '{"id":',
    'non-object': '[]',
    'wrong id': _json.replaceFirst('trip-id', 'other-id'),
    'wrong start': _json.replaceFirst('08:05:00.123456', '08:05:00.123457'),
    'wrong end': _json.replaceFirst('08:20:00', '08:21:00'),
    'wrong amount': _json.replaceFirst('"amount":1500', '"amount":1501'),
    'fractional money': _json.replaceFirst('"amount":1500', '"amount":1500.0'),
    'string money': _json.replaceFirst('"amount":1500', '"amount":"1500"'),
    'wrong commission': _json.replaceFirst(
      '"commission":225',
      '"commission":226',
    ),
    'wrong payment': _json.replaceFirst('"payment":"cash"', '"payment":"card"'),
    'missing time offset': _json.replaceFirst('08:20:00+05:00', '08:20:00'),
  };
  for (final entry in malformed.entries) {
    test('${entry.key} cannot confirm saving and remains uncertain', () async {
      final api = _api((_) async => _response(entry.value));
      await expectLater(api.createTrip(_trip()), throwsA(_uncertain));
    });
  }
}

final _uncertain = isA<TripApiException>().having(
  (error) => error.outcome,
  'outcome',
  TripFailureOutcome.uncertain,
);

Trip _trip({BigInt? amount}) => Trip(
  id: 'trip-id',
  start: DateTime.parse('2026-10-01T08:05:00.123456+05:00'),
  end: DateTime.parse('2026-10-01T08:20:00+05:00'),
  amount: amount ?? BigInt.from(1500),
  commission: BigInt.from(225),
  payment: PaymentMethod.cash,
);

TripApi _api(Future<ResponseBody> Function(RequestOptions) handler) {
  final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
  addTearDown(dio.close);
  dio.httpClientAdapter = _Adapter(handler);
  return TripApi(dio);
}

ResponseBody _response(String body, [int status = 201]) =>
    ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);
}

const _json = '''
{"id":"trip-id","start":"2026-10-01T08:05:00.123456+05:00","end":"2026-10-01T08:20:00+05:00","amount":1500,"payment":"cash","commission":225}
''';
