import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/auth_repository.dart';

// 1. Expose the authentication stream
final authStateProvider = StreamProvider<User?>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  return authRepository.authStateChanges;
});

// 2. A simple controller to handle the loading/error state of the login form
final authControllerProvider = AsyncNotifierProvider<AuthController, void>(
  AuthController.new,
);

class AuthController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {
    // Initial state does nothing
  }

  Future<void> login(String email, String password) async {
    // Set state to loading while we wait for Firebase
    state = const AsyncLoading();

    // Attempt login, if it throws, Riverpod automatically catches it and sets state to AsyncError
    state = await AsyncValue.guard(() async {
      final repo = ref.read(authRepositoryProvider);
      await repo.signInWithEmail(email, password);
    });
  }

  Future<void> signup(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(authRepositoryProvider);
      await repo.signUpWithEmail(email, password);
    });
  }

  Future<void> logout() async {
    final repo = ref.read(authRepositoryProvider);
    await repo.signOut();
  }
}

// 3. Separate from AuthController's login/signup state — a password-reset
// attempt needs its own "sent" confirmation, distinct from "successfully
// logged in", so it gets its own small notifier rather than overloading
// authControllerProvider's state.
final passwordResetControllerProvider =
    AsyncNotifierProvider.autoDispose<PasswordResetController, void>(
      PasswordResetController.new,
    );

class PasswordResetController extends AutoDisposeAsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<bool> sendResetEmail(String email) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(authRepositoryProvider);
      await repo.sendPasswordResetEmail(email);
    });
    return !state.hasError;
  }
}
