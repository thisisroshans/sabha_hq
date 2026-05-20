import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sabha_hq/features/admin_auth/presentation/admin_login_screen.dart';
import 'package:sabha_hq/features/admin_dashboard/presentation/admin_scaffold.dart';
import '../../features/admin_auth/application/auth_controller.dart';
// ------------------------------------------------------------------
// 1. STANDARD IMPORTS
// These are the lightweight screens needed for immediate routing.
// (Uncomment and adjust paths as you build your UI files)
// ------------------------------------------------------------------
// import 'package:sabha_hq/features/admin_auth/presentation/admin_login_screen.dart';
// import 'package:sabha_hq/features/admin_dashboard/presentation/admin_scaffold.dart';
// import 'package:sabha_hq/features/admin_events/presentation/event_list_screen.dart';
// import 'package:sabha_hq/features/attendee_check_in/presentation/check_in_screen.dart';
// import 'package:sabha_hq/features/attendee_feedback/presentation/feedback_screen.dart';

// ------------------------------------------------------------------
// 2. DEFERRED IMPORTS
// The 'deferred as' keyword splits this into a separate JavaScript file
// on the web. It only downloads when the Admin clicks "Analytics".
// ------------------------------------------------------------------
// import 'package:sabha_hq/features/admin_analytics/presentation/analytics_screen.dart' deferred as analytics;

// ------------------------------------------------------------------
// 3. AUTH STATE PROVIDER (Mock for now)
// Replace this with your actual FirebaseAuth state provider.
// ------------------------------------------------------------------

// ------------------------------------------------------------------
// 4. ROUTER CONFIGURATION
// ------------------------------------------------------------------

final goRouterProvider = Provider<GoRouter>((ref) {
  // Watch the AsyncValue from our real Firebase Auth stream
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/check-in',

    redirect: (context, state) {
      // If authState is still loading from Firebase, don't redirect yet
      if (authState.isLoading) return null;

      // Determine if a user is actively logged in
      final isLoggedIn = authState.valueOrNull != null;

      final isGoingToAdmin = state.matchedLocation.startsWith('/dashboard');
      final isGoingToLogin = state.matchedLocation == '/login';

      if (isGoingToAdmin && !isLoggedIn) {
        return '/login';
      }

      if (isGoingToLogin && isLoggedIn) {
        return '/dashboard/events';
      }

      return null;
    },

    routes: [
      // ==========================================
      // ATTENDEE BRANCH (Public & Lightweight)
      // ==========================================
      GoRoute(
        path: '/check-in',
        builder: (context, state) {
          // Extracts ?eventId=XYZ from the URL
          final eventId = state.uri.queryParameters['eventId'];

          // return CheckInScreen(eventId: eventId);
          return Scaffold(
            appBar: AppBar(title: const Text('Attendee Check-In')),
            body: Center(
              child: Text(
                eventId != null
                    ? 'Checking in to: $eventId'
                    : 'Please scan a valid QR code.',
              ),
            ),
          );
        },
      ),
      GoRoute(
        path: '/feedback',
        builder: (context, state) {
          final eventId = state.uri.queryParameters['eventId'];
          // return FeedbackScreen(eventId: eventId);
          return const Scaffold(body: Center(child: Text('Feedback Screen')));
        },
      ),

      // ==========================================
      // ADMIN BRANCH (Protected)
      // ==========================================
      GoRoute(
        path: '/login',
        builder: (context, state) {
          return const AdminLoginScreen();
        },
      ),
      // ShellRoute keeps the Side Menu persistent while swapping inner pages
      ShellRoute(
        builder: (context, state, child) {
          // Now it cleanly returns the isolated widget
          return AdminScaffold(child: child);
        },
        routes: [
          GoRoute(
            path: '/dashboard/events',
            builder: (context, state) {
              return const Center(
                child: Text(
                  'Event Management List',
                  style: TextStyle(fontSize: 24),
                ),
              );
            },
          ),
          GoRoute(
            path: '/dashboard/analytics',
            builder: (context, state) {
              return const Center(
                child: Text(
                  'Analytics Dashboard (Lazy Loaded)',
                  style: TextStyle(fontSize: 24),
                ),
              );
            },
          ),
        ],
      ),
    ],
  );
});
