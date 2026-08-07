import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/firebase/firestore_refs.dart';
import 'package:sabha_hq/core/models/event.dart';

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return EventRepository();
});

class EventRepository {
  // Must match functions' setGlobalOptions({ region: 'asia-south1' }) in
  // functions/src/index.ts.
  static const _functionsRegion = 'asia-south1';

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

  /// Create a new event via the createEvent callable
  /// (functions/src/events.ts) — not a direct write, so the org's
  /// maxEvents limit can actually be enforced (a Firestore rule can't
  /// count how many events already exist in a subcollection).
  Future<void> createEvent(String orgId, Event event) async {
    try {
      await FirebaseFunctions.instanceFor(region: _functionsRegion)
          .httpsCallable('createEvent')
          .call({
            'orgId': orgId,
            'title': event.title,
            'location': event.location,
            'dateIso': event.date.toIso8601String(),
          });
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? e.code);
    }
  }

  /// Update an existing event's details or branding. Unlike create, this
  /// isn't limit-gated, so it stays a direct client write (firestore.rules
  /// still checks isOwnerOrAdmin + org-active).
  Future<void> updateEvent(String orgId, Event event) async {
    await FirestoreRefs.events(orgId).doc(event.id).set(event);
  }

  /// Delete an event
  Future<void> deleteEvent(String orgId, String eventId) async {
    await FirestoreRefs.events(orgId).doc(eventId).delete();
  }
}
