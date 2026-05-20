import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sabha_hq/core/models/event.dart';
import 'package:sabha_hq/features/admin_auth/presentation/admin_login_screen.dart';
import 'package:sabha_hq/features/admin_dashboard/presentation/admin_scaffold.dart';
import 'package:sabha_hq/features/admin_events/presentation/create_event_screen.dart';
import 'package:sabha_hq/features/admin_events/presentation/edit_event_screen.dart';
import 'package:sabha_hq/features/admin_events/presentation/event_list_screen.dart';
import 'package:sabha_hq/features/admin_guests/presentation/guest_management_screen.dart';
import 'package:sabha_hq/features/attendee_check_in/presentation/check_in_screen.dart';
import '../../features/admin_auth/application/auth_controller.dart';
import '../../features/admin_analytics/presentation/analytics_screen.dart'
    deferred as analytics;
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
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    // 1. CHANGED: Make the dashboard the default starting point instead of check-in
    initialLocation: '/dashboard/events',

    redirect: (context, state) {
      if (authState.isLoading) return null;

      final isLoggedIn = authState.valueOrNull != null;

      final isGoingToAdmin = state.matchedLocation.startsWith('/dashboard');
      final isGoingToLogin = state.matchedLocation == '/login';
      final isRoot = state.matchedLocation == '/';

      // 2. Route root path directly to the dashboard
      if (isRoot) {
        return '/dashboard/events';
      }

      // 3. Prevent unauthorized access to the dashboard
      if (isGoingToAdmin && !isLoggedIn) {
        return '/login';
      }

      // 4. Prevent logged-in admins from seeing the login screen
      if (isGoingToLogin && isLoggedIn) {
        return '/dashboard/events';
      }

      return null; // Let all other routes (like /check-in) proceed normally
    },

    routes: [
      // ==========================================
      // ATTENDEE BRANCH (Public & Lightweight)
      // ==========================================
      GoRoute(
        path: '/check-in',
        builder: (context, state) {
          final eventId = state.uri.queryParameters['eventId'];

          // Return the actual UI!
          return CheckInScreen(eventId: eventId);
        },
      ),
      GoRoute(
        path: '/feedback',
        builder: (context, state) {
          // final eventId = state.uri.queryParameters['eventId'];
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
          // ------------------------------------------------
          // SIBLING 1: EVENTS
          // ------------------------------------------------
          GoRoute(
            path: '/dashboard/events',
            builder: (context, state) => const EventListScreen(),
            routes: [
              GoRoute(
                path: 'create', // Becomes /dashboard/events/create
                builder: (context, state) => const CreateEventScreen(),
              ),
              GoRoute(
                path: 'edit', // Becomes /dashboard/events/edit
                builder: (context, state) {
                  final event = state.extra as Event;
                  return EditEventScreen(event: event);
                },
              ),
            ],
          ),
          // ------------------------------------------------
          // SIBLING 2: GUESTS (Moved out of the events array!)
          // ------------------------------------------------
          GoRoute(
            path: '/dashboard/guests',
            builder: (context, state) => const GuestManagementScreen(),
          ),

          // ------------------------------------------------
          // SIBLING 3: ANALYTICS
          // ------------------------------------------------
          GoRoute(
            path: '/dashboard/analytics',
            builder: (context, state) {
              return FutureBuilder(
                future: analytics.loadLibrary(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done) {
                    return analytics.AnalyticsScreen();
                  }
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                },
              );
            },
          ),
        ],
      ),
    ],
  );
});
