import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/models/event.dart';
import '../data/event_repository.dart';

// =================================================================
// 1. LIVE EVENT STREAM
// AutoDispose ensures the stream stops listening if the admin
// navigates away to the Analytics screen, saving read costs.
// =================================================================
final eventListProvider = StreamProvider.autoDispose<List<Event>>((ref) {
  final repository = ref.watch(eventRepositoryProvider);
  return repository.watchAllEvents();
});

// =================================================================
// 2. FORM ACTION CONTROLLER
// Handles the business logic and loading state for creating events.
// =================================================================
final eventActionControllerProvider =
    AsyncNotifierProvider.autoDispose<EventActionController, void>(
      EventActionController.new,
    );

class EventActionController extends AutoDisposeAsyncNotifier<void> {
  @override
  FutureOr<void> build() {
    // Initial state is empty
  }

  Future<void> createNewEvent({
    required String title,
    required String location,
    required DateTime date,
  }) async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      final repository = ref.read(eventRepositoryProvider);

      // We pass an empty string for ID; the repository handles generating the real one.
      final newEvent = Event(
        id: '',
        title: title,
        location: location,
        date: date,
        branding: {
          'primaryColor': '#673AB7', // Default deep purple hex
          'logoUrl': '',
        },
      );

      await repository.createEvent(newEvent);
    });
  }

  Future<void> deleteEvent(String eventId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repository = ref.read(eventRepositoryProvider);
      await repository.deleteEvent(eventId);
    });
  }
}
