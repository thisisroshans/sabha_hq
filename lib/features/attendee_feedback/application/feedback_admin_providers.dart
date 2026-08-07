import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/models/feedback.dart';
import 'package:sabha_hq/core/providers/current_org_provider.dart';
import '../data/feedback_repository.dart';

/// Admin-side read of an event's feedback — resolves orgId internally
/// (currentOrgIdProvider), same pattern as eventMetricsProvider. Rules
/// restrict this collection to owner/admin, matching who this provider
/// is meant to be watched by.
final feedbackForEventProvider = StreamProvider.autoDispose
    .family<List<EventFeedback>, String>((ref, eventId) async* {
      final orgId = await ref.watch(currentOrgIdProvider.future);
      if (orgId == null) {
        yield const [];
        return;
      }
      final repo = ref.watch(feedbackRepositoryProvider);
      yield* repo.watchFeedback(orgId, eventId);
    });
