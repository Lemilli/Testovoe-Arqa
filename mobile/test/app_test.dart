import 'package:driver_shift_diary/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('entry point shows the Russian Material 3 foundation', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle();

    expect(find.text('Дневник смен'), findsOneWidget);
    expect(find.text('Дневник смен водителя'), findsOneWidget);
    expect(find.text('Здесь будут поездки и сводка за день.'), findsOneWidget);
    expect(find.text('Hello World!'), findsNothing);

    final context = tester.element(find.byType(Scaffold));
    expect(Localizations.localeOf(context), const Locale('ru'));
    expect(MaterialLocalizations.of(context).backButtonTooltip, 'Назад');
    expect(Theme.of(context).useMaterial3, isTrue);
    expect(tester.takeException(), isNull);
  });
}
