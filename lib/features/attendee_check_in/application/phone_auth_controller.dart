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

  // The screen that kicked off an ensureSignedIn()/reset() call may
  // navigate away (or be disposed) while the network call is in flight —
  // writing to `state` on a torn-down autoDispose provider throws "ref
  // used after disposed". Swallow that specific case quietly instead of
  // letting it surface as an unhandled error.
  void _setStateIfMounted(AsyncValue<void> value) {
    try {
      state = value;
    } on StateError {
      // Provider was disposed before this finished — nothing left to update.
    }
  }

  Future<bool> ensureSignedIn() async {
    if (_auth.currentUser != null) return true;

    _setStateIfMounted(const AsyncValue.loading());
    try {
      await _auth.signInAnonymously();
      _setStateIfMounted(const AsyncValue.data(null));
      return true;
    } catch (e, st) {
      _setStateIfMounted(AsyncValue.error(e, st));
      return false;
    }
  }

  Future<void> reset() async {
    // Kiosk device: clear this guest's session so the next person doesn't
    // inherit their auth state.
    await _auth.signOut();
    _setStateIfMounted(const AsyncValue.data(null));
  }
}
