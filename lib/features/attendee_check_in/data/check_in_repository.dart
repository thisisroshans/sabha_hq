import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/firebase/firestore_refs.dart';
import 'package:sabha_hq/core/models/attendee.dart';

final checkInRepositoryProvider = Provider<CheckInRepository>(
  (ref) => CheckInRepository(),
);

class CheckInRepository {
  /// Searches for a guest by phone. If found, checks them in.
  /// Returns NULL if the guest is not found (Walk-In required).
  Future<Attendee?> searchAndCheckIn(String eventId, String phone) async {
    // Standardize phone format to ensure accurate matching (e.g., remove spaces)
    final formattedPhone = phone.replaceAll(RegExp(r'\s+'), '');

    final querySnapshot = await FirestoreRefs.attendees(
      eventId,
    ).where('phone', isEqualTo: formattedPhone).limit(1).get();

    // Not found? Return null so the controller can trigger the Walk-In registration flow.
    if (querySnapshot.docs.isEmpty) return null;

    final doc = querySnapshot.docs.first;
    final attendee = doc.data();

    // If already checked in, return the attendee so the UI can say "Welcome Back"
    if (attendee.isCheckedIn) {
      return attendee;
    }

    // Check them in!
    await doc.reference.update({
      'isCheckedIn': true,
      'checkInTime': FieldValue.serverTimestamp(),
    });

    return attendee.copyWith(isCheckedIn: true, checkInTime: DateTime.now());
  }

  /// Registers a brand new walk-in guest and instantly checks them in.
  Future<Attendee> registerWalkIn(
    String eventId,
    String phone,
    String name,
  ) async {
    final formattedPhone = phone.replaceAll(RegExp(r'\s+'), '');

    // Generate a new document reference to get a unique ID
    final docRef = FirestoreRefs.attendees(eventId).doc();

    final walkInGuest = Attendee(
      id: docRef.id,
      eventId: eventId,
      name: name,
      email: '', // Not required for walk-ins based on the staff-driven model
      phone: formattedPhone,
      role: 'guest',
      isCheckedIn: true,
      checkInTime: DateTime.now(),
    );

    // Save the new guest to Firestore
    await docRef.set(walkInGuest);

    return walkInGuest;
  }
}
