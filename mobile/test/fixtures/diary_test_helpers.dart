import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder findMoney(String value) => find.byWidgetPredicate(
  (widget) =>
      widget is Text &&
      (widget.data == value ||
          widget.textSpan?.toPlainText() == value ||
          widget.semanticsLabel == value),
  description: 'Text with exact visible or accessible money "$value"',
);

Future<void> expectSelectedDate(WidgetTester tester, String date) async {
  await expectDateControl(tester, 'choose-day', date);
}

Future<void> expectDateControl(
  WidgetTester tester,
  String key,
  String date,
) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pump();
  final semantics = tester.ensureSemantics();
  try {
    expect(
      tester.getSemantics(find.byKey(Key(key))).getSemanticsData().label,
      contains(date),
    );
  } finally {
    semantics.dispose();
  }
}

void expectMinimumTapTarget(WidgetTester tester, Finder finder) {
  final size = tester.getSize(finder);
  expect(size.width, greaterThanOrEqualTo(48));
  expect(size.height, greaterThanOrEqualTo(48));
}

Future<void> scrollDayUntilVisible(WidgetTester tester, Finder finder) async {
  final scroll = find.byKey(const Key('day-scroll'));
  for (var attempt = 0; attempt < 30 && finder.evaluate().isEmpty; attempt++) {
    final viewport = tester.getRect(scroll);
    // The side margin belongs to the day scroll, outside the draggable seam.
    await tester.dragFrom(
      Offset(viewport.left + 8, viewport.center.dy),
      const Offset(0, -160),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}
