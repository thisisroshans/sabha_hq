import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sabha_hq/core/utils/color_utils.dart';
import 'package:sabha_hq/features/admin_events/application/event_providers.dart';
import '../application/phone_auth_controller.dart';
import '../application/staff_check_in_controller.dart';

class CheckInScreen extends ConsumerStatefulWidget {
  final String? orgId;
  final String? eventId;
  const CheckInScreen({super.key, required this.orgId, required this.eventId});

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
      // Silent, no-UI auth + event binding, so Firestore rules
      // (isGuestSessionFor(orgId, eventId)) are satisfied by the time the
      // guest submits their phone number.
      if (widget.orgId != null && widget.eventId != null) {
        ref
            .read(guestAuthControllerProvider.notifier)
            .ensureGuestSession(widget.orgId!, widget.eventId!);
      }
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

  Future<void> _submitPhone(String orgId, String eventId, String phone) async {
    if (phone.isEmpty) return;
    final ready = await ref
        .read(guestAuthControllerProvider.notifier)
        .ensureGuestSession(orgId, eventId);
    if (!ready || !mounted) return;
    ref.read(staffCheckInProvider.notifier).submitPhone(orgId, eventId, phone);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.orgId == null || widget.eventId == null) {
      return const Scaffold(
        body: Center(child: Text('Invalid Link. Missing Event ID.')),
      );
    }

    final orgId = widget.orgId!;
    final eventId = widget.eventId!;

    // ------------------------------------------------------------------
    // NAVIGATION LISTENER: Watch for successful check-in
    // ------------------------------------------------------------------
    ref.listen<StaffCheckInState>(staffCheckInProvider, (previous, next) {
      if (next.step == CheckInStep.success) {
        // Optional: Add a small delay so they see the success checkmark
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (!context.mounted) return;

          // Through go_router, to a URL of its own (see app_router.dart's
          // /live-event) — not Navigator.pushReplacement. A raw push left
          // the router still believing it was on /check-in, so the Live
          // Event screen's Logout (context.go back to /check-in) was a
          // no-op: the guest got signed out but the kiosk stayed stuck on a
          // "Couldn't load the live feed" screen, and the next attendee
          // couldn't check in. Found by integration_test/e2e_test.dart.
          context.go(
            '/live-event?orgId=$orgId&eventId=$eventId',
            extra: next.checkedInGuest?.name ?? 'Attendee',
          );
        });
      }
    });

    final uiState = ref.watch(staffCheckInProvider);
    final notifier = ref.read(staffCheckInProvider.notifier);
    final guestAuthState = ref.watch(guestAuthControllerProvider);

    // Event.branding was written by edit_event_screen.dart but never read
    // anywhere until task #8 — the kiosk hardcoded 0xFFc51f43 regardless.
    final eventState = ref.watch(
      eventForGuestProvider((orgId: orgId, eventId: eventId)),
    );
    final event = eventState.valueOrNull;
    final themeColor =
        parseHexColor(event?.branding['primaryColor'] as String?) ??
        const Color(0xFFc51f43);
    final logoUrl = event?.branding['logoUrl'] as String?;

    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Event Check-In'),
        backgroundColor: themeColor,
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (logoUrl != null && logoUrl.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Image.network(
                        logoUrl,
                        height: 64,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                  ],
                  Container(
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
                      orgId,
                      eventId,
                      isMobile,
                      themeColor,
                    ),
                  ),
                ],
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
    String orgId,
    String eventId,
    bool isMobile,
    Color themeColor,
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
            uiState.checkedInGuest?.name ?? 'Attendee',
            style: TextStyle(
              fontSize: isMobile ? 26 : 36,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          CircularProgressIndicator(color: themeColor),
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
                  orgId: orgId,
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
          color: themeColor,
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
          onSubmitted: (val) => _submitPhone(orgId, eventId, val.trim()),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: isBusy
                ? null
                : () => _submitPhone(orgId, eventId, _phoneController.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor,
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
