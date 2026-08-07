import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Provider to inject the repository into other parts of the app
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(FirebaseAuth.instance);
});

class AuthRepository {
  final FirebaseAuth _auth;

  AuthRepository(this._auth);

  /// Emits a new value every time the user logs in or logs out
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Synchronous read of the current user
  User? get currentUser => _auth.currentUser;

  /// Sign in using standard Email and Password
  Future<void> signInWithEmail(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  /// Create a brand new admin account. They'll have no org yet — either
  /// createOrg (self-serve, functions/src/orgs.ts) or acceptInvite
  /// (functions/src/invites.ts) is what actually gets them into one.
  Future<void> signUpWithEmail(String email, String password) async {
    await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Sign out the current admin
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Sends a password-reset email. There was previously no recovery path
  /// at all if an admin forgot their password — a real dead end for a
  /// real customer, not just a nice-to-have.
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }
}
