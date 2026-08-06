import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final guestAuthControllerProvider =
    NotifierProvider.autoDispose<GuestAuthController, AsyncValue<void>>(
      GuestAuthController.new,
    );

/// Ensures the kiosk has an active Firebase Auth session before any
/// check-in read/write hits Firestore (rules require request.auth != null).
/// No OTP, no UI — the guest never sees this, it's a silent anonymous
/// sign-in that happens the moment they try to check in.
class GuestAuthController extends AutoDisposeNotifier<AsyncValue<void>> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<bool> ensureSignedIn() async {
    if (_auth.currentUser != null) return true;

    state = const AsyncValue.loading();
    try {
      await _auth.signInAnonymously();
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  Future<void> reset() async {
    // Kiosk device: clear this guest's session so the next person doesn't
    // inherit their auth state.
    await _auth.signOut();
    state = const AsyncValue.data(null);
  }
}
