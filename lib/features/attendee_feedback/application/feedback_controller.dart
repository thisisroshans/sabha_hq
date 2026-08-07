import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/features/attendee_check_in/application/phone_auth_controller.dart';
import '../data/feedback_repository.dart';

enum FeedbackStep { idle, submitting, submitted, error }

class FeedbackState {
  final FeedbackStep step;
  final String? errorMessage;

  const FeedbackState({this.step = FeedbackStep.idle, this.errorMessage});
}

final feedbackControllerProvider =
    NotifierProvider.autoDispose<FeedbackController, FeedbackState>(
      FeedbackController.new,
    );

class FeedbackController extends AutoDisposeNotifier<FeedbackState> {
  @override
  FeedbackState build() => const FeedbackState();

  Future<void> submit({
    required String orgId,
    required String eventId,
    required int rating,
    String? comment,
  }) async {
    state = const FeedbackState(step: FeedbackStep.submitting);

    try {
      // Same event-scoped session firestore.rules' isGuestSessionFor()
      // checks for check-in — feedback wasn't moved server-side (task #6
      // was check-in only), so this is still a direct client write and
      // still needs the claim.
      final ready = await ref
          .read(guestAuthControllerProvider.notifier)
          .ensureGuestSession(orgId, eventId);
      if (!ready) {
        state = const FeedbackState(
          step: FeedbackStep.error,
          errorMessage: 'Could not connect. Please try again.',
        );
        return;
      }

      await ref.read(feedbackRepositoryProvider).submitFeedback(
            orgId: orgId,
            eventId: eventId,
            rating: rating,
            comment: comment,
          );

      state = const FeedbackState(step: FeedbackStep.submitted);
    } catch (e) {
      state = FeedbackState(step: FeedbackStep.error, errorMessage: e.toString());
    }
  }
}
