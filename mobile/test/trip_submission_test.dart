import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_shift_diary/api/day_api.dart';
import 'package:driver_shift_diary/api/trip_api.dart';
import 'package:driver_shift_diary/models/day.dart';
import 'package:driver_shift_diary/models/diary_date.dart';
import 'package:driver_shift_diary/models/trip_input.dart';
import 'package:driver_shift_diary/state/day_providers.dart';
import 'package:driver_shift_diary/state/trip_submission.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _PendingApi api;
  late ProviderContainer container;
  late int generated;

  setUp(() {
    api = _PendingApi();
    generated = 0;
    container = ProviderContainer.test(
      overrides: [
        tripApiProvider.overrideWithValue(api),
        uuidGeneratorProvider.overrideWithValue(() => 'uuid-${++generated}'),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 1, 5)),
      ],
    );
    addTearDown(api.dio.close);
  });

  test('secure generator makes UUID v4 values with RFC variant', () {
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    final ids = List.generate(20, (_) => generateTripId());
    expect(ids.every(pattern.hasMatch), isTrue);
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('one synchronous send guard blocks double taps and resets', () async {
    final notifier = container.read(tripSubmissionProvider.notifier);
    final first = notifier.submit(_input());
    final sending = container.read(tripSubmissionProvider);
    expect(sending.isSending, isTrue);
    expect(sending.pending!.id, 'uuid-1');
    expect(sending.error, isNull);
    expect(await notifier.submit(_input(amount: 5000)), isFalse);
    expect(await notifier.retry(), isFalse);
    expect(notifier.reset(), isFalse);
    expect(api.requests, hasLength(1));
    expect(generated, 1);
    api.requests.single.result.complete(api.requests.single.trip);
    expect(await first, isTrue);
    expect(container.read(tripSubmissionProvider).pending, isNull);
    expect(container.read(tripSubmissionProvider).isSending, isFalse);
  });

  test(
    'uncertain response keeps identical ID and payload for every retry',
    () async {
      final notifier = container.read(tripSubmissionProvider.notifier);
      final first = notifier.submit(_input());
      final trip = api.requests.single.trip;
      api.requests.single.result.completeError(
        const TripApiException('Нет подтверждения'),
      );
      expect(await first, isFalse);
      final uncertain = container.read(tripSubmissionProvider);
      expect(uncertain.pending, same(trip));
      expect(uncertain.isUncertain, isTrue);
      expect(uncertain.isSending, isFalse);
      expect(notifier.reset(), isFalse);
      expect(await notifier.submit(_input(amount: 5000)), isFalse);
      expect(api.requests, hasLength(1));

      final retry = notifier.retry();
      expect(api.requests.last.trip, same(trip));
      expect(container.read(tripSubmissionProvider).isSending, isTrue);
      api.requests.last.result.completeError(
        const TripApiException('Ещё нет подтверждения'),
      );
      expect(await retry, isFalse);
      final finalRetry = notifier.retry();
      expect(api.requests.last.trip, same(trip));
      api.requests.last.result.complete(trip);
      expect(await finalRetry, isTrue);
      expect(generated, 1);
      expect(container.read(tripSubmissionProvider).pending, isNull);
      expect(container.read(tripSubmissionProvider).error, isNull);
    },
  );

  test(
    'unknown client exceptions retain pending instead of permitting a new ID',
    () async {
      final notifier = container.read(tripSubmissionProvider.notifier);
      final request = notifier.submit(_input());
      api.requests.single.result.completeError(StateError('transport broke'));
      expect(await request, isFalse);
      expect(container.read(tripSubmissionProvider).isUncertain, isTrue);
      expect(container.read(tripSubmissionProvider).pending!.id, 'uuid-1');
      expect(notifier.reset(), isFalse);
    },
  );

  test(
    'validation rejection allows corrected fields with the same ID',
    () async {
      final notifier = container.read(tripSubmissionProvider.notifier);
      final request = notifier.submit(_input());
      api.requests.single.result.completeError(
        const TripApiException(
          'Проверьте данные',
          outcome: TripFailureOutcome.validation,
        ),
      );
      expect(await request, isFalse);
      expect(container.read(tripSubmissionProvider).isUncertain, isFalse);
      final corrected = notifier.submit(
        _input(amount: 2400, payment: PaymentMethod.card),
      );
      final trip = api.requests.last.trip;
      expect(trip.id, 'uuid-1');
      expect(trip.amount, BigInt.from(2400));
      expect(trip.payment, PaymentMethod.card);
      expect(generated, 1);
      api.requests.last.result.complete(trip);
      expect(await corrected, isTrue);
    },
  );

  test('conflict requires explicit reset before sending new data', () async {
    final notifier = container.read(tripSubmissionProvider.notifier);
    final request = notifier.submit(_input());
    api.requests.single.result.completeError(
      const TripApiException(
        'Поездка уже существует',
        outcome: TripFailureOutcome.conflict,
      ),
    );
    expect(await request, isFalse);
    expect(await notifier.submit(_input()), isFalse);
    expect(await notifier.retry(), isFalse);
    expect(generated, 1);
    expect(api.requests, hasLength(1));
    expect(notifier.reset(), isTrue);
    final newRequest = notifier.submit(_input());
    expect(api.requests.last.trip.id, 'uuid-2');
    api.requests.last.result.complete(api.requests.last.trip);
    expect(await newRequest, isTrue);
  });

  test('a completed trip and a following trip receive different IDs', () async {
    final notifier = container.read(tripSubmissionProvider.notifier);
    for (var index = 1; index <= 2; index++) {
      final request = notifier.submit(_input());
      expect(api.requests.last.trip.id, 'uuid-$index');
      api.requests.last.result.complete(api.requests.last.trip);
      expect(await request, isTrue);
    }
    expect(generated, 2);
  });

  test(
    'closing all form listeners preserves pending identity on reopen',
    () async {
      final subscription = container.listen(tripSubmissionProvider, (_, _) {});
      final notifier = container.read(tripSubmissionProvider.notifier);
      final request = notifier.submit(_input());
      subscription.close();
      await container.pump();
      api.requests.single.result.completeError(
        const TripApiException('Нет подтверждения'),
      );
      expect(await request, isFalse);
      await container.pump();
      final reopened = container.listen(tripSubmissionProvider, (_, _) {});
      expect(container.read(tripSubmissionProvider).pending!.id, 'uuid-1');
      expect(container.read(tripSubmissionProvider).isUncertain, isTrue);
      reopened.close();
      final retry = notifier.retry();
      expect(api.requests.last.trip, same(api.requests.first.trip));
      api.requests.last.result.complete(api.requests.last.trip);
      expect(await retry, isTrue);
    },
  );

  test(
    'success refreshes the start day and never changes the selected day',
    () async {
      final dayApi = _DayApi();
      addTearDown(dayApi.dio.close);
      container.dispose();
      container = ProviderContainer.test(
        overrides: [
          tripApiProvider.overrideWithValue(api),
          dayApiProvider.overrideWithValue(dayApi),
          uuidGeneratorProvider.overrideWithValue(() => 'uuid-${++generated}'),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 2, 5)),
        ],
      );
      final startDay = DiaryDate(2026, 10, 1);
      final selectedDay = DiaryDate(2026, 10, 2);
      container.listen(dayProvider(startDay), (_, _) {});
      container.listen(dayProvider(selectedDay), (_, _) {});
      await container.read(dayProvider(startDay).future);
      await container.read(dayProvider(selectedDay).future);
      expect(dayApi.requests, [startDay, selectedDay]);
      final request = container
          .read(tripSubmissionProvider.notifier)
          .submit(
            _input(
              start: DateTime.parse('2026-10-01T23:55:00+05:00'),
              end: DateTime.parse('2026-10-02T00:15:00+05:00'),
            ),
          );
      dayApi.revenue = 1500;
      api.requests.single.result.complete(api.requests.single.trip);
      expect(await request, isTrue);
      await container.pump();
      expect(dayApi.requests, [startDay, selectedDay, startDay]);
      expect(container.read(selectedDayProvider), selectedDay);
      expect(
        (await container.read(dayProvider(startDay).future)).summary.revenue,
        BigInt.from(1500),
      );
      expect(
        (await container.read(dayProvider(selectedDay).future)).summary.revenue,
        BigInt.zero,
      );
    },
  );

  test(
    'late success after scope disposal does not read or mutate disposed providers',
    () async {
      final request = container
          .read(tripSubmissionProvider.notifier)
          .submit(_input());
      container.dispose();
      api.requests.single.result.complete(api.requests.single.trip);
      expect(await request, isFalse);
    },
  );

  test(
    'late failure after scope disposal is handled without state mutation',
    () async {
      final request = container
          .read(tripSubmissionProvider.notifier)
          .submit(_input());
      container.dispose();
      api.requests.single.result.completeError(
        const TripApiException('Запоздалая ошибка'),
      );
      expect(await request, isFalse);
    },
  );
}

TripInput _input({
  int amount = 1500,
  PaymentMethod payment = PaymentMethod.cash,
  DateTime? start,
  DateTime? end,
}) => TripInput(
  start: start ?? DateTime.utc(2026, 10, 1, 3, 5),
  end: end ?? DateTime.utc(2026, 10, 1, 3, 20),
  amount: BigInt.from(amount),
  commission: BigInt.from(225),
  payment: payment,
);

class _Request {
  _Request(this.trip);
  final Trip trip;
  final result = Completer<Trip>();
}

class _PendingApi extends TripApi {
  _PendingApi() : this._(Dio());
  _PendingApi._(this.dio) : super(dio);
  final Dio dio;
  final requests = <_Request>[];

  @override
  Future<Trip> createTrip(Trip trip) {
    final request = _Request(trip);
    requests.add(request);
    return request.result.future;
  }
}

class _DayApi extends DayApi {
  _DayApi() : this._(Dio());
  _DayApi._(this.dio) : super(dio);
  final Dio dio;
  final requests = <DiaryDate>[];
  var revenue = 0;

  @override
  Future<DiaryDay> getDay(DiaryDate date, {CancelToken? cancelToken}) async {
    requests.add(date);
    return DiaryDay(
      date: date,
      trips: [],
      summary: DaySummary(
        tripCount: 0,
        revenue: BigInt.from(revenue),
        commission: BigInt.zero,
        netIncome: BigInt.from(revenue),
        cash: BigInt.from(revenue),
        card: BigInt.zero,
      ),
    );
  }
}
