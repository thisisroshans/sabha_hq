import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/models/attendee.dart';
import '../data/check_in_repository.dart';

enum CheckInStep { idle, loading, needsWalkInName, success, error }

class StaffCheckInState {
  final CheckInStep step;
  final String? pendingPhone;
  final Attendee? checkedInGuest;
  final String? errorMessage;
  final bool isWelcomeBack;

  StaffCheckInState({
    this.step = CheckInStep.idle,
    this.pendingPhone,
    this.checkedInGuest,
    this.errorMessage,
    this.isWelcomeBack = false,
  });
}

final staffCheckInProvider =
    NotifierProvider.autoDispose<StaffCheckInController, StaffCheckInState>(
      StaffCheckInController.new,
    );

class StaffCheckInController extends AutoDisposeNotifier<StaffCheckInState> {
  @override
  StaffCheckInState build() => StaffCheckInState();

  Future<void> submitPhone(String eventId, String phone) async {
    state = StaffCheckInState(step: CheckInStep.loading);

    try {
      final repo = ref.read(checkInRepositoryProvider);
      final guest = await repo.searchAndCheckIn(eventId, phone);

      if (guest == null) {
        // Walk-In Scenario
        state = StaffCheckInState(
          step: CheckInStep.needsWalkInName,
          pendingPhone: phone,
        );
      } else {
        // Success Scenario
        state = StaffCheckInState(
          step: CheckInStep.success,
          checkedInGuest: guest,
          isWelcomeBack:
              guest.checkInTime != null, // If they already had a timestamp
        );
      }
    } catch (e) {
      state = StaffCheckInState(
        step: CheckInStep.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> submitWalkIn(String eventId, String name) async {
    final phone = state.pendingPhone;
    if (phone == null) return;

    state = StaffCheckInState(step: CheckInStep.loading);
    try {
      final repo = ref.read(checkInRepositoryProvider);
      final guest = await repo.registerWalkIn(eventId, phone, name);

      state = StaffCheckInState(
        step: CheckInStep.success,
        checkedInGuest: guest,
      );
    } catch (e) {
      state = StaffCheckInState(
        step: CheckInStep.error,
        errorMessage: e.toString(),
      );
    }
  }

  void reset() {
    state = StaffCheckInState();
  }
}
