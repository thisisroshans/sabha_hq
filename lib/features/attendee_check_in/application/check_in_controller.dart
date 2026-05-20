import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/models/attendee.dart';
import '../data/check_in_repository.dart';

final checkInControllerProvider =
    AsyncNotifierProvider.autoDispose<CheckInController, Attendee?>(
      CheckInController.new,
    );

class CheckInController extends AutoDisposeAsyncNotifier<Attendee?> {
  @override
  FutureOr<Attendee?> build() {
    return null; // Initial state: not checked in
  }

  Future<void> submitCheckIn(String eventId, String email) async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      final repository = ref.read(checkInRepositoryProvider);
      return await repository.verifyAndCheckIn(eventId, email);
    });
  }
}
