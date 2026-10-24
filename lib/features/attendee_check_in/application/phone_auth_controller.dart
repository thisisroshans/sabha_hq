import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final guestAuthControllerProvider =
    NotifierProvider.autoDispose<GuestAuthController, AsyncValue<void>>(
      GuestAuthController.new,
    );

/// ensureSignedIn() found an organizer (email/password) signed in on this
/// browser. beginGuestSession only accepts anonymous sessions, so check-in
/// can't proceed — but signing them out silently would also log them out
/// of the dashboard in every other tab on this origin, so the check-in
/// screen asks first instead.
class OrganizerSignedInException implements Exception {
  final String? email;
  const OrganizerSignedInException(this.email);
}

/// Ensures the kiosk has an active, event-scoped Firebase Auth session
/// before any check-in read/write hits Firestore. Two steps, both silent —
/// the guest never sees either:
///
///   1. ensureSignedIn(): anonymous sign-in, so request.auth != null.
///   2. ensureGuestSession(orgId, eventId): calls the beginGuestSession
///      Cloud Function (functions/src/guestSessions.ts), which stamps
///      {guestOrgId, guestEventId} custom claims on that anonymous user.
///      Without this, firestore.rules' isGuestSessionFor(orgId, eventId)
///      has nothing to check — an anonymous session alone can't be scoped
///      to one event. See docs/saas-schema.md.
class GuestAuthController extends AutoDisposeNotifier<AsyncValue<void>> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Must match functions' setGlobalOptions({ region: 'asia-south1' }) in
  // functions/src/index.ts — the default region (us-central1) has nothing
  // deployed there.
  static const _functionsRegion = 'asia-south1';

  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  // The screen that kicked off a call may navigate away (or be disposed)
  // while the network call is in flight — writing to `state` on a
  // torn-down autoDispose provider throws "ref used after disposed".
  // Swallow that specific case quietly instead of letting it surface as
  // an unhandled error.
  void _setStateIfMounted(AsyncValue<void> value) {
    try {
      state = value;
    } on StateError {
      // Provider was disposed before this finished — nothing left to update.
    }
  }

  Future<bool> ensureSignedIn() async {
    final user = _auth.currentUser;
    if (user != null && user.isAnonymous) return true;

    // Any existing session that isn't anonymous gets rejected by
    // beginGuestSession, which used to surface as a misleading "Could not
    // connect". An organizer is the same isAdmin test app_router.dart uses.
    if (user != null && user.email != null) {
      _setStateIfMounted(
        AsyncValue.error(
          OrganizerSignedInException(user.email),
          StackTrace.current,
        ),
      );
      return false;
    }

    _setStateIfMounted(const AsyncValue.loading());
    try {
      // Anything else is a stale guest login — e.g. the phone-OTP check-in
      // this app used before anonymous guest sessions (removed Aug 2026),
      // which browsers that checked into an older event still remember.
      // Nobody else uses that session, so just replace it.
      if (user != null) await _auth.signOut();
      await _auth.signInAnonymously();
      _setStateIfMounted(const AsyncValue.data(null));
      return true;
    } catch (e, st) {
      _setStateIfMounted(AsyncValue.error(e, st));
      return false;
    }
  }

  /// Binds the current (already-signed-in) session to one event. Call
  /// after ensureSignedIn() succeeds, before any Firestore read/write.
  Future<bool> ensureGuestSession(String orgId, String eventId) async {
    final signedIn = await ensureSignedIn();
    if (!signedIn) return false;

    _setStateIfMounted(const AsyncValue.loading());
    try {
      final functions = FirebaseFunctions.instanceFor(region: _functionsRegion);
      await functions.httpsCallable('beginGuestSession').call({
        'orgId': orgId,
        'eventId': eventId,
      });

      // The claim was just set server-side, but this client is still
      // holding the ID token from before that happened — Firestore rules
      // evaluate against whatever token is attached to each request, so
      // without forcing a refresh here, every subsequent read/write would
      // be checked against the OLD token and denied by
      // isGuestSessionFor(orgId, eventId).
      await _auth.currentUser?.getIdToken(true);

      _setStateIfMounted(const AsyncValue.data(null));
      return true;
    } catch (e, st) {
      _setStateIfMounted(AsyncValue.error(e, st));
      return false;
    }
  }

  Future<void> reset() async {
    // Kiosk device: clear this guest's session so the next person doesn't
    // inherit their auth state (or their event-scoped claim).
    await _auth.signOut();
    _setStateIfMounted(const AsyncValue.data(null));
  }
}
