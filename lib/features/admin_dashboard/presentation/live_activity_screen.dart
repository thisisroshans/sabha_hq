import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/live_feed_providers.dart';
import 'package:intl/intl.dart'; // Add this to pubspec.yaml if you want nice time formatting

class LiveActivityScreen extends ConsumerWidget {
  const LiveActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveFeedState = ref.watch(liveActivityStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(
              Icons.sensors,
              color: Colors.redAccent,
            ), // A little "Live" indicator
            SizedBox(width: 8),
            Text('Live Check-In Feed'),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: liveFeedState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Error loading feed: $e')),
          data: (attendees) {
            if (attendees.isEmpty) {
              return const Center(
                child: Text(
                  'Waiting for check-ins...',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              );
            }

            return Card(
              child: ListView.separated(
                itemCount: attendees.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final guest = attendees[index];
                  // Format the time nicely (e.g., 2:30 PM)
                  final timeString = guest.checkInTime != null
                      ? DateFormat('h:mm a').format(guest.checkInTime!)
                      : 'Just now';

                  return ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.green,
                      child: Icon(Icons.check, color: Colors.white),
                    ),
                    title: Text(
                      guest.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text(
                      '${guest.phone} • ${guest.role.toUpperCase()}',
                    ),
                    trailing: Text(
                      timeString,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
