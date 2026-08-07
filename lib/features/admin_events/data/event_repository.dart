import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/firebase/firestore_refs.dart';
import 'package:sabha_hq/core/models/event.dart';

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return EventRepository();
});

class EventRepository {
  /// Stream all events for the dashboard, ordered by date
  Stream<List<Event>> watchAllEvents(String orgId) {
    return FirestoreRefs.events(orgId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  /// Stream a single event
  Stream<Event?> watchEvent(String orgId, String eventId) {
    return FirestoreRefs.event(
      orgId,
      eventId,
    ).snapshots().map((snapshot) => snapshot.data());
  }

  Future<Event?> getEvent(String orgId, String eventId) async {
    final snapshot = await FirestoreRefs.event(orgId, eventId).get();
    return snapshot.data();
  }

  /// Create a new event.
  /// We generate a Firestore document reference first to get the unique ID.
  Future<void> createEvent(String orgId, Event event) async {
    final docRef = FirestoreRefs.events(orgId).doc();

    // Update the event with the generated ID before saving
    final newEvent = event.copyWith(id: docRef.id);

    // Our withConverter automatically strips the 'id' field out before saving
    // to Firestore, keeping the DB clean!
    await docRef.set(newEvent);
  }

  /// Update an existing event's details or branding
  Future<void> updateEvent(String orgId, Event event) async {
    await FirestoreRefs.events(orgId).doc(event.id).set(event);
  }

  /// Delete an event
  Future<void> deleteEvent(String orgId, String eventId) async {
    await FirestoreRefs.events(orgId).doc(eventId).delete();
  }
}
