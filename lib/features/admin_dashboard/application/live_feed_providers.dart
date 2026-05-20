import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/models/attendee.dart';

// Streams the 50 most recent check-ins across ALL events
final liveActivityStreamProvider = StreamProvider.autoDispose<List<Attendee>>((
  ref,
) {
  // collectionGroup queries every subcollection named 'attendees' anywhere in the database
  return FirebaseFirestore.instance
      .collectionGroup('attendees')
      // Only get people who have actually checked in
      .where('isCheckedIn', isEqualTo: true)
      // Sort by the newest first
      .orderBy('checkInTime', descending: true)
      .limit(50)
      .snapshots()
      .map((snapshot) {
        // Assuming your Attendee model has a fromMap/fromJson factory,
        // or map it manually based on how your model is structured.
        return snapshot.docs.map((doc) {
          final data = doc.data();
          // Adjust this mapping based on your exact Attendee model structure
          return Attendee(
            id: doc.id,
            eventId: data['eventId'] ?? '',
            name: data['name'] ?? 'Unknown',
            phone: data['phone'] ?? '',
            email: data['email'] ?? '',
            role: data['role'] ?? 'guest',
            isCheckedIn: data['isCheckedIn'] ?? false,
            checkInTime: data['checkInTime'] != null
                ? (data['checkInTime'] as Timestamp).toDate()
                : null,
          );
        }).toList();
      });
});
