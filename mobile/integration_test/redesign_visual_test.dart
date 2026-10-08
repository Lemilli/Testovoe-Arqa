import 'dart:io';

import 'package:driver_shift_diary/app.dart';
import 'package:driver_shift_diary/models/diary_date.dart';
import 'package:driver_shift_diary/state/day_providers.dart';
import 'package:driver_shift_diary/widgets/day_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Run with test_driver/redesign_visual_driver.dart against a temporary API
/// database containing backend/data/trips.json and an empty 2 October 2026.
/// Only the clock and the QA text scale are controlled; HTTP/data are real.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture the redesign with real API data and native rendering', (
    tester,
  ) async {
    final platform = Platform.isAndroid ? 'android' : 'ios';
    final date = DiaryDate(2026, 10, 1);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 9, 7)),
        ],
        child: const DriverShiftDiaryApp(),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DayScreen)),
    );
    container.read(selectedDayProvider.notifier).select(date);
    await tester.pumpAndSettle();
    final day = await container.read(dayProvider(date).future);
    expect(day.summary.tripCount, 2);
    expect(day.summary.revenue, BigInt.from(3900));
    expect(day.summary.commission, BigInt.from(585));
    expect(day.summary.netIncome, BigInt.from(3315));
    expect(day.summary.cash, BigInt.from(1500));
    expect(day.summary.card, BigInt.from(2400));
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
    }

    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot(name);
    }

    Future<void> fillForm() async {
      await tester.ensureVisible(find.byKey(const Key('trip-amount')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('trip-amount')), '2400');
      await tester.ensureVisible(find.byKey(const Key('trip-commission')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('trip-commission')), '360');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('payment-card')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('payment-card')));
      await tester.pumpAndSettle();
      // Return to the dominant amount field without opening the keyboard.
      await tester.ensureVisible(find.byKey(const Key('trip-amount')));
      await tester.pumpAndSettle();
    }

    await capture('$platform-day');
    await tester.tap(find.byKey(const Key('calculation-toggle')));
    await capture('$platform-calculation');
    await tester.tap(find.byKey(const Key('calculation-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-trip')));
    await tester.pumpAndSettle();
    await fillForm();
    await capture('$platform-form');

    await tester.tap(find.byKey(const Key('trip-amount')));
    await capture('qa-$platform-keyboard');
    await tester.enterText(find.byKey(const Key('trip-amount')), '');
    await tester.tap(find.byKey(const Key('save-trip')));
    await capture('qa-$platform-validation');
    await tester.tap(find.byKey(const Key('close-trip')));
    await tester.pumpAndSettle();

    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(
      MediaQuery.textScalerOf(tester.element(find.byType(DayScreen))).scale(16),
      32,
    );
    await capture('qa-$platform-day-text200');
    await tester.tap(find.byKey(const Key('add-trip')));
    await tester.pumpAndSettle();
    await fillForm();
    await capture('qa-$platform-form-text200');
    await tester.tap(find.byKey(const Key('close-trip')));
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('next-day')));
    await tester.pumpAndSettle();
    expect(
      (await container.read(dayProvider(date.next).future)).trips,
      isEmpty,
    );
    await capture('qa-$platform-empty');
  });
}
