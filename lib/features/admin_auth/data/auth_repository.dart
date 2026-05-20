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

  /// Sign out the current admin
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
