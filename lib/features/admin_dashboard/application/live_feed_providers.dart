import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/firebase/firestore_refs.dart';
import 'package:sabha_hq/core/models/attendee.dart';

// 1. New Provider to track the selected event in the Live Feed
final liveFeedEventFilterProvider = StateProvider<String>((ref) => 'all');

// 2. Updated Stream Provider
final liveActivityStreamProvider = StreamProvider.autoDispose<List<Attendee>>((
  ref,
) {
  final eventId = ref.watch(liveFeedEventFilterProvider);

  Query query;

  if (eventId == 'all') {
    // Global feed across all events (returns Map<String, dynamic>)
    query = FirebaseFirestore.instance.collectionGroup('attendees');
  } else {
    // Local feed for a specific event (might return Attendee objects via withConverter)
    query = FirestoreRefs.attendees(eventId);
  }

  return query
      .where('isCheckedIn', isEqualTo: true)
      .orderBy('checkInTime', descending: true)
      .limit(50)
      .snapshots()
      .map((snapshot) {
        return snapshot.docs.map((doc) {
          final data = doc.data();

          // SAFETY CHECK: Handle both pre-converted objects and raw Maps
          if (data is Attendee) {
            return data;
          } else {
            return Attendee.fromMap(data as Map<String, dynamic>, doc.id);
          }
        }).toList();
      });
});
