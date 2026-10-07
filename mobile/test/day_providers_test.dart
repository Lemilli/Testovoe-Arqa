import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_shift_diary/api/day_api.dart';
import 'package:driver_shift_diary/models/day.dart';
import 'package:driver_shift_diary/models/diary_date.dart';
import 'package:driver_shift_diary/state/day_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _currentDay = Provider<AsyncValue<DiaryDay>>(
  (ref) => ref.watch(dayProvider(ref.watch(selectedDayProvider))),
);

void main() {
  late _PendingApi api;
  late ProviderContainer container;
  final date = DiaryDate(2026, 10, 1);

  setUp(() {
    api = _PendingApi();
    container = ProviderContainer.test(
      overrides: [
        dayApiProvider.overrideWithValue(api),
        clockProvider.overrideWithValue(
          () => DateTime.parse('2026-09-30T19:00Z'),
        ),
      ],
    );
    container.listen(_currentDay, (_, _) {});
    addTearDown(api.dio.close);
  });

  test('initial selection is today in Almaty and navigates calendar days', () {
    expect(container.read(selectedDayProvider), date);
    final selected = container.read(selectedDayProvider.notifier);
    selected.previous();
    expect(container.read(selectedDayProvider), DiaryDate(2026, 9, 30));
    selected.next();
    expect(container.read(selectedDayProvider), date);
    selected.select(DiaryDate(2024, 2, 29));
    selected.next();
    expect(container.read(selectedDayProvider), DiaryDate(2024, 3, 1));
  });

  test('selection and navigation stay in the API date range', () {
    final selected = container.read(selectedDayProvider.notifier);
    selected.select(DiaryDate.first);
    selected.previous();
    expect(container.read(selectedDayProvider), DiaryDate.first);
    selected.select(DiaryDate.last);
    selected.next();
    expect(container.read(selectedDayProvider), DiaryDate.last);
    selected.select(DiaryDate(9999, 12, 31));
    expect(container.read(selectedDayProvider), DiaryDate.last);
  });

  test('load displays the server summary without recalculating it', () async {
    expect(container.read(_currentDay).isLoading, isTrue);
    final result = _day(date, revenue: 3900);
    api.requests.single.result.complete(result);
    expect(await container.read(dayProvider(date).future), same(result));
    expect(
      container.read(_currentDay).requireValue.summary.revenue,
      BigInt.from(3900),
    );
  });

  test(
    'error remains visible without automatic retry and refresh recovers',
    () async {
      final future = container.read(dayProvider(date).future);
      final assertion = expectLater(future, throwsA(isA<DayApiException>()));
      api.requests.single.result.completeError(
        const DayApiException('Нет соединения'),
      );
      await assertion;
      expect(container.read(_currentDay).hasError, isTrue);
      await container.pump();
      expect(api.requests, hasLength(1));
      final retry = container.refresh(dayProvider(date).future);
      expect(container.read(_currentDay).isLoading, isTrue);
      expect(api.requests.first.token!.isCancelled, isTrue);
      api.requests.last.result.complete(_day(date));
      await retry;
      expect(container.read(_currentDay).requireValue.trips, isEmpty);
    },
  );

  test(
    'late success for another date cannot replace the current day',
    () async {
      final oldRequest = api.requests.single;
      container.read(selectedDayProvider.notifier).next();
      expect(container.read(_currentDay).isLoading, isTrue);
      final currentRequest = api.requests.last;
      expect(currentRequest.date, date.next);
      await container.pump();
      expect(oldRequest.token!.isCancelled, isTrue);
      currentRequest.result.complete(_day(date.next, revenue: 1500));
      await container.read(dayProvider(date.next).future);
      oldRequest.result.complete(_day(date, revenue: 3900));
      await container.pump();
      expect(container.read(_currentDay).requireValue.date, date.next);
      expect(
        container.read(_currentDay).requireValue.summary.revenue,
        BigInt.from(1500),
      );
    },
  );

  test('late error for another date cannot replace the current day', () async {
    final abandonedRequest = api.requests.single;
    container.read(selectedDayProvider.notifier).next();
    container.read(_currentDay);
    await container.pump();
    api.requests.last.result.complete(_day(date.next));
    await container.read(dayProvider(date.next).future);
    abandonedRequest.result.completeError(
      const DayApiException('Запоздалая ошибка'),
    );
    await container.pump();
    expect(container.read(_currentDay).hasError, isFalse);
    expect(container.read(_currentDay).requireValue.date, date.next);
  });

  test('A-B-A and same-date refresh ignore superseded requests', () async {
    final first = api.requests.single;
    final selected = container.read(selectedDayProvider.notifier);
    selected.next();
    container.read(_currentDay);
    await container.pump();
    final second = api.requests.last;
    selected.previous();
    container.read(_currentDay);
    await container.pump();
    final third = api.requests.last;
    expect(third, isNot(same(first)));
    third.result.complete(_day(date, revenue: 3900));
    await container.read(dayProvider(date).future);
    first.result.complete(_day(date, revenue: 1));
    second.result.complete(_day(date.next, revenue: 2));
    await container.pump();
    expect(
      container.read(_currentDay).requireValue.summary.revenue,
      BigInt.from(3900),
    );

    final refresh = container.refresh(dayProvider(date).future);
    final fourth = api.requests.last;
    final newerRefresh = container.refresh(dayProvider(date).future);
    final fifth = api.requests.last;
    fifth.result.complete(_day(date, revenue: 4000));
    await newerRefresh;
    fourth.result.complete(_day(date, revenue: 100));
    await refresh;
    await container.pump();
    expect(
      container.read(_currentDay).requireValue.summary.revenue,
      BigInt.from(4000),
    );
  });

  test('disposing the scope cancels its request', () {
    final request = api.requests.single;
    container.dispose();
    expect(request.token!.isCancelled, isTrue);
    request.result.complete(_day(date));
  });
}

DiaryDay _day(DiaryDate date, {int revenue = 0}) => DiaryDay(
  date: date,
  trips: [],
  summary: DaySummary(
    tripCount: 0,
    revenue: BigInt.from(revenue),
    commission: BigInt.zero,
    netIncome: BigInt.from(revenue),
    cash: BigInt.zero,
    card: BigInt.from(revenue),
  ),
);

class _Request {
  _Request(this.date, this.token);
  final DiaryDate date;
  final CancelToken? token;
  final result = Completer<DiaryDay>();
}

class _PendingApi extends DayApi {
  _PendingApi() : this._(Dio());
  _PendingApi._(this.dio) : super(dio);
  final Dio dio;
  final requests = <_Request>[];

  @override
  Future<DiaryDay> getDay(DiaryDate date, {CancelToken? cancelToken}) {
    final request = _Request(date, cancelToken);
    requests.add(request);
    // Intentionally ignore cancellation to prove obsolete responses stay isolated.
    return request.result.future;
  }
}
