import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sabha_hq/core/models/attendee.dart';
import 'package:sabha_hq/core/models/event.dart';
import 'package:sabha_hq/core/models/schedule_item.dart';
import 'package:sabha_hq/core/utils/color_utils.dart';
import 'package:sabha_hq/features/admin_dashboard/application/live_feed_providers.dart';
import 'package:sabha_hq/features/admin_events/application/event_providers.dart';
import 'package:sabha_hq/features/admin_events/application/schedule_providers.dart';
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

    // 2. Navigate back to the check-in phone-entry screen FIRST, via
    //    go_router (not a raw Navigator push) so the route/redirect logic
    //    stays in sync — this lands back on "enter your phone number",
    //    never on the admin login screen.
    //
    //    This must happen before signing out below. This screen's
    //    Firestore streams are scoped by the guest's auth claims
    //    (isGuestSessionFor in firestore.rules); if we sign out while
    //    still mounted here, those listeners re-evaluate against the
    //    now-signed-out user and briefly surface a raw
    //    "permission-denied" error screen before the route change lands.
    //    Navigating away first unmounts the listeners before the token
    //    disappears, so the guest never sees that flash.
    context.go('/check-in?orgId=$orgId&eventId=$eventId');

    // 3. Sign this guest out of Firebase Auth so the shared kiosk device
    //    doesn't carry their identity (or event-scoped claim) into the
    //    next person's check-in.
    ref.read(guestAuthControllerProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveFeedState = ref.watch(
      eventAttendeesStreamProvider((orgId: orgId, eventId: eventId)),
    );
    final eventState = ref.watch(
      eventForGuestProvider((orgId: orgId, eventId: eventId)),
    );
    final scheduleState = ref.watch(
      scheduleItemsForGuestProvider((orgId: orgId, eventId: eventId)),
    );

    // Event.branding wired up (task #8) — was written by
    // edit_event_screen.dart but never read anywhere before this.
    final event = eventState.valueOrNull;
    final themeColor =
        parseHexColor(event?.branding['primaryColor'] as String?) ??
        const Color(0xFFc51f43);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Event'),
        backgroundColor: themeColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Give Feedback',
            icon: const Icon(Icons.rate_review_outlined),
            onPressed: () =>
                context.go('/feedback?orgId=$orgId&eventId=$eventId'),
          ),
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
                              // AGENDA — "happening now" banner (task #8).
                              // schedule_item.dart existed fully modelled
                              // with zero UI until this task.
                              scheduleState.when(
                                loading: () => const SizedBox.shrink(),
                                error: (e, st) => const SizedBox.shrink(),
                                data: (items) => _buildAgendaBanner(
                                  context: context,
                                  items: items,
                                  themeColor: themeColor,
                                ),
                              ),
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
                                    child: Padding(
                                      padding: const EdgeInsets.all(24.0),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.wifi_off_rounded,
                                            size: 40,
                                            color: Colors.grey[400],
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            "Couldn't load the live feed.",
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Check your connection and try again.',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[500],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  data: (attendees) {
                                    return _buildColumn(
                                      title: 'Checked In (${attendees.length})',
                                      icon: Icons.how_to_reg,
                                      color: themeColor,
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

Widget _buildAgendaBanner({
  required BuildContext context,
  required List<ScheduleItem> items,
  required Color themeColor,
}) {
  if (items.isEmpty) return const SizedBox.shrink();

  final now = DateTime.now();
  final current = items
      .where((i) => now.isAfter(i.startTime) && now.isBefore(i.endTime))
      .firstOrNull;
  final next = items.where((i) => i.startTime.isAfter(now)).firstOrNull;
  final highlight = current ?? next;
  if (highlight == null) return const SizedBox.shrink();

  final timeFmt = DateFormat('h:mm a');
  final label = current != null ? 'NOW' : 'NEXT';

  return GestureDetector(
    onTap: () => _showFullAgenda(context, items, themeColor),
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: themeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: themeColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: themeColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${highlight.title} • ${timeFmt.format(highlight.startTime)}',
              style: TextStyle(fontWeight: FontWeight.w600, color: themeColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(Icons.chevron_right, color: themeColor),
        ],
      ),
    ),
  );
}

void _showFullAgenda(
  BuildContext context,
  List<ScheduleItem> items,
  Color themeColor,
) {
  final timeFmt = DateFormat('h:mm a');
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.6,
        expand: false,
        builder: (context, scrollController) {
          return ListView.separated(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: items.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Agenda',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: themeColor,
                    ),
                  ),
                );
              }
              final item = items[index - 1];
              return ListTile(
                title: Text(item.title),
                subtitle: Text(
                  '${timeFmt.format(item.startTime)} – ${timeFmt.format(item.endTime)}'
                  '${item.speaker != null ? ' • ${item.speaker}' : ''}',
                ),
              );
            },
          );
        },
      );
    },
  );
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
          color: color.withValues(alpha: 0.1),
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
