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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 800;

          return Padding(
            padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // EVENT FILTER DROPDOWN
                ConstrainedBox(
                  // Use constraints instead of fixed SizedBox width
                  constraints: const BoxConstraints(maxWidth: 400),
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
                          (e) => DropdownMenuItem(
                            value: e.id,
                            child: Text(e.title),
                          ),
                        ),
                      ];

                      return DropdownButtonFormField<String>(
                        isExpanded:
                            true, // Prevents text overflow inside dropdown
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
                            ref
                                    .read(liveFeedEventFilterProvider.notifier)
                                    .state =
                                val;
                          }
                        },
                      );
                    },
                  ),
                ),
                SizedBox(height: isMobile ? 16 : 24),

                // SPLIT LIVE FEED LIST
                Expanded(
                  child: liveFeedState.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, st) =>
                        Center(child: Text('Error loading feed: $e')),
                    data: (attendees) {
                      final events = eventsState.valueOrNull ?? [];

                      final movers = attendees
                          .where((a) => !a.isPitcher)
                          .toList();
                      final pitchers = attendees
                          .where((a) => a.isPitcher)
                          .toList();

                      // Flex changes direction based on screen width
                      return Flex(
                        direction: isMobile ? Axis.vertical : Axis.horizontal,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // MOVERS (stored role: 'guest')
                          Expanded(
                            child: _buildColumn(
                              title: 'Movers (${movers.length})',
                              icon: Icons.person,
                              color: Colors.green,
                              attendees: movers,
                              events: events,
                              ref: ref,
                            ),
                          ),

                          SizedBox(
                            width: isMobile ? 0 : 24,
                            height: isMobile ? 24 : 0,
                          ),

                          // PITCHERS (stored role: 'participant')
                          Expanded(
                            child: _buildColumn(
                              title: 'Pitchers (${pitchers.length})',
                              icon: Icons.stars,
                              color: Colors.deepPurple,
                              attendees: pitchers,
                              events: events,
                              ref: ref,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildColumn({
    required String title,
    required IconData icon,
    required Color color,
    required List<Attendee> attendees,
    required List<dynamic> events,
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

  Widget _buildAttendeeTile(Attendee guest, List<dynamic> events) {
    final timeString = guest.checkInTime != null
        ? DateFormat('h:mm a').format(guest.checkInTime!)
        : 'Just now';
    final dateString = guest.checkInTime != null
        ? DateFormat('MMM d, yyyy').format(guest.checkInTime!)
        : 'Today';

    final matchingEvent = events
        .where((e) => e.id == guest.eventId)
        .firstOrNull;
    final eventTitle = matchingEvent?.title ?? 'Unknown Event';

    // Name tag — "Mover"/"Pitcher", see AttendeeRole.
    final roleDisplay = guest.roleLabel;

    return ListTile(
      isThreeLine: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: guest.isPitcher ? Colors.deepPurple : Colors.green,
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
              'Checked into $eventTitle',
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              guest.companyName.isNotEmpty
                  ? '$dateString • ${guest.companyName} (${guest.phone})'
                  : '$dateString • ${guest.phone}',
              style: const TextStyle(fontSize: 12),
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
}
