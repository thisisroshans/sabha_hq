import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sabha_hq/core/models/event.dart';
import 'package:sabha_hq/core/models/schedule_item.dart';
import '../application/event_providers.dart';
import '../application/schedule_providers.dart';

class EditEventScreen extends ConsumerStatefulWidget {
  final Event event;
  const EditEventScreen({super.key, required this.event});

  @override
  ConsumerState<EditEventScreen> createState() => _EditEventScreenState();
}

class _EditEventScreenState extends ConsumerState<EditEventScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _locationController;
  late TextEditingController _colorController;
  late TextEditingController _logoUrlController;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.event.title);
    _locationController = TextEditingController(text: widget.event.location);
    // Extract branding color or default to Purple
    final primaryColor = widget.event.branding['primaryColor'] ?? '#673AB7';
    _colorController = TextEditingController(text: primaryColor);
    _logoUrlController = TextEditingController(
      text: (widget.event.branding['logoUrl'] as String?) ?? '',
    );
    _selectedDate = widget.event.date;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _colorController.dispose();
    _logoUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (date != null) setState(() => _selectedDate = date);
  }

  Future<void> _submit() async {
    if (_formKey.currentState!.validate()) {
      final updatedEvent = widget.event.copyWith(
        title: _titleController.text.trim(),
        location: _locationController.text.trim(),
        date: _selectedDate,
        branding: {
          'primaryColor': _colorController.text.trim(),
          'logoUrl': _logoUrlController.text.trim(),
        },
      );

      // Wait for the boolean result
      final success = await ref
          .read(eventActionControllerProvider.notifier)
          .updateExistingEvent(updatedEvent);

      if (!mounted) return;

      if (success) {
        context.pop(); // Pop back to the list
      } else {
        final errorState = ref.read(eventActionControllerProvider).error;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $errorState'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showScheduleItemDialog({ScheduleItem? existing}) async {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final speakerController = TextEditingController(text: existing?.speaker ?? '');
    final descriptionController = TextEditingController(text: existing?.description ?? '');
    DateTime start = existing?.startTime ?? widget.event.date;
    DateTime end = existing?.endTime ?? start.add(const Duration(hours: 1));

    Future<void> pickDateTime(bool isStart, void Function(void Function()) setDialogState) async {
      final base = isStart ? start : end;
      final date = await showDatePicker(
        context: context,
        initialDate: base,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      );
      if (date == null || !mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(base),
      );
      if (time == null) return;
      final combined = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      setDialogState(() {
        if (isStart) {
          start = combined;
        } else {
          end = combined;
        }
      });
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final fmt = DateFormat('MMM d, h:mm a');
          return AlertDialog(
            title: Text(existing == null ? 'Add Agenda Item' : 'Edit Agenda Item'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: 'Title *'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: speakerController,
                    decoration: const InputDecoration(labelText: 'Speaker (optional)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: 'Description (optional)'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Starts'),
                    subtitle: Text(fmt.format(start)),
                    trailing: const Icon(Icons.edit_calendar),
                    onTap: () => pickDateTime(true, setDialogState),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ends'),
                    subtitle: Text(fmt.format(end)),
                    trailing: const Icon(Icons.edit_calendar),
                    onTap: () => pickDateTime(false, setDialogState),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final title = titleController.text.trim();
                  if (title.isEmpty) return;
                  if (!end.isAfter(start)) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('End time must be after start time.')),
                    );
                    return;
                  }

                  final item = ScheduleItem(
                    id: existing?.id ?? '',
                    eventId: widget.event.id,
                    title: title,
                    startTime: start,
                    endTime: end,
                    speaker: speakerController.text.trim().isEmpty ? null : speakerController.text.trim(),
                    description: descriptionController.text.trim().isEmpty
                        ? null
                        : descriptionController.text.trim(),
                  );

                  final controller = ref.read(scheduleActionControllerProvider.notifier);
                  final success = existing == null
                      ? await controller.addItem(widget.event.id, item)
                      : await controller.updateItem(widget.event.id, item);

                  if (!dialogContext.mounted) return;
                  if (success) {
                    Navigator.pop(dialogContext);
                  } else {
                    final error = ref.read(scheduleActionControllerProvider).error;
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('Error: $error')),
                    );
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actionState = ref.watch(eventActionControllerProvider);
    final scheduleState = ref.watch(scheduleItemsProvider(widget.event.id));

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Event & Branding')),
      body: Center(
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                const Text(
                  'Event Details',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Event Title',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value != null && value.isNotEmpty ? null : 'Required',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _locationController,
                  decoration: const InputDecoration(
                    labelText: 'Location / Venue',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value != null && value.isNotEmpty ? null : 'Required',
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Date: ${_selectedDate.month}/${_selectedDate.day}/${_selectedDate.year}',
                  ),
                  trailing: ElevatedButton(
                    onPressed: _pickDate,
                    child: const Text('Change Date'),
                  ),
                ),
                const Divider(height: 48),
                const Text(
                  'Attendee App Branding',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Shown on the public check-in screen for this event.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _colorController,
                  decoration: const InputDecoration(
                    labelText: 'Primary Color (Hex Code)',
                    border: OutlineInputBorder(),
                    hintText: '#FF0000',
                  ),
                  validator: (value) => value != null && value.startsWith('#')
                      ? null
                      : 'Must be a valid hex code (e.g. #FF0000)',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _logoUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Logo URL (optional)',
                    border: OutlineInputBorder(),
                    hintText: 'https://...',
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: actionState.isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: actionState.isLoading
                      ? const CircularProgressIndicator()
                      : const Text('Update Event'),
                ),

                const Divider(height: 48),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Agenda',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    TextButton.icon(
                      onPressed: () => _showScheduleItemDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Item'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                scheduleState.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Text('Error loading agenda: $e'),
                  data: (items) {
                    if (items.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No agenda items yet.',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      );
                    }
                    final timeFmt = DateFormat('h:mm a');
                    return Column(
                      children: items.map((item) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(item.title),
                            subtitle: Text(
                              '${timeFmt.format(item.startTime)} – ${timeFmt.format(item.endTime)}'
                              '${item.speaker != null ? ' • ${item.speaker}' : ''}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 20),
                                  onPressed: () => _showScheduleItemDialog(existing: item),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                  onPressed: () => ref
                                      .read(scheduleActionControllerProvider.notifier)
                                      .deleteItem(widget.event.id, item.id),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
