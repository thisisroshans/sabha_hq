import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/firebase/firestore_refs.dart';
import 'package:sabha_hq/core/models/event.dart';

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return EventRepository();
});

class EventRepository {
  /// Stream all events for the dashboard, ordered by date
  Stream<List<Event>> watchAllEvents() {
    return FirestoreRefs.events()
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  /// Create a new event.
  /// We generate a Firestore document reference first to get the unique ID.
  Future<void> createEvent(Event event) async {
    final docRef = FirestoreRefs.events().doc();

    // Update the event with the generated ID before saving
    final newEvent = event.copyWith(id: docRef.id);

    // Our withConverter automatically strips the 'id' field out before saving
    // to Firestore, keeping the DB clean!
    await docRef.set(newEvent);
  }

  /// Update an existing event's details or branding
  Future<void> updateEvent(Event event) async {
    await FirestoreRefs.events().doc(event.id).set(event);
  }

  /// Delete an event
  Future<void> deleteEvent(String eventId) async {
    await FirestoreRefs.events().doc(eventId).delete();
  }
}
