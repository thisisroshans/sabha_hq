import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/check_in_controller.dart';

class CheckInScreen extends ConsumerStatefulWidget {
  final String? eventId;

  const CheckInScreen({super.key, required this.eventId});

  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate() && widget.eventId != null) {
      ref
          .read(checkInControllerProvider.notifier)
          .submitCheckIn(widget.eventId!, _emailController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Failsafe if they somehow navigated here without a QR code
    if (widget.eventId == null || widget.eventId!.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Invalid QR Code. Missing Event ID.')),
      );
    }

    final checkInState = ref.watch(checkInControllerProvider);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 20),
              ],
            ),
            child: checkInState.when(
              // -------------------------------------------------------------
              // SUCCESS STATE: Replaces the form with a welcome message
              // -------------------------------------------------------------
              data: (attendee) {
                if (attendee != null) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 80,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Welcome, ${attendee.name}!',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text('You are successfully checked in.'),
                      const SizedBox(height: 32),
                      OutlinedButton(
                        onPressed: () {
                          // Allow another person to use the same device to check in
                          ref.invalidate(checkInControllerProvider);
                          _emailController.clear();
                        },
                        child: const Text('Check in someone else'),
                      ),
                    ],
                  );
                }

                // -------------------------------------------------------------
                // INPUT FORM STATE
                // -------------------------------------------------------------
                return Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.qr_code_scanner,
                        size: 64,
                        color: Colors.deepPurple,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Event Check-In',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Enter your registered email to verify your ticket.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 32),

                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email Address',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.email),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) =>
                            value != null && value.contains('@')
                            ? null
                            : 'Enter a valid email',
                      ),
                      const SizedBox(height: 24),

                      ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text(
                          'Check In',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                );
              },

              // -------------------------------------------------------------
              // ERROR STATE
              // -------------------------------------------------------------
              error: (error, stack) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    error.toString().replaceAll('Exception: ', ''),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red, fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => ref.invalidate(checkInControllerProvider),
                    child: const Text('Try Again'),
                  ),
                ],
              ),

              // -------------------------------------------------------------
              // LOADING STATE
              // -------------------------------------------------------------
              loading: () => const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
