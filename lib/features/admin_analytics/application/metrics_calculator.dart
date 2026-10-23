import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/firebase/firestore_refs.dart';
import 'package:sabha_hq/core/models/attendee.dart';
import 'package:sabha_hq/core/providers/current_org_provider.dart';

class EventMetrics {
  final int totalRegistered;
  final int totalCheckedIn;
  // Movers/pitchers are the stored 'guest'/'participant' roles — see
  // AttendeeRole for why the stored values didn't change with the names.
  final int movers;
  final int pitchers;

  const EventMetrics({
    required this.totalRegistered,
    required this.totalCheckedIn,
    required this.movers,
    required this.pitchers,
  });

  int get pending => totalRegistered - totalCheckedIn;

  static const empty = EventMetrics(
    totalRegistered: 0,
    totalCheckedIn: 0,
    movers: 0,
    pitchers: 0,
  );
}

// Using .family allows us to pass the specific eventId we want to analyze.
// orgId is resolved internally (currentOrgIdProvider) so the analytics
// screen's call site didn't need to change.
final eventMetricsProvider = FutureProvider.autoDispose
    .family<EventMetrics, String>((ref, eventId) async {
      final orgId = await ref.watch(currentOrgIdProvider.future);
      if (orgId == null) return EventMetrics.empty;

      // .get() fetches once. This prevents infinite read loops on the dashboard.
      final snapshot = await FirestoreRefs.attendees(orgId, eventId).get();
      final attendees = snapshot.docs.map((d) => d.data()).toList();

      int checkedIn = 0;
      int movers = 0;
      int pitchers = 0;

      for (final attendee in attendees) {
        if (attendee.isCheckedIn) checkedIn++;
        if (attendee.role == AttendeeRole.mover) movers++;
        if (attendee.role == AttendeeRole.pitcher) pitchers++;
      }

      return EventMetrics(
        totalRegistered: attendees.length,
        totalCheckedIn: checkedIn,
        movers: movers,
        pitchers: pitchers,
      );
    });
