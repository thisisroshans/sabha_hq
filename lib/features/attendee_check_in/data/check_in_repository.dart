import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/firebase/firestore_refs.dart';
import 'package:sabha_hq/core/models/attendee.dart';

final checkInRepositoryProvider = Provider<CheckInRepository>((ref) {
  return CheckInRepository();
});

class CheckInRepository {
  /// Searches for the attendee by email and marks them as checked in
  Future<Attendee> verifyAndCheckIn(String eventId, String email) async {
    // 1. Query the subcollection for this specific email
    final querySnapshot = await FirestoreRefs.attendees(
      eventId,
    ).where('email', isEqualTo: email.toLowerCase().trim()).limit(1).get();

    // 2. Validate existence
    if (querySnapshot.docs.isEmpty) {
      throw Exception(
        'Email not found on the guest list. Please check for typos.',
      );
    }

    final doc = querySnapshot.docs.first;
    final attendee = doc.data();

    // 3. Prevent double check-ins
    if (attendee.isCheckedIn) {
      throw Exception(
        'You are already checked in! Welcome back, ${attendee.name}.',
      );
    }

    // 4. Update Firestore directly
    await doc.reference.update({
      'isCheckedIn': true,
      'checkInTime': FieldValue.serverTimestamp(),
    });

    // 5. Return the updated model to the UI for a personalized greeting
    return attendee.copyWith(isCheckedIn: true, checkInTime: DateTime.now());
  }
}
