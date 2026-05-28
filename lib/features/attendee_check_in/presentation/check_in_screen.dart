import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/staff_check_in_controller.dart';

class CheckInScreen extends ConsumerStatefulWidget {
  final String? eventId;
  const CheckInScreen({super.key, required this.eventId});

  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen> {
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();

  // Focus nodes allow us to keep the cursor active without mouse clicks
  final _phoneFocus = FocusNode();
  final _nameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Auto-focus the phone field when the screen loads
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _phoneFocus.requestFocus(),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    _phoneFocus.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _resetForm() {
    _phoneController.clear();
    _nameController.clear();
    ref.read(staffCheckInProvider.notifier).reset();
    _phoneFocus.requestFocus(); // Snap focus back to phone input for next guest
  }

  @override
  Widget build(BuildContext context) {
    if (widget.eventId == null) {
      return const Scaffold(
        body: Center(child: Text('Invalid Link. Missing Event ID.')),
      );
    }

    final uiState = ref.watch(staffCheckInProvider);
    final notifier = ref.read(staffCheckInProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Staff Check-In Terminal'),
        backgroundColor: const Color(0xFFc51f43),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20)],
          ),
          child: _buildBody(uiState, notifier, widget.eventId!),
        ),
      ),
    );
  }

  Widget _buildBody(
    StaffCheckInState uiState,
    StaffCheckInController notifier,
    String eventId,
  ) {
    // -------------------------------------------------------------
    // SUCCESS SCREEN (Fast Reset)
    // -------------------------------------------------------------
    if (uiState.step == CheckInStep.success) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: Colors.green[600], size: 100),
          const SizedBox(height: 24),
          Text(
            uiState.isWelcomeBack
                ? 'Already Checked In!'
                : 'Check-In Successful!',
            style: const TextStyle(fontSize: 20, color: Colors.grey),
          ),
          Text(
            uiState.checkedInGuest?.name ?? 'Guest',
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: _resetForm,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'Next Guest (Enter)',
                style: TextStyle(fontSize: 20),
              ),
            ),
          ),
        ],
      );
    }

    // -------------------------------------------------------------
    // WALK-IN FULL REGISTRATION SCREEN
    // -------------------------------------------------------------
    if (uiState.step == CheckInStep.needsWalkInName) {
      // Create local controllers for the new fields (ensure you dispose these in the State class)
      final emailController = TextEditingController();
      final companyController = TextEditingController();
      final designationController = TextEditingController();
      final industryController = TextEditingController();

      return SizedBox(
        height: 600, // Constrain height so the form can scroll if needed
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'New Registration',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Phone: ${uiState.pendingPhone}',
                style: const TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 24),

              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name *',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'Email Address *',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              TextField(
                controller: companyController,
                decoration: const InputDecoration(
                  labelText: 'Company Name',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              TextField(
                controller: designationController,
                decoration: const InputDecoration(
                  labelText: 'Designation / Title',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              TextField(
                controller: industryController,
                decoration: const InputDecoration(
                  labelText: 'Industry',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (_nameController.text.trim().isEmpty ||
                        emailController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Name and Email are required.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    notifier.submitFullRegistration(
                      eventId: eventId,
                      name: _nameController.text.trim(),
                      email: emailController.text.trim(),
                      companyName: companyController.text.trim(),
                      designation: designationController.text.trim(),
                      industry: industryController.text.trim(),
                    );
                  },
                  child: const Text(
                    'Complete Registration & Check In',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: _resetForm,
                  child: const Text('Cancel & Return to Search'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // -------------------------------------------------------------
    // DEFAULT SEARCH SCREEN
    // -------------------------------------------------------------
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (uiState.step == CheckInStep.error) ...[
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.red[50],
            child: Text(
              uiState.errorMessage ?? 'Error',
              style: const TextStyle(color: Colors.red),
            ),
          ),
          const SizedBox(height: 24),
        ],
        const Icon(Icons.qr_code_scanner, size: 80, color: Color(0xFFc51f43)),
        const SizedBox(height: 16),
        const Text(
          'Enter Attendee Phone Number',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _phoneController,
          focusNode: _phoneFocus,
          decoration: const InputDecoration(
            labelText: 'Phone Number',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.phone),
          ),
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.search,
          onSubmitted: (val) {
            if (val.isNotEmpty) notifier.submitPhone(eventId, val);
          },
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton(
            onPressed: uiState.step == CheckInStep.loading
                ? null
                : () => notifier.submitPhone(
                    eventId,
                    _phoneController.text.trim(),
                  ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFc51f43),
              foregroundColor: Colors.white,
            ),
            child: uiState.step == CheckInStep.loading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text(
                    'Search & Check In',
                    style: TextStyle(fontSize: 20),
                  ),
          ),
        ),
      ],
    );
  }
}
