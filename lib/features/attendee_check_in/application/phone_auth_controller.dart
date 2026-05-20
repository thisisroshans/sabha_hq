import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/models/attendee.dart';
import '../data/check_in_repository.dart';

// State definition to track where we are in the flow
class PhoneAuthState {
  final bool isLoading;
  final String? error;
  final ConfirmationResult? confirmationResult;
  final Attendee? checkedInAttendee;

  PhoneAuthState({
    this.isLoading = false,
    this.error,
    this.confirmationResult,
    this.checkedInAttendee,
  });

  PhoneAuthState copyWith({
    bool? isLoading,
    String? error,
    ConfirmationResult? confirmationResult,
    Attendee? checkedInAttendee,
    bool clearError = false,
  }) {
    return PhoneAuthState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      confirmationResult: confirmationResult ?? this.confirmationResult,
      checkedInAttendee: checkedInAttendee ?? this.checkedInAttendee,
    );
  }
}

final phoneAuthControllerProvider =
    NotifierProvider.autoDispose<PhoneAuthController, PhoneAuthState>(
      PhoneAuthController.new,
    );

class PhoneAuthController extends AutoDisposeNotifier<PhoneAuthState> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String _currentPhone = '';

  @override
  PhoneAuthState build() => PhoneAuthState();

  // STEP 1: Send the SMS
  Future<void> sendOtp(String phoneNumber) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      // Ensure it has the country code (e.g., +91 for India, +1 for US)
      if (!phoneNumber.startsWith('+')) {
        throw Exception('Please include country code (e.g., +91)');
      }

      _currentPhone = phoneNumber;

      // Flutter Web uses signInWithPhoneNumber for OTP sending
      final confirmation = await _auth.signInWithPhoneNumber(phoneNumber);

      state = state.copyWith(
        isLoading: false,
        confirmationResult: confirmation, // Move to OTP input screen
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  // STEP 2: Verify the Code and Check In
  Future<void> verifyOtpAndCheckIn(String eventId, String smsCode) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      if (state.confirmationResult == null) {
        throw Exception('Session expired. Try again.');
      }

      // 1. Authenticate with Firebase
      await state.confirmationResult!.confirm(smsCode);

      // 2. Query Firestore and update the guest list
      final repository = ref.read(checkInRepositoryProvider);
      final attendee = await repository.searchAndCheckIn(
        eventId,
        _currentPhone,
      );

      // 3. Success! Move to the welcome screen
      state = state.copyWith(isLoading: false, checkedInAttendee: attendee);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Invalid OTP or not on guest list.',
      );
    }
  }

  void reset() {
    state = PhoneAuthState();
  }
}
