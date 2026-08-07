import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/firebase/firestore_refs.dart';
import 'package:sabha_hq/core/models/schedule_item.dart';

final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  return ScheduleRepository();
});

/// ScheduleItem (lib/core/models/schedule_item.dart) has existed since
/// early in the project — fully modelled, zero repository, zero UI, until
/// task #8. Mirrors EventRepository's shape.
class ScheduleRepository {
  Stream<List<ScheduleItem>> watchScheduleItems(String orgId, String eventId) {
    return FirestoreRefs.scheduleItems(orgId, eventId)
        .orderBy('startTime')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  Future<void> addScheduleItem(
    String orgId,
    String eventId,
    ScheduleItem item,
  ) async {
    final docRef = FirestoreRefs.scheduleItems(orgId, eventId).doc();
    await docRef.set(item.copyWith(id: docRef.id, eventId: eventId));
  }

  Future<void> updateScheduleItem(
    String orgId,
    String eventId,
    ScheduleItem item,
  ) async {
    await FirestoreRefs.scheduleItems(orgId, eventId).doc(item.id).set(item);
  }

  Future<void> deleteScheduleItem(
    String orgId,
    String eventId,
    String itemId,
  ) async {
    await FirestoreRefs.scheduleItems(orgId, eventId).doc(itemId).delete();
  }
}
