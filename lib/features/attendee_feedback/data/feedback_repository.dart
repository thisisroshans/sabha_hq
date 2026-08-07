import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/firebase/firestore_refs.dart';
import 'package:sabha_hq/core/models/feedback.dart';

final feedbackRepositoryProvider = Provider<FeedbackRepository>((ref) {
  return FeedbackRepository();
});

/// EventFeedback (lib/core/models/feedback.dart) existed since early in
/// the project — model + Firestore converter, but the /feedback route was
/// a placeholder (Text('Feedback Screen')) until task #8. Direct client
/// write, not moved server-side (see firestore.rules' comment on
/// feedback — same tradeoff task #6 made when deciding what was actually
/// in scope for the check-in move).
class FeedbackRepository {
  Future<void> submitFeedback({
    required String orgId,
    required String eventId,
    required int rating,
    String? comment,
  }) async {
    final docRef = FirestoreRefs.feedback(orgId, eventId).doc();
    await docRef.set(
      EventFeedback(
        id: docRef.id,
        eventId: eventId,
        rating: rating,
        comment: comment,
        submittedAt: DateTime.now(),
      ),
    );
  }

  /// Admin-side read — firestore.rules restricts this to owner/admin.
  Stream<List<EventFeedback>> watchFeedback(String orgId, String eventId) {
    return FirestoreRefs.feedback(orgId, eventId)
        .orderBy('submittedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }
}
