import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/models/event.dart';
import 'package:sabha_hq/core/providers/current_org_provider.dart';
import '../data/event_repository.dart';

// =================================================================
// 1. LIVE EVENT STREAM
// AutoDispose ensures the stream stops listening if the admin
// navigates away to the Analytics screen, saving read costs.
//
// orgId is resolved internally (currentOrgIdProvider) rather than
// threaded through every call site — screens didn't change for this
// migration. While the org is still resolving, or if this account has
// no org (see currentOrgIdProvider's doc comment), this yields an empty
// list rather than erroring; EventActionController below surfaces a
// real error if someone tries to *write* with no org.
// =================================================================
final eventListProvider = StreamProvider.autoDispose<List<Event>>((ref) async* {
  final orgId = await ref.watch(currentOrgIdProvider.future);
  if (orgId == null) {
    yield const [];
    return;
  }
  final repository = ref.watch(eventRepositoryProvider);
  yield* repository.watchAllEvents(orgId);
});

final eventProvider = StreamProvider.autoDispose.family<Event?, String>((
  ref,
  eventId,
) async* {
  final orgId = await ref.watch(currentOrgIdProvider.future);
  if (orgId == null) {
    yield null;
    return;
  }
  final repository = ref.watch(eventRepositoryProvider);
  yield* repository.watchEvent(orgId, eventId);
});

/// Same as eventProvider above, but takes orgId explicitly instead of
/// resolving it from admin custom claims — for the public/guest-facing
/// Guest Activity screen, whose viewer is an anonymous check-in session
/// with no admin org claim to resolve (currentOrgIdProvider would always
/// yield null for them).
final eventForGuestProvider = StreamProvider.autoDispose
    .family<Event?, ({String orgId, String eventId})>((ref, key) {
      final repository = ref.watch(eventRepositoryProvider);
      return repository.watchEvent(key.orgId, key.eventId);
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

  Future<String> _requireOrgId() async {
    final orgId = await ref.read(currentOrgIdProvider.future);
    if (orgId == null) {
      throw Exception(
        'No organization found for this account. Contact an owner to be invited.',
      );
    }
    return orgId;
  }

  // Changed to return Future<bool>
  Future<bool> createNewEvent({
    required String title,
    required String location,
    required DateTime date,
  }) async {
    state = const AsyncLoading(); // Start loading spinner

    try {
      final orgId = await _requireOrgId();
      final repository = ref.read(eventRepositoryProvider);

      final newEvent = Event(
        id: '',
        title: title,
        location: location,
        date: date,
        branding: {'primaryColor': '#673AB7', 'logoUrl': ''},
      );

      await repository.createEvent(orgId, newEvent);

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
      final orgId = await _requireOrgId();
      final repository = ref.read(eventRepositoryProvider);
      await repository.updateEvent(orgId, updatedEvent);

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
      final orgId = await _requireOrgId();
      final repository = ref.read(eventRepositoryProvider);
      await repository.deleteEvent(orgId, eventId);
      state = const AsyncData(null);
    } catch (e, stackTrace) {
      state = AsyncError(e, stackTrace);
    }
  }
}
