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

  /// Registers a brand new walk-in guest with full details and instantly checks them in.
  Future<Attendee> registerFullWalkIn({
    required String eventId,
    required String phone,
    required String name,
    required String email,
    required String companyName,
    required String designation,
    required String industry,
  }) async {
    final formattedPhone = phone.replaceAll(RegExp(r'\s+'), '');
    final docRef = FirestoreRefs.attendees(eventId).doc();

    final walkInGuest = Attendee(
      id: docRef.id,
      eventId: eventId,
      name: name,
      email: email,
      phone: formattedPhone,
      companyName: companyName,
      designation: designation,
      industry: industry,
      role: 'guest',
      isCheckedIn: true,
      checkInTime: DateTime.now(),
    );

    await docRef.set(walkInGuest);
    return walkInGuest;
  }
}
