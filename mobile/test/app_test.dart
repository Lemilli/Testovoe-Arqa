import 'package:driver_shift_diary/app.dart';
import 'package:driver_shift_diary/state/day_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/day_fixtures.dart';

void main() {
  testWidgets('midnight updates Today without changing the selected day', (
    tester,
  ) async {
    var now = DateTime.parse('2026-10-01T18:59:59Z');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          dayProvider.overrideWith((ref, date) async => emptyDay(date)),
        ],
        child: const DriverShiftDiaryApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 октября 2026'), findsOneWidget);
    expect(find.text('Сегодня'), findsNothing);
    now = DateTime.parse('2026-10-01T19:00:00Z');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('1 октября 2026'), findsOneWidget);
    expect(find.text('Сегодня'), findsOneWidget);
    await tester.tap(find.byKey(const Key('today')));
    await tester.pumpAndSettle();
    expect(find.text('2 октября 2026'), findsOneWidget);
    expect(find.text('Сегодня'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resuming after midnight updates the calendar Today', (
    tester,
  ) async {
    var now = DateTime.parse('2026-10-01T10:00:00Z');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          dayProvider.overrideWith((ref, date) async => emptyDay(date)),
        ],
        child: const DriverShiftDiaryApp(),
      ),
    );
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = DateTime.parse('2026-10-02T10:00:00Z');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('1 октября 2026'), findsOneWidget);
    expect(find.text('Сегодня'), findsOneWidget);
    await tester.tap(find.byKey(const Key('choose-day')));
    await tester.pumpAndSettle();
    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(picker.currentDate.year, 2026);
    expect(picker.currentDate.month, 10);
    expect(picker.currentDate.day, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('app shows the Russian Material 3 diary', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayProvider.overrideWithValue(sampleDate),
          dayProvider.overrideWith((ref, date) async => emptyDay(date)),
        ],
        child: const DriverShiftDiaryApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Дневник смен'), findsOneWidget);
    expect(find.text('1 октября 2026'), findsOneWidget);
    expect(find.text('На руки'), findsOneWidget);
    expect(find.text('Hello World!'), findsNothing);

    final context = tester.element(find.byType(Scaffold));
    expect(Localizations.localeOf(context), const Locale('ru'));
    expect(MaterialLocalizations.of(context).backButtonTooltip, 'Назад');
    expect(Theme.of(context).useMaterial3, isTrue);
    expect(tester.takeException(), isNull);
  });
}
