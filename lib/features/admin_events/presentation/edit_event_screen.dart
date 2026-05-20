import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sabha_hq/core/models/event.dart';
import '../application/event_providers.dart';

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
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.event.title);
    _locationController = TextEditingController(text: widget.event.location);
    // Extract branding color or default to Purple
    final primaryColor = widget.event.branding['primaryColor'] ?? '#673AB7';
    _colorController = TextEditingController(text: primaryColor);
    _selectedDate = widget.event.date;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _colorController.dispose();
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
          'logoUrl': widget.event.branding['logoUrl'] ?? '',
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

  @override
  Widget build(BuildContext context) {
    final actionState = ref.watch(eventActionControllerProvider);

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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
