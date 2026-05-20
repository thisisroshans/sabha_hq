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

  // Changed to return Future<bool>
  Future<bool> createNewEvent({
    required String title,
    required String location,
    required DateTime date,
  }) async {
    state = const AsyncLoading(); // Start loading spinner

    try {
      final repository = ref.read(eventRepositoryProvider);

      final newEvent = Event(
        id: '',
        title: title,
        location: location,
        date: date,
        branding: {'primaryColor': '#673AB7', 'logoUrl': ''},
      );

      await repository.createEvent(newEvent);

      state = const AsyncData(null); // Stop loading
      return true; // Success!
    } catch (e, stackTrace) {
      state = AsyncError(e, stackTrace); // Stop loading, show error
      return false; // Failed
    }
  }

  // Changed to return Future<bool>
  Future<bool> updateExistingEvent(Event updatedEvent) async {
    state = const AsyncLoading();
    try {
      final repository = ref.read(eventRepositoryProvider);
      await repository.updateEvent(updatedEvent);

      state = const AsyncData(null);
      return true;
    } catch (e, stackTrace) {
      state = AsyncError(e, stackTrace);
      return false;
    }
  }

  Future<void> deleteEvent(String eventId) async {
    state = const AsyncLoading();
    try {
      final repository = ref.read(eventRepositoryProvider);
      await repository.deleteEvent(eventId);
      state = const AsyncData(null);
    } catch (e, stackTrace) {
      state = AsyncError(e, stackTrace);
    }
  }
}
