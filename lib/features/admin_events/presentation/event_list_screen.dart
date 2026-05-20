import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../application/event_providers.dart';

class EventListScreen extends ConsumerWidget {
  const EventListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the live stream of events from Firestore
    final eventsState = ref.watch(eventListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Event Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create Event',
            onPressed: () => context.go('/dashboard/events/create'),
          ),
        ],
      ),
      // .when() forces you to handle all three states safely
      body: eventsState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
        data: (events) {
          if (events.isEmpty) {
            return const Center(child: Text('No events found. Create one!'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = events[index];
              final dateStr =
                  '${event.date.month}/${event.date.day}/${event.date.year}';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text(
                    event.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('$dateStr • ${event.location}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // View event details / QR code link
                      IconButton(
                        icon: const Icon(
                          Icons.qr_code,
                          color: Colors.deepPurple,
                        ),
                        onPressed: () {
                          // Note: In Phase 4 we will generate the actual QR code here
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Attendee Link: /check-in?eventId=${event.id}',
                              ),
                            ),
                          );
                        },
                      ),
                      // Delete event
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          ref
                              .read(eventActionControllerProvider.notifier)
                              .deleteEvent(event.id);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/dashboard/events/create'),
        icon: const Icon(Icons.add),
        label: const Text('New Event'),
      ),
    );
  }
}
