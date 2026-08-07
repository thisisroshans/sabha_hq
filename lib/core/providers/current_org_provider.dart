import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/features/admin_auth/application/auth_controller.dart';

/// The signed-in admin's org, read from their Firebase Auth custom claims
/// — set by functions/src/invites.ts on invite-accept, or by
/// functions/scripts/migrate-to-orgs.js for the bootstrap owner (see
/// docs/saas-schema.md). One org per admin account for now; switching
/// between multiple orgs is Phase 2 territory (task #7), not built.
///
/// Every admin-side repository/provider resolves this internally rather
/// than having screens thread orgId through by hand — the one place that
/// genuinely can't do that is the public, unauthenticated check-in flow
/// (no claims exist for someone who hasn't signed in), which instead
/// carries orgId explicitly via the /check-in?orgId=...&eventId=... URL.
///
/// Returns null while signed out, or if this account has no orgId claim
/// (e.g. a Firebase Auth user created by hand, never migrated or
/// invited) — callers should treat that as "no organization", not throw.
final currentOrgIdProvider = FutureProvider.autoDispose<String?>((ref) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return null;

  // Force a refresh: a long-lived session's cached token may predate a
  // claims change (e.g. accepting an invite mid-session, or being
  // migrated into an org while already logged in). This is a network
  // call only when the cached token is actually stale — cheap the rest
  // of the time — and happens once per cold start of this provider, not
  // on every rebuild, since FutureProvider caches its result.
  final tokenResult = await user.getIdTokenResult(true);
  return tokenResult.claims?['orgId'] as String?;
});

/// role is 'owner' | 'admin' | 'staff' — see docs/saas-schema.md. Null
/// under the same conditions as currentOrgIdProvider.
final currentRoleProvider = FutureProvider.autoDispose<String?>((ref) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return null;
  final tokenResult = await user.getIdTokenResult();
  return tokenResult.claims?['role'] as String?;
});

/// Live status ('active'/'suspended') of the signed-in admin's own org —
/// so AdminScaffold can show a clear "you're suspended" banner instead of
/// a wall of permission-denied errors the moment they try to write
/// anything. A Stream, not a one-off read: a platform owner suspending
/// this org while the admin already has the dashboard open should show
/// up without them needing to refresh. firestore.rules keeps reads open
/// on a suspended org specifically so this still works.
final currentOrgStatusProvider = StreamProvider.autoDispose<String?>((ref) async* {
  final orgId = await ref.watch(currentOrgIdProvider.future);
  if (orgId == null) {
    yield null;
    return;
  }
  yield* FirebaseFirestore.instance
      .collection('orgs')
      .doc(orgId)
      .snapshots()
      .map((snap) => snap.data()?['status'] as String? ?? 'active');
});
