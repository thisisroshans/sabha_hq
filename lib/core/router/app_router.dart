import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
final authStateProvider = StateProvider<bool>((ref) => false);

// ------------------------------------------------------------------
// 4. ROUTER CONFIGURATION
// ------------------------------------------------------------------
final goRouterProvider = Provider<GoRouter>((ref) {
  // Listen to auth state changes to trigger redirects automatically
  final isLoggedIn = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/check-in',

    // Global redirect handles Route Guarding
    redirect: (context, state) {
      final isGoingToAdmin = state.matchedLocation.startsWith('/dashboard');
      final isGoingToLogin = state.matchedLocation == '/login';

      // 1. Prevent unauthorized access to the dashboard
      if (isGoingToAdmin && !isLoggedIn) {
        return '/login';
      }

      // 2. Prevent logged-in admins from seeing the login screen
      if (isGoingToLogin && isLoggedIn) {
        return '/dashboard/events';
      }

      return null; // Proceed as normal
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
          // return const AdminLoginScreen();
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => ref.read(authStateProvider.notifier).state =
                    true, // Mock login
                child: const Text('Login as Admin'),
              ),
            ),
          );
        },
      ),

      // ShellRoute keeps the Side Menu persistent while swapping inner pages
      ShellRoute(
        builder: (context, state, child) {
          // return AdminScaffold(child: child);

          // Basic Mock Scaffold to show how ShellRoute works
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  extended: true,
                  selectedIndex: state.matchedLocation.contains('analytics')
                      ? 1
                      : 0,
                  onDestinationSelected: (index) {
                    if (index == 0) context.go('/dashboard/events');
                    if (index == 1) context.go('/dashboard/analytics');
                  },
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.event),
                      label: Text('Events'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.analytics),
                      label: Text('Analytics'),
                    ),
                  ],
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: TextButton.icon(
                          icon: const Icon(Icons.logout),
                          label: const Text('Logout'),
                          onPressed: () =>
                              ref.read(authStateProvider.notifier).state =
                                  false, // Mock logout
                        ),
                      ),
                    ),
                  ),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                // The 'child' is either the EventList or Analytics screen
                Expanded(child: child),
              ],
            ),
          );
        },
        routes: [
          GoRoute(
            path: '/dashboard/events',
            builder: (context, state) {
              // return const EventListScreen();
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
              // -------------------------------------------------------------
              // DEFERRED LOADING IMPLEMENTATION
              // -------------------------------------------------------------
              /* 
              return FutureBuilder(
                future: analytics.loadLibrary(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done) {
                    // Once downloaded, render the heavy charting screen
                    return analytics.AnalyticsScreen();
                  }
                  // Show a spinner while the JS chunk is downloading
                  return const Center(child: CircularProgressIndicator());
                },
              );
              */
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
