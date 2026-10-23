import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/models/attendee.dart';
import 'package:sabha_hq/core/utils/file_saver.dart';

import '../../admin_events/application/event_providers.dart';
import '../application/guest_providers.dart';

class GuestManagementScreen extends ConsumerWidget {
  const GuestManagementScreen({super.key});

  /// Browser download on web, native share sheet on Android/iOS — see
  /// file_saver.dart. (This used to call package:web directly, which
  /// doesn't compile for Android/iOS at all.)
  Future<void> _saveAndShareCsv({
    required BuildContext context,
    required String csvContent,
    required String fileName,
  }) {
    return saveFile(
      context: context,
      bytes: Uint8List.fromList(utf8.encode(csvContent)),
      fileName: fileName,
      mimeType: 'text/csv',
    );
  }

  Future<void> _downloadCsvTemplate(BuildContext context) async {
    final List<List<dynamic>> csvData = [
      [
        'Name',
        'Phone',
        'Email',
        'Role',
        'Company',
        'Designation',
        'Industry',
        'Checked In',
        'Check-In Time',
      ],
    ];

    final String csvContent = Csv().encode(csvData);

    await _saveAndShareCsv(
      context: context,
      csvContent: csvContent,
      fileName: 'sabha_attendee_template.csv',
    );

    // The share sheet is its own confirmation on mobile.
    if (kIsWeb && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Template downloaded!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _exportGuestsToCsv(BuildContext context, List<Attendee> guests) async {
    if (guests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No attendees to export!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final List<List<dynamic>> csvData = [
        [
          'Name',
          'Phone',
          'Email',
          'Role',
          'Company',
          'Designation',
          'Industry',
          'Checked In',
          'Check-In Time',
        ],
        ...guests.map(
          (g) => [
            g.name,
            g.phone,
            g.email,
            // Exported as the label admins see (Mover/Pitcher);
            // importGuestsFromCsv reads both these and the stored values
            // back, so an export still round-trips. See AttendeeRole.
            g.roleLabel,
            g.companyName,
            g.designation,
            g.industry,
            g.isCheckedIn ? 'Yes' : 'No',
            g.checkInTime?.toIso8601String() ?? 'N/A',
          ],
        ),
      ];

      final String csvContent = Csv().encode(csvData);

      await _saveAndShareCsv(
        context: context,
        csvContent: csvContent,
        fileName: 'sabha_attendee_export.csv',
      );

      if (kIsWeb && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Export successful!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAddGuestDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    String selectedRole = AttendeeRole.mover;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Attendee'),
        content: SingleChildScrollView(
          child: Column(
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
              const SizedBox(height: 8),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: 'Phone Number'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [
                  for (final role in const [
                    AttendeeRole.mover,
                    AttendeeRole.pitcher,
                  ])
                    DropdownMenuItem(
                      value: role,
                      child: Text(AttendeeRole.label(role)),
                    ),
                ],
                onChanged: (val) => selectedRole = val!,
              ),
            ],
          ),
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
    final actionState = ref.watch(guestActionControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendee Directory'),
        actions: [
          // On mobile screens, move quick CSV actions to the AppBar overflow menu
          if (selectedEventId != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                switch (value) {
                  case 'template':
                    _downloadCsvTemplate(context);
                    break;
                  case 'export':
                    guestsState.maybeWhen(
                      data: (guests) => _exportGuestsToCsv(context, guests),
                      orElse: () {},
                    );
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'template',
                  child: Row(
                    children: [
                      Icon(Icons.download, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('Get Template'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'export',
                  child: Row(
                    children: [
                      Icon(Icons.file_download, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Export List'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0), // Reduced for mobile
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. RESPONSIVE CONTROLS HEADER
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 600;

                    // Event Dropdown Widget
                    final dropdownWidget = eventsState.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('Error loading events: $e'),
                      data: (events) {
                        if (events.isEmpty) {
                          return const Text('Create an event first.');
                        }

                        final bool isValidSelection =
                            selectedEventId != null &&
                            events.any((e) => e.id == selectedEventId);

                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if ((selectedEventId == null || !isValidSelection) &&
                              events.isNotEmpty) {
                            ref
                                    .read(selectedEventFilterProvider.notifier)
                                    .state =
                                events.first.id;
                          }
                        });

                        return DropdownButtonFormField<String>(
                          // Without this the field sizes itself to the
                          // longest event title and overflows on phones.
                          isExpanded: true,
                          initialValue: isValidSelection
                              ? selectedEventId
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Filter by Event',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          items: events
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.id,
                                  child: Text(
                                    e.title,
                                    overflow: TextOverflow.ellipsis,
                                  ),
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
                    );

                    // Import CSV Button
                    final importButton = ElevatedButton.icon(
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Import CSV'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      onPressed:
                          (actionState.isLoading ||
                              selectedEventId == null ||
                              selectedEventId == 'all')
                          ? null
                          : () async {
                              final count = await ref
                                  .read(guestActionControllerProvider.notifier)
                                  .importGuestsFromCsv();

                              if (!context.mounted) return;

                              if (count > 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Successfully imported $count attendees!',
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
                    );

                    if (isMobile) {
                      // Vertical layout for small mobile screens
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          dropdownWidget,
                          if (selectedEventId != null) ...[
                            const SizedBox(height: 12),
                            importButton,
                          ],
                        ],
                      );
                    }

                    // Horizontal layout for tablets/desktops
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(flex: 2, child: dropdownWidget),
                        if (selectedEventId != null) ...[
                          const SizedBox(width: 12),
                          TextButton.icon(
                            icon: const Icon(Icons.download),
                            label: const Text('Template'),
                            onPressed: () => _downloadCsvTemplate(context),
                          ),
                          const SizedBox(width: 8),
                          guestsState.maybeWhen(
                            data: (guests) => OutlinedButton.icon(
                              icon: const Icon(Icons.file_download),
                              label: const Text('Export'),
                              onPressed: () =>
                                  _exportGuestsToCsv(context, guests),
                            ),
                            orElse: () => const SizedBox.shrink(),
                          ),
                          const SizedBox(width: 8),
                          importButton,
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                // 2. GUEST DATA LIST
                Expanded(
                  child: selectedEventId == null
                      ? const Center(
                          child: Text('Select an event to view attendees'),
                        )
                      : guestsState.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Center(child: Text('Error: $e')),
                          data: (guests) {
                            if (guests.isEmpty) {
                              return const Center(
                                child: Text('No attendees added yet.'),
                              );
                            }

                            return Card(
                              margin: EdgeInsets.zero,
                              child: ListView.separated(
                                itemCount: guests.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final guest = guests[index];
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
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
                                    subtitle: Text(
                                      '${guest.phone} • ${guest.roleLabel.toUpperCase()}',
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.redAccent,
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

          // 3. GLOBAL LOADING OVERLAY
          if (actionState.isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Card(
                  margin: EdgeInsets.all(32),
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
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
            ),
        ],
      ),
      floatingActionButton: selectedEventId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAddGuestDialog(context, ref),
              icon: const Icon(Icons.person_add),
              label: const Text('Add Attendee'),
            ),
    );
  }
}
