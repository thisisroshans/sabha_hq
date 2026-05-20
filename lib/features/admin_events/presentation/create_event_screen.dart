import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../application/event_providers.dart';

class CreateEventScreen extends ConsumerStatefulWidget {
  const CreateEventScreen({super.key});

  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  DateTime? _selectedDate;

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _submit() async {
    if (_formKey.currentState!.validate() && _selectedDate != null) {
      // Wait for the boolean result
      final success = await ref
          .read(eventActionControllerProvider.notifier)
          .createNewEvent(
            title: _titleController.text.trim(),
            location: _locationController.text.trim(),
            date: _selectedDate!,
          );

      if (!mounted) return;

      if (success) {
        // If successful, navigate away (this destroys the screen and clears the form)
        context.go('/dashboard/events');
      } else {
        // If it failed, show the error message so you aren't guessing
        final errorState = ref.read(eventActionControllerProvider).error;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $errorState'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else if (_selectedDate == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a date')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final actionState = ref.watch(eventActionControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Create New Event')),
      body: Center(
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                    _selectedDate == null
                        ? 'No date selected'
                        : 'Date: ${_selectedDate!.month}/${_selectedDate!.day}/${_selectedDate!.year}',
                  ),
                  trailing: ElevatedButton(
                    onPressed: _pickDate,
                    child: const Text('Select Date'),
                  ),
                ),
                const SizedBox(height: 32),

                ElevatedButton(
                  onPressed: actionState.isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: actionState.isLoading
                      ? const CircularProgressIndicator()
                      : const Text('Save Event'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
