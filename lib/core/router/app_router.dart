import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sabha_hq/core/models/event.dart';
import 'package:sabha_hq/features/admin_auth/presentation/admin_login_screen.dart';
import 'package:sabha_hq/features/admin_auth/presentation/signup_screen.dart';
import 'package:sabha_hq/features/admin_dashboard/presentation/admin_scaffold.dart';
import 'package:sabha_hq/features/admin_events/presentation/create_event_screen.dart';
import 'package:sabha_hq/features/admin_events/presentation/edit_event_screen.dart';
import 'package:sabha_hq/features/admin_events/presentation/event_list_screen.dart';
import 'package:sabha_hq/features/admin_guests/presentation/guest_management_screen.dart';
import 'package:sabha_hq/features/admin_org/presentation/accept_invite_screen.dart';
import 'package:sabha_hq/features/admin_org/presentation/team_screen.dart';
import 'package:sabha_hq/features/attendee_check_in/presentation/check_in_screen.dart';
import 'package:sabha_hq/features/attendee_feedback/presentation/feedback_screen.dart';

// ADDED: Import for the new Live Activity Screen
import 'package:sabha_hq/features/admin_dashboard/presentation/live_activity_screen.dart';

import '../../features/admin_analytics/presentation/analytics_screen.dart'
    deferred as analytics;

/// Bridges a Stream (Firebase auth state changes) into a Listenable that
/// go_router's `refreshListenable` can watch. This lets auth changes
/// re-run `redirect` on the CURRENT location, instead of the old approach
/// of `ref.watch`-ing auth state inside the GoRouter provider — which
/// rebuilt a brand new GoRouter (reset to `initialLocation`) on every
/// sign-in/sign-out, including the guest kiosk's silent anonymous
/// sign-in/out. That's what was bouncing guests to /login.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen(
      (_) => notifyListeners(),
    );
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

// A single GoRouter instance lives for the app's lifetime — it must never
// be recreated on auth changes (that resets navigation to
// initialLocation). Reactivity to auth comes from refreshListenable below.
final goRouterProvider = Provider<GoRouter>((ref) {
  final refreshStream = GoRouterRefreshStream(
    FirebaseAuth.instance.authStateChanges(),
  );
  ref.onDispose(refreshStream.dispose);

  return GoRouter(
    initialLocation: '/dashboard/events',
    refreshListenable: refreshStream,
    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;
      final isAdmin = user != null && user.email != null;

      final isGoingToAdmin = state.matchedLocation.startsWith('/dashboard');
      final isGoingToAuthScreen =
          state.matchedLocation == '/login' || state.matchedLocation == '/signup';
      final isRoot = state.matchedLocation == '/';

      if (isRoot) return '/dashboard/events';

      // Block non-admins (including anonymous check-in kiosk sessions) from
      // the dashboard.
      if (isGoingToAdmin && !isAdmin) return '/login';

      // An already-authenticated admin hitting login OR signup goes to the
      // dashboard — AdminScaffold itself decides whether that's the real
      // dashboard or the org-onboarding screen, based on whether they have
      // an orgId claim yet (see OrgOnboardingScreen).
      if (isGoingToAuthScreen && isAdmin) return '/dashboard/events';

      return null;
    },
    routes: [
      // ==========================================
      // ATTENDEE BRANCH (Public & Lightweight)
      // ==========================================
      GoRoute(
        path: '/check-in',
        builder: (context, state) {
          // Both ids travel in the URL — this is a public,
          // pre-authentication screen with no admin claims to resolve an
          // org from (see qr_code_dialog.dart, which is what generates
          // this link).
          final orgId = state.uri.queryParameters['orgId'];
          final eventId = state.uri.queryParameters['eventId'];
          return CheckInScreen(orgId: orgId, eventId: eventId);
        },
      ),
      GoRoute(
        path: '/feedback',
        builder: (context, state) {
          // Same reasoning as /check-in: public, pre-auth, orgId travels
          // in the URL. Reached from GuestActivityScreen's "Give
          // Feedback" button after check-in (task #8).
          final orgId = state.uri.queryParameters['orgId'];
          final eventId = state.uri.queryParameters['eventId'];
          return FeedbackScreen(orgId: orgId, eventId: eventId);
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
      GoRoute(
        path: '/signup',
        builder: (context, state) {
          return const SignupScreen();
        },
      ),
      // Public — reached via a link an owner/admin shares (Team screen),
      // not gated by isGoingToAdmin since the visitor may not be signed
      // in yet. See AcceptInviteScreen for why it can't pre-validate the
      // invite before the visitor authenticates.
      GoRoute(
        path: '/accept-invite',
        builder: (context, state) {
          final orgId = state.uri.queryParameters['orgId'];
          final token = state.uri.queryParameters['token'];
          return AcceptInviteScreen(orgId: orgId, token: token);
        },
      ),

      // ShellRoute keeps the Side Menu persistent while swapping inner pages
      ShellRoute(
        builder: (context, state, child) {
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
                path: 'create',
                builder: (context, state) => const CreateEventScreen(),
              ),
              GoRoute(
                path: 'edit',
                builder: (context, state) {
                  final event = state.extra as Event;
                  return EditEventScreen(event: event);
                },
              ),
            ],
          ),

          // ------------------------------------------------
          // SIBLING 2: GUESTS
          // ------------------------------------------------
          GoRoute(
            path: '/dashboard/guests',
            builder: (context, state) => const GuestManagementScreen(),
          ),

          // ------------------------------------------------
          // SIBLING 2b: TEAM (Phase 2, task #7)
          // ------------------------------------------------
          GoRoute(
            path: '/dashboard/team',
            builder: (context, state) => const TeamScreen(),
          ),

          // ------------------------------------------------
          // SIBLING 3: LIVE ACTIVITY FEED (NEW)
          // ------------------------------------------------
          GoRoute(
            path: '/dashboard/live',
            builder: (context, state) => const LiveActivityScreen(),
          ),

          // ------------------------------------------------
          // SIBLING 4: ANALYTICS
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
