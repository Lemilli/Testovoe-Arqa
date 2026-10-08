import 'dart:async';

import 'package:driver_shift_diary/api/day_api.dart';
import 'package:driver_shift_diary/app.dart';
import 'package:driver_shift_diary/formatting/diary_format.dart';
import 'package:driver_shift_diary/models/day.dart';
import 'package:driver_shift_diary/models/diary_date.dart';
import 'package:driver_shift_diary/state/day_providers.dart';
import 'package:driver_shift_diary/widgets/day_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/day_fixtures.dart';
import 'fixtures/diary_test_helpers.dart';

Future<void> pumpDiary(
  WidgetTester tester,
  Future<DiaryDay> Function(DiaryDate) load, {
  DiaryDate? today,
  double textScale = 1,
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        todayProvider.overrideWithValue(today ?? sampleDate),
        dayProvider.overrideWith((ref, date) => load(date)),
      ],
      child: MediaQuery.fromView(
        view: tester.view,
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: disableAnimations,
            ),
            child: const DriverShiftDiaryApp(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(DayScreen)));

Future<void> showTrip(WidgetTester tester, String id) async {
  await scrollDayUntilVisible(tester, find.byKey(ValueKey('trip-$id')));
}

void main() {
  testWidgets('loading is visible and refresh is disabled', (tester) async {
    final pending = Completer<DiaryDay>();
    await pumpDiary(tester, (_) => pending.future);

    expect(find.text('Загружаем день…'), findsOneWidget);
    expect(find.byType(ShaderMask), findsOneWidget);
    expect(find.text('На руки'), findsNothing);
    final refresh = tester.widget<IconButton>(
      find.byKey(const Key('refresh-day')),
    );
    expect(refresh.onPressed, isNull);

    pending.complete(emptyDay(sampleDate));
    await tester.pumpAndSettle();
    expect(find.text('Загружаем день…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion disables the loading shimmer', (tester) async {
    final pending = Completer<DiaryDay>();
    await pumpDiary(tester, (_) => pending.future, disableAnimations: true);
    await tester.pumpAndSettle();
    expect(find.text('Загружаем день…'), findsOneWidget);
    expect(find.byType(ShaderMask), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    pending.complete(emptyDay(sampleDate));
    await tester.pumpAndSettle();
    expect(find.byType(ShaderMask), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sample summary and trips display server values and order', (
    tester,
  ) async {
    await pumpDiary(tester, (_) async => sampleDay());
    await tester.pumpAndSettle();

    expect(find.text('На руки'), findsOneWidget);
    expect(findMoney('3 315 ₸'), findsOneWidget);
    expect(find.text('Поездки'), findsOneWidget);
    expect(find.text('02'), findsOneWidget);
    expect(find.text('Выручка'), findsOneWidget);
    expect(findMoney('3 900 ₸'), findsOneWidget);
    expect(find.text('Комиссия'), findsOneWidget);
    expect(findMoney('585 ₸'), findsOneWidget);
    expect(findMoney('1 500 ₸'), findsWidgets);
    expect(findMoney('2 400 ₸'), findsWidgets);

    await showTrip(tester, 't1');
    expect(find.text('09:05–09:20'), findsOneWidget);
    expect(find.text('08:10–08:32'), findsOneWidget);
    expect(find.text('Комиссия 225 ₸'), findsOneWidget);
    expect(find.text('Комиссия 360 ₸'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('trip-t2'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('trip-t1'))).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty day has all zero metrics and an empty message', (
    tester,
  ) async {
    await pumpDiary(tester, (_) async => emptyDay(sampleDate));
    await tester.pumpAndSettle();

    expect(find.text('00'), findsOneWidget);
    expect(findMoney('0 ₸'), findsNWidgets(5));
    await tester.scrollUntilVisible(
      find.text('Поездок пока нет'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Добавьте первую поездку за этот день.'), findsOneWidget);
    expect(find.byKey(const ValueKey('trip-t1')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('API error offers a retry that loads the same day', (
    tester,
  ) async {
    final requested = <DiaryDate>[];
    await pumpDiary(tester, (date) async {
      requested.add(date);
      if (requested.length == 1) {
        throw const DayApiException(
          'Проверьте соединение и повторите попытку.',
        );
      }
      return sampleDay(date: date);
    });
    await tester.pumpAndSettle();

    expect(
      find.text('Проверьте соединение и повторите попытку.'),
      findsOneWidget,
    );
    expect(find.text('На руки'), findsNothing);
    await tester.tap(find.byKey(const Key('retry-day')));
    await tester.pumpAndSettle();

    expect(requested, [sampleDate, sampleDate]);
    expect(findMoney('3 315 ₸'), findsOneWidget);
    expect(find.text('Повторить'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh clears old values and then displays the new response', (
    tester,
  ) async {
    var requests = 0;
    final refreshed = Completer<DiaryDay>();
    await pumpDiary(tester, (date) {
      requests++;
      return requests == 1
          ? Future.value(sampleDay(date: date))
          : refreshed.future;
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refresh-day')));
    await tester.pump();

    expect(find.text('Загружаем день…'), findsOneWidget);
    expect(findMoney('3 315 ₸'), findsNothing);
    refreshed.complete(emptyDay(sampleDate));
    await tester.pumpAndSettle();

    expect(requests, 2);
    expect(findMoney('0 ₸'), findsNWidgets(5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh error removes stale data and offers retry', (
    tester,
  ) async {
    var requests = 0;
    await pumpDiary(tester, (date) async {
      requests++;
      if (requests == 2) throw const DayApiException('Сервер недоступен.');
      return sampleDay(date: date);
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refresh-day')));
    await tester.pumpAndSettle();

    expect(find.text('Сервер недоступен.'), findsOneWidget);
    expect(findMoney('3 315 ₸'), findsNothing);
    await tester.tap(find.byKey(const Key('retry-day')));
    await tester.pumpAndSettle();
    expect(requests, 3);
    expect(findMoney('3 315 ₸'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final withError in [false, true]) {
    testWidgets(
      'pull to refresh works for ${withError ? 'an error' : 'an empty day'}',
      (tester) async {
        var requests = 0;
        final refreshed = Completer<DiaryDay>();
        await pumpDiary(tester, (date) async {
          requests++;
          if (requests > 1) return refreshed.future;
          if (withError) throw const DayApiException('Сервер недоступен.');
          return emptyDay(date);
        });
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const Key('day-scroll')),
          const Offset(0, 320),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        expect(requests, 2);
        refreshed.complete(sampleDay());
        await tester.pumpAndSettle();
        expect(findMoney('3 315 ₸'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('arrows switch calendar days and Today returns to today', (
    tester,
  ) async {
    final requests = <DiaryDate>[];
    await pumpDiary(tester, (date) async {
      requests.add(date);
      return emptyDay(date);
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('previous-day')));
    await tester.pumpAndSettle();
    await expectSelectedDate(tester, '30 сентября 2026');
    expect(find.text('Сегодня'), findsOneWidget);

    await tester.tap(find.byKey(const Key('next-day')));
    await tester.pumpAndSettle();
    await expectSelectedDate(tester, '1 октября 2026');
    await tester.tap(find.byKey(const Key('next-day')));
    await tester.pumpAndSettle();
    await expectSelectedDate(tester, '2 октября 2026');
    await tester.tap(find.byKey(const Key('today')));
    await tester.pumpAndSettle();

    await expectSelectedDate(tester, '1 октября 2026');
    expect(find.text('Сегодня'), findsNothing);
    expect(
      requests,
      containsAll([sampleDate.previous, sampleDate, sampleDate.next]),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('date picker loads the selected date', (tester) async {
    final requests = <DiaryDate>[];
    await pumpDiary(tester, (date) async {
      requests.add(date);
      return emptyDay(date);
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choose-day')));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
    final dialog = find.byType(DatePickerDialog);
    await tester.tap(find.descendant(of: dialog, matching: find.text('2')));
    final context = tester.element(dialog);
    await tester.tap(
      find.text(MaterialLocalizations.of(context).okButtonLabel),
    );
    await tester.pumpAndSettle();

    await expectSelectedDate(tester, '2 октября 2026');
    expect(requests.last, DiaryDate(2026, 10, 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'late response of the previous date cannot replace current data',
    (tester) async {
      final first = Completer<DiaryDay>();
      final second = Completer<DiaryDay>();
      await pumpDiary(
        tester,
        (date) => date == sampleDate ? first.future : second.future,
      );
      await tester.tap(find.byKey(const Key('next-day')));
      await tester.pump();
      await expectSelectedDate(tester, '2 октября 2026');
      expect(find.text('Загружаем день…'), findsOneWidget);

      second.complete(emptyDay(sampleDate.next));
      await tester.pumpAndSettle();
      first.complete(sampleDay());
      await tester.pumpAndSettle();

      await expectSelectedDate(tester, '2 октября 2026');
      expect(findMoney('0 ₸'), findsNWidgets(5));
      expect(findMoney('3 315 ₸'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'switching from loaded date shows loading instead of stale summary',
    (tester) async {
      final pending = Completer<DiaryDay>();
      await pumpDiary(
        tester,
        (date) =>
            date == sampleDate ? Future.value(sampleDay()) : pending.future,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('next-day')));
      await tester.pump();
      await expectSelectedDate(tester, '2 октября 2026');
      expect(find.text('Загружаем день…'), findsOneWidget);
      expect(findMoney('3 315 ₸'), findsNothing);

      pending.complete(emptyDay(sampleDate.next));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('arrows disable at the API calendar boundaries', (tester) async {
    await pumpDiary(tester, (date) async => emptyDay(date));
    await tester.pumpAndSettle();
    final container = containerOf(tester);
    container.read(selectedDayProvider.notifier).select(DiaryDate.first);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('previous-day')))
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<IconButton>(find.byKey(const Key('next-day'))).onPressed,
      isNotNull,
    );
    container.read(selectedDayProvider.notifier).select(DiaryDate.last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<IconButton>(find.byKey(const Key('next-day'))).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('trip crossing midnight names its end date in Almaty', (
    tester,
  ) async {
    final day = sampleDay();
    final trip = Trip(
      id: 'overnight',
      start: DateTime.parse('2026-10-01T23:50:00+05:00'),
      end: DateTime.parse('2026-10-02T00:10:00+05:00'),
      amount: BigInt.from(2400),
      commission: BigInt.from(360),
      payment: PaymentMethod.card,
    );
    await pumpDiary(
      tester,
      (_) async =>
          DiaryDay(date: day.date, trips: [trip], summary: day.summary),
    );
    await tester.pumpAndSettle();
    await showTrip(tester, 'overnight');
    expect(find.text('23:50–00:10'), findsOneWidget);
    expect(find.text('Конец: 2 октября 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow screen and large text keep summary and trips usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpDiary(tester, (_) async => sampleDay(), textScale: 2);
    await tester.pumpAndSettle();
    expect(
      MediaQuery.textScalerOf(tester.element(find.byType(Scaffold))).scale(14),
      28,
    );
    await expectSelectedDate(tester, '1 октября 2026');
    expect(tester.takeException(), isNull);
    await showTrip(tester, 't1');
    expect(find.text('Комиссия 360 ₸'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('calculation closes after refreshing or selecting another day', (
    tester,
  ) async {
    await pumpDiary(tester, (date) async => sampleDay(date: date));
    await tester.pumpAndSettle();
    for (final action in ['refresh-day', 'next-day']) {
      final toggle = find.byKey(const Key('calculation-toggle'));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('calculation-fold'))).height,
        greaterThan(0),
      );
      await tester.tap(find.byKey(Key(action)));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('calculation-fold'))).height,
        0,
      );
    }
    await expectSelectedDate(tester, '2 октября 2026');
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging the calculation seam does not refresh the day', (
    tester,
  ) async {
    var requests = 0;
    await pumpDiary(tester, (date) async {
      requests++;
      return sampleDay(date: date);
    });
    await tester.pumpAndSettle();
    final toggle = find.byKey(const Key('calculation-toggle'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(toggle));
    await gesture.moveBy(const Offset(0, 90));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('calculation-fold'))).height,
      greaterThan(0),
    );
    expect(requests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'settlement and unfolded equation use the supplied server summary',
    (tester) async {
      final day = sampleDay();
      final summary = DaySummary(
        tripCount: 17,
        revenue: BigInt.from(500),
        commission: BigInt.from(700),
        netIncome: BigInt.from(-200),
        cash: BigInt.from(123),
        card: BigInt.from(377),
      );
      await pumpDiary(
        tester,
        (_) async =>
            DiaryDay(date: day.date, trips: day.trips, summary: summary),
      );
      await tester.pumpAndSettle();
      expect(findMoney('−200 ₸'), findsOneWidget);
      expect(findMoney('500 ₸'), findsOneWidget);
      expect(findMoney('700 ₸'), findsOneWidget);
      expect(findMoney('123 ₸'), findsOneWidget);
      expect(findMoney('377 ₸'), findsOneWidget);
      expect(find.text('17'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('calculation-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('calculation-toggle')));
      await tester.pumpAndSettle();
      final equation = find.byKey(const Key('calculation-equation'));
      for (final amount in ['500 ₸', '700 ₸', '−200 ₸']) {
        expect(
          find.descendant(of: equation, matching: findMoney(amount)),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(320, 640),
    const Size(360, 800),
    const Size(390, 844),
    const Size(430, 932),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('day remains usable at $size with text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pumpDiary(tester, (_) async => sampleDay(), textScale: scale);
        await tester.pumpAndSettle();
        await expectSelectedDate(tester, '1 октября 2026');
        for (final key in [
          'choose-day',
          'previous-day',
          'next-day',
          'refresh-day',
          'add-trip',
        ]) {
          expectMinimumTapTarget(tester, find.byKey(Key(key)));
        }
        final add = tester.getRect(find.byKey(const Key('add-trip')));
        expect(add.bottom, lessThanOrEqualTo(size.height));
        expect(add.left, greaterThanOrEqualTo(0));
        expect(add.right, lessThanOrEqualTo(size.width));
        final toggle = find.byKey(const Key('calculation-toggle'));
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(const Key('calculation-fold'))).height,
          greaterThan(0),
        );
        await showTrip(tester, 't1');
        expect(find.text('Комиссия 360 ₸'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final negative in [false, true]) {
    testWidgets(
      'very long signed money remains exact and readable: $negative',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final value = BigInt.parse('123456789012345678901234567890');
        final summary = DaySummary(
          tripCount: 1,
          revenue: value,
          commission: negative ? value * BigInt.two : BigInt.zero,
          netIncome: negative ? -value : value,
          cash: BigInt.zero,
          card: value,
        );
        final sampleTrip = sampleDay().trips.last;
        final trip = Trip(
          id: sampleTrip.id,
          start: sampleTrip.start,
          end: sampleTrip.end,
          amount: BigInt.parse('9223372036854775807'),
          commission: BigInt.parse('9223372036854775806'),
          payment: sampleTrip.payment,
        );
        await pumpDiary(
          tester,
          (_) async =>
              DiaryDay(date: sampleDate, trips: [trip], summary: summary),
          textScale: 2,
        );
        await tester.pumpAndSettle();
        expect(findMoney(formatMoney(summary.netIncome)), findsWidgets);
        expect(findMoney(formatMoney(summary.commission)), findsWidgets);
        final toggle = find.byKey(const Key('calculation-toggle'));
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        final equation = find.byKey(const Key('calculation-equation'));
        expect(
          find.descendant(
            of: equation,
            matching: findMoney(formatMoney(summary.netIncome)),
          ),
          findsWidgets,
        );
        await showTrip(tester, trip.id);
        expect(findMoney(formatMoney(trip.amount)), findsOneWidget);
        expect(
          find.text('Комиссия ${formatMoney(trip.commission)}'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
