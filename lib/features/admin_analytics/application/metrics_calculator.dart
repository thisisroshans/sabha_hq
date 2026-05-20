import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/firebase/firestore_refs.dart';

class EventMetrics {
  final int totalRegistered;
  final int totalCheckedIn;
  final int guests;
  final int participants;

  const EventMetrics({
    required this.totalRegistered,
    required this.totalCheckedIn,
    required this.guests,
    required this.participants,
  });

  int get pending => totalRegistered - totalCheckedIn;
}

// Using .family allows us to pass the specific eventId we want to analyze
final eventMetricsProvider = FutureProvider.autoDispose
    .family<EventMetrics, String>((ref, eventId) async {
      // .get() fetches once. This prevents infinite read loops on the dashboard.
      final snapshot = await FirestoreRefs.attendees(eventId).get();
      final attendees = snapshot.docs.map((d) => d.data()).toList();

      int checkedIn = 0;
      int guests = 0;
      int participants = 0;

      for (final attendee in attendees) {
        if (attendee.isCheckedIn) checkedIn++;
        if (attendee.role == 'guest') guests++;
        if (attendee.role == 'participant') participants++;
      }

      return EventMetrics(
        totalRegistered: attendees.length,
        totalCheckedIn: checkedIn,
        guests: guests,
        participants: participants,
      );
    });
