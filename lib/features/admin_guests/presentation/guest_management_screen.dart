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

    // Watch the action state to show loading spinners during imports
    final actionState = ref.watch(guestActionControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Guest Directory')),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. EVENT FILTER DROPDOWN & IMPORT BUTTON
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: eventsState.when(
                        loading: () => const CircularProgressIndicator(),
                        error: (e, _) => Text('Error: $e'),
                        data: (events) {
                          if (events.isEmpty)
                            return const Text('Create an event first.');

                          // 1. SAFETY CHECK: Does the selected ID actually exist in the current list?
                          final bool isValidSelection =
                              selectedEventId != null &&
                              events.any((e) => e.id == selectedEventId);

                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            // 2. If the ID is null OR invalid, reset it to the first valid event
                            if ((selectedEventId == null ||
                                    !isValidSelection) &&
                                events.isNotEmpty) {
                              ref
                                  .read(selectedEventFilterProvider.notifier)
                                  .state = events
                                  .first
                                  .id;
                            }
                          });

                          return DropdownButtonFormField<String>(
                            // 3. Only pass the ID to the dropdown if we know it's in the list
                            value: isValidSelection ? selectedEventId : null,
                            decoration: const InputDecoration(
                              labelText: 'Filter by Event',
                              border: OutlineInputBorder(),
                            ),
                            items: events
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.id,
                                    child: Text(e.title),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) =>
                                ref
                                        .read(
                                          selectedEventFilterProvider.notifier,
                                        )
                                        .state =
                                    val,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 16),

                    // ADD THIS: Bulk Import Button
                    if (selectedEventId != null)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Import CSV'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 20,
                          ),
                        ),
                        onPressed: actionState.isLoading
                            ? null
                            : () async {
                                final count = await ref
                                    .read(
                                      guestActionControllerProvider.notifier,
                                    )
                                    .importGuestsFromCsv();

                                if (!context.mounted) return;

                                if (count > 0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Successfully imported $count guests!',
                                      ),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                } else if (count == -1) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Error parsing CSV file.'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              },
                      ),
                  ],
                ),
                const SizedBox(height: 24),

                // 2. GUEST DATA TABLE (Keep your existing table code here)
                Expanded(
                  child: selectedEventId == null
                      ? const Center(
                          child: Text('Select an event to view guests'),
                        )
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
                                        color: Colors.white,
                                      ),
                                    ),
                                    title: Text(
                                      guest.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    // Modified to show Phone instead of Email
                                    subtitle: Text(
                                      '${guest.phone} • ${guest.role.toUpperCase()}',
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                      ),
                                      onPressed: () => ref
                                          .read(
                                            guestActionControllerProvider
                                                .notifier,
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

          // ADD THIS: Global Loading Overlay
          if (actionState.isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Card(
                  margin: EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Processing File...'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: selectedEventId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAddGuestDialog(
                context,
                ref,
              ), // Assuming you have this defined
              icon: const Icon(Icons.person_add),
              label: const Text('Add Single Guest'),
            ),
    );
  }
}
