import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/features/attendee_check_in/presentation/guest_activity_screen.dart';
import '../application/phone_auth_controller.dart';
import '../application/staff_check_in_controller.dart';

class CheckInScreen extends ConsumerStatefulWidget {
  final String? eventId;
  const CheckInScreen({super.key, required this.eventId});

  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen> {
  // Persistent Controllers
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _companyController = TextEditingController();
  final _designationController = TextEditingController();
  final _industryController = TextEditingController();

  final _phoneFocus = FocusNode();
  final _nameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _phoneFocus.requestFocus();
      // Silent, no-UI auth so Firestore rules (request.auth != null) are
      // satisfied by the time the guest submits their phone number.
      ref.read(guestAuthControllerProvider.notifier).ensureSignedIn();
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _companyController.dispose();
    _designationController.dispose();
    _industryController.dispose();
    _phoneFocus.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _resetForm() {
    _phoneController.clear();
    _nameController.clear();
    _emailController.clear();
    _companyController.clear();
    _designationController.clear();
    _industryController.clear();
    ref.read(staffCheckInProvider.notifier).reset();
    _phoneFocus.requestFocus();
  }

  Future<void> _submitPhone(String eventId, String phone) async {
    if (phone.isEmpty) return;
    final signedIn = await ref
        .read(guestAuthControllerProvider.notifier)
        .ensureSignedIn();
    if (!signedIn || !mounted) return;
    ref.read(staffCheckInProvider.notifier).submitPhone(eventId, phone);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.eventId == null) {
      return const Scaffold(
        body: Center(child: Text('Invalid Link. Missing Event ID.')),
      );
    }

    // ------------------------------------------------------------------
    // NAVIGATION LISTENER: Watch for successful check-in
    // ------------------------------------------------------------------
    ref.listen<StaffCheckInState>(staffCheckInProvider, (previous, next) {
      if (next.step == CheckInStep.success) {
        // Optional: Add a small delay so they see the success checkmark
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (!context.mounted) return;

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => GuestActivityScreen(
                eventId: widget.eventId!,
                guestName: next.checkedInGuest?.name ?? 'Guest',
              ),
            ),
          );
        });
      }
    });

    final uiState = ref.watch(staffCheckInProvider);
    final notifier = ref.read(staffCheckInProvider.notifier);
    final guestAuthState = ref.watch(guestAuthControllerProvider);

    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Event Check-In'),
        backgroundColor: const Color(0xFFc51f43),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16.0 : 32.0,
              vertical: 24.0,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Container(
                padding: EdgeInsets.all(isMobile ? 20.0 : 40.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 20),
                  ],
                ),
                child: _buildBody(
                  uiState,
                  notifier,
                  guestAuthState,
                  widget.eventId!,
                  isMobile,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    StaffCheckInState uiState,
    StaffCheckInController notifier,
    AsyncValue<void> guestAuthState,
    String eventId,
    bool isMobile,
  ) {
    // -------------------------------------------------------------
    // SUCCESS SCREEN (Redirecting State)
    // -------------------------------------------------------------
    if (uiState.step == CheckInStep.success) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle,
            color: Colors.green[600],
            size: isMobile ? 70 : 100,
          ),
          const SizedBox(height: 20),
          Text(
            uiState.isWelcomeBack ? 'Welcome Back!' : 'Check-In Successful!',
            style: TextStyle(
              fontSize: isMobile ? 16 : 20,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            uiState.checkedInGuest?.name ?? 'Guest',
            style: TextStyle(
              fontSize: isMobile ? 26 : 36,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          const CircularProgressIndicator(color: Color(0xFFc51f43)),
          const SizedBox(height: 16),
          const Text(
            'Taking you to the live event...',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      );
    }

    // -------------------------------------------------------------
    // WALK-IN FULL REGISTRATION SCREEN
    // -------------------------------------------------------------
    if (uiState.step == CheckInStep.needsWalkInName) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'New Registration',
            style: TextStyle(
              fontSize: isMobile ? 20 : 24,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Phone: ${uiState.pendingPhone}',
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            focusNode: _nameFocus,
            decoration: const InputDecoration(
              labelText: 'Full Name *',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Email Address *',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _companyController,
            decoration: const InputDecoration(
              labelText: 'Company Name',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _designationController,
            decoration: const InputDecoration(
              labelText: 'Designation / Title',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _industryController,
            decoration: const InputDecoration(
              labelText: 'Industry',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                if (_nameController.text.trim().isEmpty ||
                    _emailController.text.trim().isEmpty) {
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
                  email: _emailController.text.trim(),
                  companyName: _companyController.text.trim(),
                  designation: _designationController.text.trim(),
                  industry: _industryController.text.trim(),
                );
              },
              child: const Text(
                'Register & Check In',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _resetForm,
              child: const Text('Cancel'),
            ),
          ),
        ],
      );
    }

    final isBusy =
        guestAuthState.isLoading || uiState.step == CheckInStep.loading;
    final errorText =
        guestAuthState.hasError
            ? 'Could not connect. Please try again.'
            : uiState.errorMessage;

    // -------------------------------------------------------------
    // DEFAULT SEARCH SCREEN
    // -------------------------------------------------------------
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (uiState.step == CheckInStep.error || guestAuthState.hasError) ...[
          Container(
            padding: const EdgeInsets.all(12),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              errorText ?? 'An unknown error occurred.',
              style: const TextStyle(color: Colors.red),
            ),
          ),
          const SizedBox(height: 20),
        ],
        Icon(
          Icons.qr_code_scanner,
          size: isMobile ? 60 : 80,
          color: const Color(0xFFc51f43),
        ),
        const SizedBox(height: 16),
        Text(
          'Enter Your Phone Number',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: isMobile ? 18 : 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _phoneController,
          focusNode: _phoneFocus,
          decoration: const InputDecoration(
            labelText: 'Phone Number',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.phone),
            counterText: '',
          ),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.search,
          maxLength: 10,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (val) => _submitPhone(eventId, val.trim()),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: isBusy
                ? null
                : () => _submitPhone(eventId, _phoneController.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFc51f43),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: isBusy
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Text('Check In', style: TextStyle(fontSize: 18)),
          ),
        ),
      ],
    );
  }
}
