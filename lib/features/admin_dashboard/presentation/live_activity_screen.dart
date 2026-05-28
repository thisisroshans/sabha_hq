import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/attendee.dart';
import '../application/live_feed_providers.dart';
import '../../admin_events/application/event_providers.dart';

class LiveActivityScreen extends ConsumerWidget {
  const LiveActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveFeedState = ref.watch(liveActivityStreamProvider);
    final eventsState = ref.watch(eventListProvider);
    final selectedFilter = ref.watch(liveFeedEventFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.sensors, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Live Check-In Feed'),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // EVENT FILTER DROPDOWN
            SizedBox(
              width: 400,
              child: eventsState.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error loading events: $e'),
                data: (events) {
                  final dropdownItems = [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All Events (Global)'),
                    ),
                    ...events.map(
                      (e) =>
                          DropdownMenuItem(value: e.id, child: Text(e.title)),
                    ),
                  ];

                  return DropdownButtonFormField<String>(
                    initialValue:
                        selectedFilter == 'all' ||
                            events.any((e) => e.id == selectedFilter)
                        ? selectedFilter
                        : 'all',
                    decoration: const InputDecoration(
                      labelText: 'Filter Feed by Event',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.filter_list),
                    ),
                    items: dropdownItems,
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(liveFeedEventFilterProvider.notifier).state =
                            val;
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // SPLIT LIVE FEED LIST
            Expanded(
              child: liveFeedState.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text('Error loading feed: $e')),
                data: (attendees) {
                  // Safely extract the events list to match IDs to titles
                  final events = eventsState.valueOrNull ?? [];

                  // Split the attendees into two separate lists
                  final guests = attendees
                      .where((a) => a.role.toLowerCase() != 'participant')
                      .toList();
                  final participants = attendees
                      .where((a) => a.role.toLowerCase() == 'participant')
                      .toList();

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // LEFT HALF: GUESTS
                      Expanded(
                        child: _buildColumn(
                          title: 'Guests (${guests.length})',
                          icon: Icons.person,
                          color: Colors.green,
                          attendees: guests,
                          events: events,
                        ),
                      ),

                      const SizedBox(width: 24), // Spacing between columns
                      // RIGHT HALF: PARTICIPANTS
                      Expanded(
                        child: _buildColumn(
                          title: 'Participants (${participants.length})',
                          icon: Icons.stars,
                          color: Colors.deepPurple,
                          attendees: participants,
                          events: events,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to build each column (Guests or Participants)
  Widget _buildColumn({
    required String title,
    required IconData icon,
    required Color color,
    required List<Attendee> attendees,
    required List<dynamic> events, // Or List<Event> if imported properly
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
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
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
                  child: ListView.separated(
                    itemCount: attendees.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      return _buildAttendeeTile(attendees[index], events);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // Helper method extracted from your previous code to keep things DRY
  Widget _buildAttendeeTile(Attendee guest, List<dynamic> events) {
    // 1. Format Time & Date
    final timeString = guest.checkInTime != null
        ? DateFormat('h:mm a').format(guest.checkInTime!)
        : 'Just now';
    final dateString = guest.checkInTime != null
        ? DateFormat('MMM d, yyyy').format(guest.checkInTime!)
        : 'Today';

    // 2. Get the Event Name
    final matchingEvent = events
        .where((e) => e.id == guest.eventId)
        .firstOrNull;
    final eventTitle = matchingEvent?.title ?? 'Unknown Event';

    // 3. Format the Role string properly
    final roleDisplay = guest.role.isNotEmpty
        ? '${guest.role[0].toUpperCase()}${guest.role.substring(1).toLowerCase()}'
        : 'Guest';

    return ListTile(
      isThreeLine: true,
      leading: CircleAvatar(
        backgroundColor: guest.role.toLowerCase() == 'participant'
            ? Colors.deepPurple
            : Colors.green,
        child: const Icon(Icons.how_to_reg, color: Colors.white),
      ),
      title: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 16, color: Colors.black87),
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
              'Checked into $eventTitle',
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              guest.companyName.isNotEmpty
                  ? '$dateString • ${guest.companyName} (${guest.phone})'
                  : '$dateString • ${guest.phone}',
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
              fontSize: 14,
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
}
