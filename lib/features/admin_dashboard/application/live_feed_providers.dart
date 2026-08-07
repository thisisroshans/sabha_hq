import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/firebase/firestore_refs.dart';
import 'package:sabha_hq/core/models/attendee.dart';
import 'package:sabha_hq/core/providers/current_org_provider.dart';

// 1. New Provider to track the selected event in the Live Feed
final liveFeedEventFilterProvider = StateProvider<String>((ref) => 'all');

// Controls how many records to fetch. Starts at 25.
final liveFeedLimitProvider = StateProvider<int>((ref) => 25);

// 2. Updated Stream Provider
//
// The "All Events" branch used to be a bare collectionGroup('attendees')
// query with no org filter at all — across every tenant, not just this
// admin's. Now scoped with .where('orgId', isEqualTo: orgId), matching
// the composite index added for exactly this in firestore.indexes.json
// and the isOrgMember() check in firestore.rules.
final liveActivityStreamProvider = StreamProvider.autoDispose<List<Attendee>>((
  ref,
) async* {
  final orgId = await ref.watch(currentOrgIdProvider.future);
  if (orgId == null) {
    yield const [];
    return;
  }

  final eventId = ref.watch(liveFeedEventFilterProvider);

  Query query;
  if (eventId == 'all') {
    query = FirebaseFirestore.instance
        .collectionGroup('attendees')
        .where('orgId', isEqualTo: orgId);
  } else {
    query = FirestoreRefs.attendees(orgId, eventId);
  }

  yield* query
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
//
// Takes orgId explicitly (not resolved from currentOrgIdProvider) because
// its caller is the PUBLIC check-in flow — a guest has no admin claims to
// resolve an org from, so the screen carries orgId from the check-in URL
// instead. See check_in_screen.dart / guest_activity_screen.dart.
final eventAttendeesStreamProvider = StreamProvider.autoDispose
    .family<List<Attendee>, ({String orgId, String eventId})>((ref, key) {
      return FirestoreRefs.attendees(key.orgId, key.eventId)
          .where('isCheckedIn', isEqualTo: true)
          .orderBy('checkInTime', descending: true)
          .limit(ref.watch(liveFeedLimitProvider))
          .snapshots()
          .map(
            (snapshot) => snapshot.docs.map((doc) => doc.data()).toList(),
          );
    });
