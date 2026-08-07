import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sabha_hq/core/models/attendee.dart';
import 'package:sabha_hq/core/models/event.dart';
import 'package:sabha_hq/features/admin_dashboard/application/live_feed_providers.dart';
import 'package:sabha_hq/features/admin_events/application/event_providers.dart';
import 'package:sabha_hq/features/attendee_check_in/application/phone_auth_controller.dart';
import 'package:sabha_hq/features/attendee_check_in/application/staff_check_in_controller.dart';

class GuestActivityScreen extends ConsumerWidget {
  final String orgId;
  final String eventId;
  final String guestName;

  const GuestActivityScreen({
    super.key,
    required this.orgId,
    required this.eventId,
    required this.guestName,
  });

  void _handleLogout(BuildContext context, WidgetRef ref) {
    // 1. Reset the check-in form state.
    ref.read(staffCheckInProvider.notifier).reset();
    // 2. Sign this guest out of Firebase Auth so the shared kiosk device
    //    doesn't carry their identity (or event-scoped claim) into the
    //    next person's check-in.
    ref.read(guestAuthControllerProvider.notifier).reset();

    // 3. Navigate back to the check-in phone-entry screen via go_router
    //    (not a raw Navigator push) so the route/redirect logic stays in
    //    sync — this lands back on "enter your phone number", never on
    //    the admin login screen.
    context.go('/check-in?orgId=$orgId&eventId=$eventId');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveFeedState = ref.watch(
      eventAttendeesStreamProvider((orgId: orgId, eventId: eventId)),
    );
    final eventState = ref.watch(
      eventForGuestProvider((orgId: orgId, eventId: eventId)),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Event'),
        backgroundColor: const Color(0xFFc51f43),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () => _handleLogout(context, ref),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 800;
                    return eventState.when(
                      error: (error, stackTrace) => Text('Error: $error'),
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      data: (event) {
                        if (event == null) {
                          return const Center(child: Text('Event not found'));
                        }
                        return Padding(
                          padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(height: isMobile ? 16 : 24),

                              // SPLIT LIVE FEED LIST
                              Expanded(
                                child: liveFeedState.when(
                                  // Loading more (limit bump from scrolling
                                  // to the bottom) re-subscribes the stream,
                                  // which briefly re-enters "loading" — keep
                                  // showing the current list instead of
                                  // flashing a spinner and losing scroll
                                  // position. Only spinner-block on the very
                                  // first load, when there's no data yet.
                                  skipLoadingOnReload: true,
                                  loading: () => const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                  error: (e, st) => Center(
                                    child: Text('Error loading feed: $e'),
                                  ),
                                  data: (attendees) {
                                    return _buildColumn(
                                      title:
                                          'Checked In (${attendees.length})',
                                      icon: Icons.how_to_reg,
                                      color: const Color(0xFFc51f43),
                                      attendees: attendees,
                                      events: event,
                                      ref: ref,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _buildColumn({
  required String title,
  required IconData icon,
  required Color color,
  required List<Attendee> attendees,
  required Event? events,
  required WidgetRef ref,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Column Header
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),

      // Column List
      Expanded(
        child: attendees.isEmpty
            ? Center(
                child: Text(
                  'No check-ins yet.',
                  style: TextStyle(fontSize: 16, color: Colors.grey[400]),
                ),
              )
            : Card(
                margin: EdgeInsets.zero,
                child: NotificationListener<ScrollEndNotification>(
                  onNotification: (scrollInfo) {
                    if (scrollInfo.metrics.pixels >=
                        scrollInfo.metrics.maxScrollExtent) {
                      ref.read(liveFeedLimitProvider.notifier).state += 25;
                    }
                    return true;
                  },
                  child: ListView.separated(
                    itemCount: attendees.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      return _buildAttendeeTile(attendees[index], events);
                    },
                  ),
                ),
              ),
      ),
    ],
  );
}

Widget _buildAttendeeTile(Attendee guest, Event? events) {
  final isParticipant = guest.role.toLowerCase() == 'participant';

  final timeString = guest.checkInTime != null
      ? DateFormat('h:mm a').format(guest.checkInTime!)
      : 'Just now';
  final dateString = guest.checkInTime != null
      ? DateFormat('MMM d, yyyy').format(guest.checkInTime!)
      : 'Today';

  final roleDisplay = guest.role.isNotEmpty
      ? '${guest.role[0].toUpperCase()}${guest.role.substring(1).toLowerCase()}'
      : 'Guest';

  // Participants show designation + company + email; everyone else shows
  // the check-in date (+ company, if on file).
  final String secondLine;
  if (isParticipant) {
    final parts = [
      guest.designation,
      guest.companyName,
      guest.email,
    ].where((s) => s.isNotEmpty);
    secondLine = parts.isNotEmpty ? parts.join(' • ') : 'No details on file';
  } else {
    secondLine = guest.companyName.isNotEmpty
        ? '$dateString • ${guest.companyName}'
        : dateString;
  }

  return ListTile(
    isThreeLine: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    leading: CircleAvatar(
      backgroundColor: guest.role.toLowerCase() == 'participant'
          ? Colors.deepPurple
          : Colors.green,
      child: const Icon(Icons.how_to_reg, color: Colors.white, size: 20),
    ),
    title: RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 15, color: Colors.black87),
        children: [
          TextSpan(
            text: '$roleDisplay ',
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
          TextSpan(
            text: guest.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Checked into ${events?.title}',
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            secondLine,
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
    trailing: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          timeString,
          style: const TextStyle(
            color: Colors.green,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Checked In',
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ],
    ),
  );
}
