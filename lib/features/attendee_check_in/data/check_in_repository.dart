import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/firebase/firestore_refs.dart';
import 'package:sabha_hq/core/models/attendee.dart';
import 'package:sabha_hq/core/utils/phone.dart';

final checkInRepositoryProvider = Provider<CheckInRepository>(
  (ref) => CheckInRepository(),
);

class CheckInRepository {
  /// Searches for a guest by phone. If found, checks them in.
  /// Returns NULL if the guest is not found (Walk-In required).
  Future<Attendee?> searchAndCheckIn(String eventId, String phone) async {
    final normalizedPhone = PhoneUtils.normalize(phone);
    final variants = PhoneUtils.lookupVariants(phone);
    if (variants.isEmpty) return null;

    // Match every shape this number might already be stored as, so a guest
    // imported as "+91 98765 43210" is still found when they type the bare
    // 10 digits at the kiosk. One indexed query, not one per variant.
    final querySnapshot = await FirestoreRefs.attendees(
      eventId,
    ).where('phone', whereIn: variants).limit(1).get();

    // Not found? Return null so the controller can trigger the Walk-In registration flow.
    if (querySnapshot.docs.isEmpty) return null;

    final doc = querySnapshot.docs.first;
    final attendee = doc.data();

    // If already checked in, return the attendee so the UI can say "Welcome Back"
    if (attendee.isCheckedIn) {
      return attendee;
    }

    // Check them in — and rewrite the phone to the canonical form while
    // we're already writing, so legacy records self-heal as people arrive
    // rather than needing a separate migration pass.
    await doc.reference.update({
      'isCheckedIn': true,
      'checkInTime': FieldValue.serverTimestamp(),
      'phone': normalizedPhone,
    });

    return attendee.copyWith(
      isCheckedIn: true,
      checkInTime: DateTime.now(),
      phone: normalizedPhone,
    );
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
    final docRef = FirestoreRefs.attendees(eventId).doc();

    final walkInGuest = Attendee(
      id: docRef.id,
      eventId: eventId,
      name: name,
      email: email,
      phone: PhoneUtils.normalize(phone),
      companyName: companyName,
      designation: designation,
      industry: industry,
      role: 'participant',
      isCheckedIn: true,
      checkInTime: DateTime.now(),
    );

    await docRef.set(walkInGuest);
    return walkInGuest;
  }
}
