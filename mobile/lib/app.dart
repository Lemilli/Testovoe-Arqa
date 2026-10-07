import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/day_providers.dart';
import 'widgets/day_screen.dart';

class DriverShiftDiaryApp extends ConsumerStatefulWidget {
  const DriverShiftDiaryApp({super.key});

  @override
  ConsumerState<DriverShiftDiaryApp> createState() =>
      _DriverShiftDiaryAppState();
}

class _DriverShiftDiaryAppState extends ConsumerState<DriverShiftDiaryApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(todayProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Дневник смен водителя',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006A6A)),
      ),
      home: const DayScreen(),
    );
  }
}
