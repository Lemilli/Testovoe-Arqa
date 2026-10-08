import 'package:dio/dio.dart';
import 'package:driver_shift_diary/api/day_api.dart';
import 'package:driver_shift_diary/api/dio_provider.dart';
import 'package:driver_shift_diary/app.dart';
import 'package:driver_shift_diary/config.dart';
import 'package:driver_shift_diary/formatting/diary_format.dart';
import 'package:driver_shift_diary/models/diary_date.dart';
import 'package:driver_shift_diary/state/day_providers.dart';
import 'package:driver_shift_diary/state/trip_submission.dart';
import 'package:driver_shift_diary/widgets/day_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/fixtures/diary_test_helpers.dart';

/// Run against a migrated temporary API database, with TEST_DAY and its next
/// day empty. HTTP and server responses are real. Only one received POST success
/// is deliberately discarded to reproduce a lost response after server commit.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('add, lose response, reopen and retry without a duplicate', (
    tester,
  ) async {
    final date = DiaryDate.parse(
      const String.fromEnvironment('TEST_DAY', defaultValue: '2026-10-03'),
    );
    final dio = Dio(
      BaseOptions(
        baseUrl: apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Accept': 'application/json'},
      ),
    );
    addTearDown(() => dio.close(force: true));
    final bodies = <String>[];
    final statuses = <int?>[];
    var discardNextSuccess = false;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method == 'POST') bodies.add(options.data as String);
          handler.next(options);
        },
        onResponse: (response, handler) {
          if (response.requestOptions.method == 'POST') {
            statuses.add(response.statusCode);
            if (discardNextSuccess) {
              discardNextSuccess = false;
              handler.reject(
                DioException(
                  requestOptions: response.requestOptions,
                  type: DioExceptionType.receiveTimeout,
                  message: 'Simulated lost response after real server commit',
                ),
              );
              return;
            }
          }
          handler.next(response);
        },
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dio),
          clockProvider.overrideWithValue(
            () => DateTime.utc(date.year, date.month, date.day, 7),
          ),
        ],
        child: const DriverShiftDiaryApp(),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DayScreen)),
    );
    await expectSelectedDate(tester, formatDay(date));
    expect(findMoney('0 ₸'), findsNWidgets(5));

    await tester.tap(find.byKey(const Key('add-trip')));
    await tester.pumpAndSettle();
    await _enterMoney(tester, '2400', '360');
    await _choosePayment(tester, 'card');
    await _tapSave(tester);
    expect(find.text('Поездка добавлена'), findsOneWidget);
    expect(findMoney('2 040 ₸'), findsOneWidget);
    expect(findMoney('2 400 ₸'), findsWidgets);

    await tester.tap(find.byKey(const Key('add-trip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('end-date')));
    await tester.pumpAndSettle();
    final dialog = find.byType(DatePickerDialog);
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('${date.next.day}')),
    );
    await tester.tap(
      find.text(MaterialLocalizations.of(tester.element(dialog)).okButtonLabel),
    );
    await tester.pumpAndSettle();
    await _enterMoney(tester, '1500', '225');
    await _choosePayment(tester, 'cash');
    discardNextSuccess = true;
    await _tapSave(tester);
    final pending = container.read(tripSubmissionProvider).pending!;
    expect(container.read(tripSubmissionProvider).isUncertain, isTrue);
    expect(pending.amount, BigInt.from(1500));
    expect(almatyDay(pending.start), date);
    expect(almatyDay(pending.end), date.next);
    expect(bodies, hasLength(2));
    expect(statuses, [201, 201]);

    // Close the uncertain form, select another date, and reopen. The pending
    // request belongs to its original start date, independent of selection.
    await tester.tap(find.byKey(const Key('close-trip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('next-day')));
    await tester.pumpAndSettle();
    await expectSelectedDate(tester, formatDay(date.next));
    expect(findMoney('0 ₸'), findsNWidgets(5));
    await tester.tap(find.byKey(const Key('add-trip')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('trip-amount')))
          .enabled,
      isFalse,
    );
    await tester.ensureVisible(find.byKey(const Key('retry-trip')));
    await tester.tap(find.byKey(const Key('retry-trip')));
    await tester.pumpAndSettle();
    expect(statuses, [201, 201, 200]);
    expect(bodies[2], bodies[1]);
    expect(container.read(tripSubmissionProvider).pending, isNull);
    expect(container.read(selectedDayProvider), date.next);
    expect(findMoney('0 ₸'), findsNWidgets(5));

    await tester.tap(find.byKey(const Key('previous-day')));
    await tester.pumpAndSettle();
    expect(findMoney('3 900 ₸'), findsOneWidget);
    expect(findMoney('585 ₸'), findsOneWidget);
    expect(findMoney('3 315 ₸'), findsOneWidget);
    final day = await container.read(dayApiProvider).getDay(date);
    expect(day.summary.tripCount, 2);
    expect(day.summary.cash, BigInt.from(1500));
    expect(day.summary.card, BigInt.from(2400));
    expect(day.trips.where((trip) => trip.id == pending.id), hasLength(1));
    expect(day.trips.map((trip) => trip.id).toSet(), hasLength(2));
    expect(
      (await container.read(dayApiProvider).getDay(date.next)).trips,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _enterMoney(
  WidgetTester tester,
  String amount,
  String commission,
) async {
  await tester.ensureVisible(find.byKey(const Key('trip-amount')));
  await tester.enterText(find.byKey(const Key('trip-amount')), amount);
  await tester.ensureVisible(find.byKey(const Key('trip-commission')));
  await tester.enterText(find.byKey(const Key('trip-commission')), commission);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> _tapSave(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('save-trip')));
  await tester.tap(find.byKey(const Key('save-trip')));
  await tester.pumpAndSettle();
}

Future<void> _choosePayment(WidgetTester tester, String payment) async {
  await tester.ensureVisible(find.byKey(Key('payment-$payment')));
  await tester.tap(find.byKey(Key('payment-$payment')));
  await tester.pumpAndSettle();
}
