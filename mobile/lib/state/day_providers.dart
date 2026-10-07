import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/day_api.dart';
import '../formatting/diary_format.dart';
import '../models/day.dart';
import '../models/diary_date.dart';

final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
final todayProvider = Provider<DiaryDate>((ref) {
  final now = ref.watch(clockProvider)();
  final timer = Timer(
    nextAlmatyMidnight(now).difference(now.toUtc()),
    ref.invalidateSelf,
  );
  ref.onDispose(timer.cancel);
  return almatyDay(now);
});

final selectedDayProvider = NotifierProvider<SelectedDay, DiaryDate>(
  SelectedDay.new,
);

class SelectedDay extends Notifier<DiaryDate> {
  @override
  DiaryDate build() => ref.read(todayProvider);

  void select(DiaryDate date) {
    if (date.compareTo(DiaryDate.first) >= 0 &&
        date.compareTo(DiaryDate.last) <= 0) {
      state = date;
    }
  }

  void previous() {
    if (state.compareTo(DiaryDate.first) > 0) select(state.previous);
  }

  void next() {
    if (state.compareTo(DiaryDate.last) < 0) select(state.next);
  }
}

/// Each date owns its request/result. A late response cannot update another day.
/// Releasing a date cancels its HTTP request; refresh also cancels its old one.
final dayProvider = FutureProvider.autoDispose.family<DiaryDay, DiaryDate>(
  (ref, date) {
    final token = CancelToken();
    ref.onDispose(() => token.cancel());
    return ref.watch(dayApiProvider).getDay(date, cancelToken: token);
  },
  // A visible retry is controlled by the user, without hidden background loops.
  retry: (_, _) => null,
);
