import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/firebase/firestore_refs.dart';
import 'package:sabha_hq/core/models/attendee.dart';

final guestRepositoryProvider = Provider<GuestRepository>(
  (ref) => GuestRepository(),
);

class GuestRepository {
  /// Stream attendees for a specific event
  Stream<List<Attendee>> watchGuests(String eventId) {
    return FirestoreRefs.attendees(eventId)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  /// Add a new guest to the event
  Future<void> addGuest(String eventId, Attendee guest) async {
    final docRef = FirestoreRefs.attendees(eventId).doc();
    final newGuest = guest.copyWith(id: docRef.id, eventId: eventId);
    await docRef.set(newGuest);
  }

  /// Remove a guest from the event
  Future<void> removeGuest(String eventId, String guestId) async {
    await FirestoreRefs.attendees(eventId).doc(guestId).delete();
  }
}
