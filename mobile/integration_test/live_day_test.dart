import 'package:driver_shift_diary/app.dart';
import 'package:driver_shift_diary/state/day_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Run against a migrated temporary API database with backend/data/trips.json.
/// Only the initial clock is fixed; HTTP, models, state and widgets are real.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('browse the real sample day, change date and refresh', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 2, 7)),
        ],
        child: const DriverShiftDiaryApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 октября 2026'), findsOneWidget);
    expect(find.text('0 ₸'), findsNWidgets(5));
    await tester.scrollUntilVisible(
      find.text('Поездок пока нет'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('За выбранный день нет поездок.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('previous-day')));
    await tester.pumpAndSettle();
    expect(find.text('1 октября 2026'), findsOneWidget);
    expect(find.text('3 900 ₸'), findsOneWidget);
    expect(find.text('585 ₸'), findsOneWidget);
    expect(find.text('3 315 ₸'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('trip-t1')),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('09:05 – 09:20'), findsOneWidget);
    expect(find.text('08:10 – 08:32'), findsOneWidget);
    expect(find.text('Комиссия: 225 ₸'), findsOneWidget);
    expect(find.text('Комиссия: 360 ₸'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('trip-t2'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('trip-t1'))).dy),
    );

    await tester.tap(find.byKey(const Key('choose-day')));
    await tester.pumpAndSettle();
    final dialog = find.byType(DatePickerDialog);
    await tester.tap(find.descendant(of: dialog, matching: find.text('2')));
    await tester.tap(
      find.text(MaterialLocalizations.of(tester.element(dialog)).okButtonLabel),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 октября 2026'), findsOneWidget);
    expect(find.text('0 ₸'), findsNWidgets(5));
    expect(find.text('3 315 ₸'), findsNothing);

    await tester.tap(find.byKey(const Key('next-day')));
    await tester.pumpAndSettle();
    expect(find.text('3 октября 2026'), findsOneWidget);
    await tester.tap(find.byKey(const Key('today')));
    await tester.pumpAndSettle();
    expect(find.text('2 октября 2026'), findsOneWidget);

    await tester.tap(find.byKey(const Key('previous-day')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refresh-day')));
    await tester.pumpAndSettle();
    expect(find.text('3 315 ₸'), findsOneWidget);
    expect(find.text('3 900 ₸'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
