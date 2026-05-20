import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/guest_providers.dart';
import '../../admin_events/application/event_providers.dart';

class GuestManagementScreen extends ConsumerWidget {
  const GuestManagementScreen({super.key});

  void _showAddGuestDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    String selectedRole = 'guest';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Attendee'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Full Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email Address'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Phone Number'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: selectedRole,
              decoration: const InputDecoration(labelText: 'Role'),
              items: const [
                DropdownMenuItem(value: 'guest', child: Text('Guest')),
                DropdownMenuItem(
                  value: 'participant',
                  child: Text('Participant'),
                ),
              ],
              onChanged: (val) => selectedRole = val!,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final success = await ref
                  .read(guestActionControllerProvider.notifier)
                  .addGuest(
                    name: nameController.text.trim(),
                    email: emailController.text.trim().toLowerCase(),
                    phone: phoneController.text.trim(),
                    role: selectedRole,
                  );
              if (success && context.mounted) Navigator.pop(context);
            },
            child: const Text('Add Attendee'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsState = ref.watch(eventListProvider);
    final selectedEventId = ref.watch(selectedEventFilterProvider);
    final guestsState = ref.watch(guestListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Guest Directory')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. EVENT FILTER DROPDOWN
            eventsState.when(
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => Text('Error loading events: $e'),
              data: (events) {
                if (events.isEmpty) return const Text('Create an event first.');

                // Auto-select first event if none selected
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (selectedEventId == null && events.isNotEmpty) {
                    ref.read(selectedEventFilterProvider.notifier).state =
                        events.first.id;
                  }
                });

                return DropdownButtonFormField<String>(
                  initialValue: selectedEventId,
                  decoration: const InputDecoration(
                    labelText: 'Filter by Event',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.event),
                  ),
                  items: events
                      .map(
                        (e) =>
                            DropdownMenuItem(value: e.id, child: Text(e.title)),
                      )
                      .toList(),
                  onChanged: (val) =>
                      ref.read(selectedEventFilterProvider.notifier).state =
                          val,
                );
              },
            ),
            const SizedBox(height: 24),

            // 2. GUEST DATA TABLE
            Expanded(
              child: selectedEventId == null
                  ? const Center(child: Text('Select an event to view guests'))
                  : guestsState.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(child: Text('Error: $e')),
                      data: (guests) {
                        if (guests.isEmpty) {
                          return const Center(
                            child: Text('No guests added yet.'),
                          );
                        }
                        return Card(
                          child: ListView.separated(
                            itemCount: guests.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final guest = guests[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: guest.isCheckedIn
                                      ? Colors.green
                                      : Colors.grey[300],
                                  child: Icon(
                                    guest.isCheckedIn
                                        ? Icons.check
                                        : Icons.person,
                                    color: guest.isCheckedIn
                                        ? Colors.white
                                        : Colors.grey[700],
                                  ),
                                ),
                                title: Text(
                                  guest.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  '${guest.email} • ${guest.role.toUpperCase()}',
                                ),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => ref
                                      .read(
                                        guestActionControllerProvider.notifier,
                                      )
                                      .removeGuest(guest.id),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: selectedEventId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAddGuestDialog(context, ref),
              icon: const Icon(Icons.person_add),
              label: const Text('Add Guest'),
            ),
    );
  }
}
