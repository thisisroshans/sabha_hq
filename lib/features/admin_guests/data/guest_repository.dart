import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/firebase/firestore_refs.dart';
import 'package:sabha_hq/core/models/attendee.dart';
import 'package:sabha_hq/core/utils/phone.dart';

final guestRepositoryProvider = Provider<GuestRepository>(
  (ref) => GuestRepository(),
);

class GuestRepository {
  /// Stream attendees for a specific event
  Stream<List<Attendee>> watchGuests(String orgId, String eventId) {
    return FirestoreRefs.attendees(orgId, eventId)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  /// Add a single new guest to the event
  Future<void> addGuest(String orgId, String eventId, Attendee guest) async {
    final docRef = FirestoreRefs.attendees(orgId, eventId).doc();
    final newGuest = guest.copyWith(
      id: docRef.id,
      eventId: eventId,
      orgId: orgId,
      phone: PhoneUtils.normalize(guest.phone),
    );
    await docRef.set(newGuest);
  }

  /// Uploads multiple guests simultaneously using a WriteBatch
  Future<void> addGuestsInBatch(
    String orgId,
    String eventId,
    List<Attendee> guests,
  ) async {
    final db = FirebaseFirestore.instance;
    final batch = db.batch();

    final collectionRef = FirestoreRefs.attendees(orgId, eventId);

    for (final guest in guests) {
      final docRef = collectionRef.doc(); // Generate new ID

      // Canonical 10-digit form, so a CSV carrying "+91 98765 43210" still
      // matches the bare digits an attendee types at the kiosk.
      final newGuest = guest.copyWith(
        id: docRef.id,
        eventId: eventId,
        orgId: orgId,
        phone: PhoneUtils.normalize(guest.phone),
      );

      batch.set(docRef, newGuest);
    }

    // Commit all operations as a single atomic unit
    await batch.commit();
  }

  /// Remove a guest from the event
  Future<void> removeGuest(String orgId, String eventId, String guestId) async {
    await FirestoreRefs.attendees(orgId, eventId).doc(guestId).delete();
  }
}
