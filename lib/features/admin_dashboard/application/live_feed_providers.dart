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

// Scoped to a single event (used by the attendee-facing Guest Activity
// screen after check-in) — independent of the admin dashboard's global
// liveFeedEventFilterProvider so it never fights over shared state.
final eventAttendeesStreamProvider = StreamProvider.autoDispose
    .family<List<Attendee>, String>((ref, eventId) {
      return FirestoreRefs.attendees(eventId)
          .where('isCheckedIn', isEqualTo: true)
          .orderBy('checkInTime', descending: true)
          .limit(ref.watch(liveFeedLimitProvider))
          .snapshots()
          .map(
            (snapshot) => snapshot.docs.map((doc) => doc.data()).toList(),
          );
    });

// Controls how many records to fetch. Starts at 25.
final liveFeedLimitProvider = StateProvider<int>((ref) => 25);

final participantsStreamProvider = StreamProvider.autoDispose<List<Attendee>>((
  ref,
) {
  final eventId = ref.watch(liveFeedEventFilterProvider);
  final currentLimit = ref.watch(
    liveFeedLimitProvider,
  ); // Watch the dynamic limit

  Query query = eventId == 'all'
      ? FirebaseFirestore.instance.collectionGroup('attendees')
      : FirestoreRefs.attendees(eventId);

  return query
      .where('isCheckedIn', isEqualTo: true)
      .where('role', isEqualTo: 'participant')
      .orderBy('checkInTime', descending: true)
      .limit(currentLimit) // Use the dynamic limit here
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map((doc) {
          final data = doc.data();
          if (data is Attendee) return data;
          return Attendee.fromMap(data as Map<String, dynamic>, doc.id);
        }).toList(),
      );
});

final guestsStreamProvider = StreamProvider.autoDispose<List<Attendee>>((ref) {
  final eventId = ref.watch(liveFeedEventFilterProvider);
  final currentLimit = ref.watch(
    liveFeedLimitProvider,
  ); // Watch the dynamic limit

  Query query = eventId == 'all'
      ? FirebaseFirestore.instance.collectionGroup('attendees')
      : FirestoreRefs.attendees(eventId);

  return query
      .where('isCheckedIn', isEqualTo: true)
      .where('role', isNotEqualTo: 'participant')
      .orderBy('checkInTime', descending: true)
      .limit(currentLimit) // Use the dynamic limit here
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map((doc) {
          final data = doc.data();
          if (data is Attendee) return data;
          return Attendee.fromMap(data as Map<String, dynamic>, doc.id);
        }).toList(),
      );
});
