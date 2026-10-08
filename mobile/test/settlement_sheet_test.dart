import 'dart:ui' show SemanticsAction;

import 'package:driver_shift_diary/theme/shift_theme.dart';
import 'package:driver_shift_diary/widgets/settlement_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/day_fixtures.dart';
import 'fixtures/diary_test_helpers.dart';

const _toggle = Key('calculation-toggle');
const _fold = Key('calculation-fold');
const _equation = Key('calculation-equation');

Future<void> pumpSheet(
  WidgetTester tester, {
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildShiftTheme(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: Scaffold(
            body: SingleChildScrollView(
              child: SettlementSheet(summary: sampleDay().summary),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<TestGesture> dragSheet(WidgetTester tester, double distance) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(_toggle)),
  );
  await gesture.moveBy(Offset(0, distance));
  await tester.pump();
  return gesture;
}

void main() {
  testWidgets('tap exposes the exact server calculation and closes it', (
    tester,
  ) async {
    await pumpSheet(tester);
    expect(tester.getSize(find.byKey(_fold)).height, 0);
    expect(findMoney('3 315 ₸'), findsOneWidget);
    expect(findMoney('3 900 ₸'), findsOneWidget);
    expect(findMoney('585 ₸'), findsOneWidget);
    expectMinimumTapTarget(tester, find.byKey(_toggle));

    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(_fold)).height, greaterThan(0));
    final equation = find.byKey(_equation);
    expect(
      find.descendant(of: equation, matching: findMoney('3 900 ₸')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: equation, matching: findMoney('585 ₸')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: equation, matching: findMoney('3 315 ₸')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(_fold)).height, 0);
    expect(tester.takeException(), isNull);
  });

  for (final fraction in [0.34, 0.36, 1.0]) {
    testWidgets('drag $fraction settles at the 0.35 threshold', (tester) async {
      await pumpSheet(tester);
      final gesture = await dragSheet(tester, 90 * fraction);
      expect(tester.getSize(find.byKey(_fold)).height, greaterThan(0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(_fold)).height,
        fraction > 0.35 ? greaterThan(0) : 0,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('upward drag closes an open calculation', (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    final gesture = await dragSheet(tester, -90);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(_fold)).height, 0);
    expect(tester.takeException(), isNull);
  });

  for (final initiallyOpen in [false, true]) {
    testWidgets('cancelled drag restores initially open $initiallyOpen', (
      tester,
    ) async {
      await pumpSheet(tester);
      if (initiallyOpen) {
        await tester.tap(find.byKey(_toggle));
        await tester.pumpAndSettle();
      }
      final gesture = await dragSheet(tester, initiallyOpen ? -45 : 45);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(_fold)).height,
        initiallyOpen ? greaterThan(0) : 0,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'collapsed and fractional calculation is excluded from semantics',
    (tester) async {
      await pumpSheet(tester);
      var data = tester.getSemantics(find.byKey(_toggle)).getSemanticsData();
      expect(data.label, 'Показать расчёт');
      expect(data.value, 'Свёрнут');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(
        find.bySemanticsLabel('3 900 ₸ минус 585 ₸ равно 3 315 ₸'),
        findsNothing,
      );

      final gesture = await dragSheet(tester, 45);
      expect(
        find.bySemanticsLabel('3 900 ₸ минус 585 ₸ равно 3 315 ₸'),
        findsNothing,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      data = tester.getSemantics(find.byKey(_toggle)).getSemanticsData();
      expect(data.label, 'Скрыть расчёт');
      expect(data.value, 'Раскрыт');
      expect(
        find.bySemanticsLabel('3 900 ₸ минус 585 ₸ равно 3 315 ₸'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keyboard focus supports Space and Enter activation', (
    tester,
  ) async {
    await pumpSheet(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(_fold)).height, greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(_fold)).height, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'normal transition lasts 350ms while reduced motion is immediate',
    (tester) async {
      await pumpSheet(tester);
      await tester.tap(find.byKey(_toggle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 175));
      final halfway = tester.getSize(find.byKey(_fold)).height;
      await tester.pump(const Duration(milliseconds: 175));
      final complete = tester.getSize(find.byKey(_fold)).height;
      expect(halfway, greaterThan(0));
      expect(halfway, lessThan(complete));

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpSheet(tester, disableAnimations: true);
      await tester.tap(find.byKey(_toggle));
      await tester.pump();
      expect(tester.getSize(find.byKey(_fold)).height, closeTo(complete, 0.1));
      await tester.tap(find.byKey(_toggle));
      await tester.pump();
      expect(tester.getSize(find.byKey(_fold)).height, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
