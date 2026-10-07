import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/trip_api.dart';
import '../formatting/diary_format.dart';
import '../models/day.dart';
import '../models/trip_input.dart';
import 'day_providers.dart';

final uuidGeneratorProvider = Provider<String Function()>(
  (ref) => generateTripId,
);

/// RFC 4122 version 4, using operating-system-backed secure random bytes.
String generateTripId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class TripSubmissionState {
  const TripSubmissionState({this.pending, this.isSending = false, this.error});

  final Trip? pending;
  final bool isSending;
  final TripApiException? error;

  bool get isUncertain => error?.outcome == TripFailureOutcome.uncertain;
}

/// Kept for the app's lifetime so closing the form cannot discard an uncertain ID.
final tripSubmissionProvider =
    NotifierProvider<TripSubmission, TripSubmissionState>(TripSubmission.new);

class TripSubmission extends Notifier<TripSubmissionState> {
  @override
  TripSubmissionState build() => const TripSubmissionState();

  Future<bool> submit(TripInput input) {
    if (state.isSending ||
        state.isUncertain ||
        state.error?.outcome == TripFailureOutcome.conflict) {
      return Future.value(false);
    }
    // A rejected validation request may be edited while retaining its ID.
    final id = state.pending?.id ?? ref.read(uuidGeneratorProvider)();
    return _send(input.withId(id));
  }

  Future<bool> retry() {
    final pending = state.pending;
    if (state.isSending ||
        pending == null ||
        state.error?.outcome == TripFailureOutcome.conflict) {
      return Future.value(false);
    }
    return _send(pending);
  }

  bool reset() {
    if (state.isSending || state.isUncertain) return false;
    state = const TripSubmissionState();
    return true;
  }

  Future<bool> _send(Trip trip) async {
    // Set the guard before any await so a second tap cannot start another POST.
    state = TripSubmissionState(pending: trip, isSending: true);
    try {
      await ref.read(tripApiProvider).createTrip(trip);
      if (!ref.mounted) return false;
      ref.invalidate(dayProvider(almatyDay(trip.start)));
      state = const TripSubmissionState();
      return true;
    } on TripApiException catch (error) {
      if (!ref.mounted) return false;
      state = TripSubmissionState(pending: trip, error: error);
      return false;
    } catch (_) {
      if (!ref.mounted) return false;
      state = TripSubmissionState(
        pending: trip,
        error: const TripApiException(
          'Не удалось подтвердить сохранение. Повторите отправку этой поездки.',
        ),
      );
      return false;
    }
  }
}
