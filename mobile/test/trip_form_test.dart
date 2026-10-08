import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_shift_diary/api/trip_api.dart';
import 'package:driver_shift_diary/app.dart';
import 'package:driver_shift_diary/models/day.dart';
import 'package:driver_shift_diary/models/diary_date.dart';
import 'package:driver_shift_diary/state/day_providers.dart';
import 'package:driver_shift_diary/state/trip_submission.dart';
import 'package:driver_shift_diary/widgets/day_screen.dart';
import 'package:driver_shift_diary/widgets/trip_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/day_fixtures.dart';
import 'fixtures/diary_test_helpers.dart';

class FormTripApi extends TripApi {
  FormTripApi(this.respond) : super(Dio());

  final Future<Trip> Function(Trip trip, int requestNumber) respond;
  final requests = <Trip>[];

  @override
  Future<Trip> createTrip(Trip trip) {
    requests.add(trip);
    return respond(trip, requests.length);
  }
}

Future<void> pumpForm(
  WidgetTester tester,
  FormTripApi api, {
  Future<DiaryDay> Function(DiaryDate)? loadDay,
  double textScale = 1,
}) async {
  var nextId = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        todayProvider.overrideWithValue(sampleDate),
        dayProvider.overrideWith(
          (ref, date) => loadDay?.call(date) ?? Future.value(emptyDay(date)),
        ),
        tripApiProvider.overrideWithValue(api),
        uuidGeneratorProvider.overrideWithValue(() => 'form-id-${++nextId}'),
      ],
      child: MediaQuery.fromView(
        view: tester.view,
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: const DriverShiftDiaryApp(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('add-trip')));
  await tester.pumpAndSettle();
}

Future<void> enterMoney(
  WidgetTester tester, {
  String amount = '2400',
  String commission = '360',
}) async {
  final amountField = find.byKey(const Key('trip-amount'));
  await tester.ensureVisible(amountField);
  await tester.enterText(amountField, amount);
  final commissionField = find.byKey(const Key('trip-commission'));
  await tester.ensureVisible(commissionField);
  await tester.enterText(commissionField, commission);
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
}

Future<void> pickTime(
  WidgetTester tester,
  String key,
  String hour,
  String minute,
) async {
  await tapKey(tester, key);
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pumpAndSettle();
  final dialog = find.byType(TimePickerDialog);
  final fields = find.descendant(of: dialog, matching: find.byType(TextField));
  await tester.enterText(fields.at(0), hour);
  await tester.enterText(fields.at(1), minute);
  await tester.pumpAndSettle();
  final ok = find.text(
    MaterialLocalizations.of(tester.element(dialog)).okButtonLabel,
  );
  await tester.ensureVisible(ok);
  await tester.pumpAndSettle();
  await tester.tap(ok);
  await tester.pumpAndSettle();
  expect(find.byType(TimePickerDialog), findsNothing);
}

Future<void> pickDate(WidgetTester tester, String key, String day) async {
  await tapKey(tester, key);
  await tester.pumpAndSettle();
  final dialog = find.byType(DatePickerDialog);
  await tester.tap(find.descendant(of: dialog, matching: find.text(day)));
  await tester.tap(
    find.text(MaterialLocalizations.of(tester.element(dialog)).okButtonLabel),
  );
  await tester.pumpAndSettle();
}

void expectFieldsLocked(WidgetTester tester, bool locked) {
  for (final key in ['trip-amount', 'trip-commission']) {
    expect(tester.widget<TextFormField>(find.byKey(Key(key))).enabled, !locked);
  }
  for (final key in ['start-date', 'start-time', 'end-date', 'end-time']) {
    expect(
      tester.widget<OutlinedButton>(find.byKey(Key(key))).onPressed,
      locked ? isNull : isNotNull,
    );
  }
  for (final payment in ['cash', 'card']) {
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(Key('payment-$payment')))
          .onPressed,
      locked ? isNull : isNotNull,
    );
  }
}

void main() {
  testWidgets('entry point opens Russian form with selected day and defaults', (
    tester,
  ) async {
    final api = FormTripApi((trip, _) async => trip);
    await pumpForm(tester, api);

    expect(find.byType(TripForm), findsOneWidget);
    expect(find.text('Время Алматы'), findsOneWidget);
    expect(find.text('Новая поездка'), findsOneWidget);
    expect(find.text('Сохранить поездку'), findsOneWidget);
    await expectDateControl(tester, 'start-date', '1 октября 2026');
    await expectDateControl(tester, 'end-date', '1 октября 2026');
    expect(find.text('09:00'), findsOneWidget);
    expect(find.text('09:30'), findsOneWidget);
    expectFieldsLocked(tester, false);
    expect(api.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final value in ['', '0', '-1', '1.5', '1e3', '9223372036854775808']) {
    testWidgets('invalid amount "$value" prevents sending', (tester) async {
      final api = FormTripApi((trip, _) async => trip);
      await pumpForm(tester, api);
      await enterMoney(tester, amount: value);
      await tapKey(tester, 'save-trip');
      await tester.pumpAndSettle();

      expect(api.requests, isEmpty);
      expect(
        tester
            .state<FormFieldState<String>>(find.byKey(const Key('trip-amount')))
            .hasError,
        isTrue,
      );
      expect(find.byType(TripForm), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final value in ['', '-1', '1.5', '1e3', '9223372036854775808']) {
    testWidgets('invalid commission "$value" prevents sending', (tester) async {
      final api = FormTripApi((trip, _) async => trip);
      await pumpForm(tester, api);
      await enterMoney(tester, commission: value);
      await tapKey(tester, 'save-trip');
      await tester.pumpAndSettle();

      expect(api.requests, isEmpty);
      expect(
        tester
            .state<FormFieldState<String>>(
              find.byKey(const Key('trip-commission')),
            )
            .hasError,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final time in [('09', '00'), ('08', '30')]) {
    testWidgets('end ${time.$1}:${time.$2} cannot precede or equal start', (
      tester,
    ) async {
      final api = FormTripApi((trip, _) async => trip);
      await pumpForm(tester, api);
      await pickTime(tester, 'end-time', time.$1, time.$2);
      await enterMoney(tester);
      await tapKey(tester, 'save-trip');
      await tester.pumpAndSettle();

      expect(find.text('Окончание должно быть позже начала.'), findsOneWidget);
      expect(api.requests, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'card payment saves exact integers and refreshes server summary',
    (tester) async {
      var dayRequests = 0;
      final api = FormTripApi((trip, _) async => trip);
      await pumpForm(
        tester,
        api,
        loadDay: (date) async {
          dayRequests++;
          return api.requests.isEmpty ? emptyDay(date) : sampleDay(date: date);
        },
      );
      await enterMoney(tester, amount: '9007199254740993', commission: '0');
      await tapKey(tester, 'payment-card');
      await tester.pumpAndSettle();
      await tapKey(tester, 'save-trip');
      await tester.pumpAndSettle();

      final sent = api.requests.single;
      expect(sent.id, 'form-id-1');
      expect(sent.start, DateTime.utc(2026, 10, 1, 4));
      expect(sent.end, DateTime.utc(2026, 10, 1, 4, 30));
      expect(sent.amount, BigInt.parse('9007199254740993'));
      expect(sent.commission, BigInt.zero);
      expect(sent.payment, PaymentMethod.card);
      expect(find.byType(TripForm), findsNothing);
      expect(find.text('Поездка добавлена'), findsOneWidget);
      expect(findMoney('3 315 ₸'), findsOneWidget);
      expect(dayRequests, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('independent end date allows a trip crossing midnight', (
    tester,
  ) async {
    final api = FormTripApi((trip, _) async => trip);
    await pumpForm(tester, api);
    await pickTime(tester, 'start-time', '23', '50');
    await pickDate(tester, 'end-date', '2');
    await pickTime(tester, 'end-time', '00', '10');
    await enterMoney(tester, amount: '1500', commission: '225');
    await tapKey(tester, 'save-trip');
    await tester.pumpAndSettle();

    final sent = api.requests.single;
    expect(sent.start, DateTime.utc(2026, 10, 1, 18, 50));
    expect(sent.end, DateTime.utc(2026, 10, 1, 19, 10));
    expect(sent.payment, PaymentMethod.cash);
    expect(find.byType(TripForm), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changed start day is refreshed without changing selected day', (
    tester,
  ) async {
    final loaded = <DiaryDate>[];
    final api = FormTripApi((trip, _) async => trip);
    await pumpForm(
      tester,
      api,
      loadDay: (date) async {
        loaded.add(date);
        return emptyDay(date);
      },
    );
    await pickDate(tester, 'start-date', '2');
    await pickDate(tester, 'end-date', '2');
    await enterMoney(tester);
    await tapKey(tester, 'save-trip');
    await tester.pumpAndSettle();

    expect(find.text('Поездка добавлена: 2 октября 2026'), findsOneWidget);
    await expectSelectedDate(tester, '1 октября 2026');
    expect(loaded, [sampleDate]);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DayScreen)),
    );
    expect(container.read(selectedDayProvider), sampleDate);
    await tester.tap(find.byKey(const Key('next-day')));
    await tester.pumpAndSettle();
    expect(loaded.last, sampleDate.next);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sending disables double tap, all edits and navigation', (
    tester,
  ) async {
    final pending = Completer<Trip>();
    final api = FormTripApi((_, _) => pending.future);
    await pumpForm(tester, api);
    await enterMoney(tester);
    await tester.ensureVisible(find.byKey(const Key('save-trip')));
    await tester.tap(find.byKey(const Key('save-trip')));
    await tester.tap(find.byKey(const Key('save-trip')));
    await tester.pump();

    expect(api.requests, hasLength(1));
    expect(find.text('Отправляем поездку'), findsOneWidget);
    expect(find.text('Отправляем…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expectFieldsLocked(tester, true);
    expect(
      tester.widget<IconButton>(find.byKey(const Key('close-trip'))).onPressed,
      isNull,
    );
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('save-trip'))).onPressed,
      isNull,
    );
    await Navigator.of(tester.element(find.byType(TripForm))).maybePop();
    await tester.pump();
    expect(find.byType(TripForm), findsOneWidget);

    pending.complete(api.requests.single);
    await tester.pumpAndSettle();
    expect(find.byType(TripForm), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('network failure locks exact retry and restores it on reopen', (
    tester,
  ) async {
    final api = FormTripApi((trip, number) async {
      if (number == 1) {
        throw const TripApiException('Нет подтверждения сервера.');
      }
      return trip;
    });
    await pumpForm(tester, api);
    await enterMoney(tester, amount: '1500', commission: '225');
    await tapKey(tester, 'save-trip');
    await tester.pumpAndSettle();

    expect(find.text('Нет подтверждения сервера.'), findsOneWidget);
    expect(find.byKey(const Key('trip-retry-note')), findsOneWidget);
    expect(find.text('Повторить отправку'), findsOneWidget);
    expectFieldsLocked(tester, true);
    await tester.tap(find.byKey(const Key('close-trip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('next-day')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-trip')));
    await tester.pumpAndSettle();

    await expectDateControl(tester, 'start-date', '1 октября 2026');
    await expectDateControl(tester, 'end-date', '1 октября 2026');
    expect(find.text('Нет подтверждения сервера.'), findsOneWidget);
    expectFieldsLocked(tester, true);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('trip-amount')))
          .controller!
          .text,
      '1500',
    );
    await tapKey(tester, 'retry-trip');
    await tester.pumpAndSettle();

    expect(api.requests, hasLength(2));
    expect(identical(api.requests[0], api.requests[1]), isTrue);
    expect(find.byType(TripForm), findsNothing);
    await expectSelectedDate(tester, '2 октября 2026');
    expect(find.text('Поездка добавлена: 1 октября 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server validation keeps form editable and retains rejected ID', (
    tester,
  ) async {
    final api = FormTripApi((trip, number) async {
      if (number == 1) {
        throw const TripApiException(
          'Проверьте сумму поездки.',
          outcome: TripFailureOutcome.validation,
        );
      }
      return trip;
    });
    await pumpForm(tester, api);
    await enterMoney(tester);
    await tapKey(tester, 'save-trip');
    await tester.pumpAndSettle();

    expect(find.text('Проверьте сумму поездки.'), findsOneWidget);
    expect(find.byKey(const Key('trip-retry-note')), findsNothing);
    expectFieldsLocked(tester, false);
    await enterMoney(tester, amount: '1500', commission: '225');
    await tapKey(tester, 'save-trip');
    await tester.pumpAndSettle();

    expect(api.requests, hasLength(2));
    expect(api.requests[1].id, api.requests[0].id);
    expect(api.requests[1].amount, BigInt.from(1500));
    expect(find.byType(TripForm), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('conflict requires returning to form before using a new ID', (
    tester,
  ) async {
    final api = FormTripApi((trip, number) async {
      if (number == 1) {
        throw const TripApiException(
          'Поездка уже существует с другими данными.',
          outcome: TripFailureOutcome.conflict,
        );
      }
      return trip;
    });
    await pumpForm(tester, api);
    await enterMoney(tester);
    await tapKey(tester, 'save-trip');
    await tester.pumpAndSettle();

    expect(
      find.text('Поездка уже существует с другими данными.'),
      findsOneWidget,
    );
    expectFieldsLocked(tester, true);
    expect(find.byKey(const Key('save-trip')), findsNothing);
    await tapKey(tester, 'reset-trip');
    await tester.pumpAndSettle();
    expectFieldsLocked(tester, false);
    await tapKey(tester, 'save-trip');
    await tester.pumpAndSettle();

    expect(api.requests, hasLength(2));
    expect(api.requests[0].id, 'form-id-1');
    expect(api.requests[1].id, 'form-id-2');
    expect(find.byType(TripForm), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px large text and keyboard keep all fields and save usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FormTripApi((trip, _) async => trip);
    await pumpForm(tester, api, textScale: 2);
    expect(tester.takeException(), isNull);

    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await enterMoney(tester);
    expect(tester.takeException(), isNull);
    await tapKey(tester, 'save-trip');
    await tester.pumpAndSettle();

    expect(api.requests, hasLength(1));
    expect(find.byType(TripForm), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final invalidField in ['trip-amount', 'trip-commission']) {
    testWidgets(
      'first invalid $invalidField is focused and scrolled into view',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = FormTripApi((trip, _) async => trip);
        await pumpForm(tester, api, textScale: 2);
        await enterMoney(
          tester,
          amount: invalidField == 'trip-amount' ? '' : '2400',
          commission: '-1',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.ensureVisible(find.byKey(const Key('end-time')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('save-trip')));
        await tester.pumpAndSettle();

        final field = find.byKey(Key(invalidField));
        expect(
          tester
              .widget<EditableText>(
                find.descendant(of: field, matching: find.byType(EditableText)),
              )
              .focusNode
              .hasFocus,
          isTrue,
        );
        expect(tester.state<FormFieldState<String>>(field).hasError, isTrue);
        final rect = tester.getRect(field);
        final action = tester.getRect(find.byKey(const Key('save-trip')));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.center.dy, lessThan(action.top));
        expect(api.requests, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('invalid time focuses the end control and reveals its error', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FormTripApi((trip, _) async => trip);
    await pumpForm(tester, api);
    await pickTime(tester, 'end-time', '09', '00');
    await enterMoney(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-trip')));
    await tester.pumpAndSettle();

    final end = find.byKey(const Key('end-time'));
    expect(tester.widget<OutlinedButton>(end).focusNode!.hasFocus, isTrue);
    expect(end.hitTestable(), findsOneWidget);
    expect(
      find.text('Окончание должно быть позже начала.').hitTestable(),
      findsOneWidget,
    );
    expect(api.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 640),
    const Size(360, 800),
    const Size(390, 844),
    const Size(430, 932),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('form supports $size, text scale $scale, and keyboard', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.view.padding = const FakeViewPadding(bottom: 24);
        addTearDown(tester.view.resetPadding);
        final api = FormTripApi((trip, _) async => trip);
        await pumpForm(tester, api, textScale: scale);
        expectMinimumTapTarget(tester, find.byKey(const Key('close-trip')));
        for (final key in [
          'payment-cash',
          'payment-card',
          'start-date',
          'start-time',
          'end-date',
          'end-time',
        ]) {
          final control = find.byKey(Key(key));
          await tester.ensureVisible(control);
          expectMinimumTapTarget(tester, control);
        }
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await enterMoney(
          tester,
          amount: '9223372036854775807',
          commission: '0',
        );
        final save = find.byKey(const Key('save-trip'));
        expectMinimumTapTarget(tester, save);
        final action = tester.getRect(save);
        expect(action.bottom, lessThanOrEqualTo(size.height - 280));
        expect(action.left, greaterThanOrEqualTo(0));
        expect(action.right, lessThanOrEqualTo(size.width));
        await tapKey(tester, 'save-trip');
        await tester.pumpAndSettle();
        expect(api.requests, hasLength(1));
        expect(api.requests.single.amount, BigInt.parse('9223372036854775807'));
        expect(find.byType(TripForm), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
