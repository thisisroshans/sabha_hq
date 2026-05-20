import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/models/attendee.dart';
import '../data/guest_repository.dart';

// 1. Holds the ID of the currently selected event in the dropdown
final selectedEventFilterProvider = StateProvider<String?>((ref) => null);

// 2. Streams the guests ONLY for the selected event
final guestListProvider = StreamProvider.autoDispose<List<Attendee>>((ref) {
  final eventId = ref.watch(selectedEventFilterProvider);
  if (eventId == null) return const Stream.empty();

  return ref.watch(guestRepositoryProvider).watchGuests(eventId);
});

// 3. Handles Add/Delete actions
final guestActionControllerProvider =
    AsyncNotifierProvider.autoDispose<GuestActionController, void>(
      GuestActionController.new,
    );

class GuestActionController extends AutoDisposeAsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<bool> addGuest({
    required String name,
    required String email,
    required String role,
    required String phone,
  }) async {
    state = const AsyncLoading();
    final eventId = ref.read(selectedEventFilterProvider);

    if (eventId == null) return false;

    try {
      final repository = ref.read(guestRepositoryProvider);
      final newGuest = Attendee(
        id: '',
        eventId: eventId,
        phone: phone,
        name: name,
        email: email,
        role: role,
      );

      await repository.addGuest(eventId, newGuest);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<void> removeGuest(String guestId) async {
    final eventId = ref.read(selectedEventFilterProvider);
    if (eventId == null) return;

    try {
      await ref.read(guestRepositoryProvider).removeGuest(eventId, guestId);
    } catch (e) {
      // Handle error quietly or show toast
    }
  }
}
