import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/features/admin_auth/application/auth_controller.dart';

/// Sabha HQ's own staff, resolved the same way as
/// current_org_provider.dart's currentOrgIdProvider — but this is a
/// STRUCTURALLY SEPARATE claim. A platform-staff account has no orgId at
/// all; it doesn't "belong to" any org and can't inherit org access
/// through isOrgMember(). Only 'owner' exists today; a lesser 'support'
/// tier is anticipated (see the platform dashboard plan) but not built —
/// this provider already returns the raw string so that tier can plug in
/// without a shape change here.
///
/// Granted via functions/scripts/grant-platform-staff.js — no self-serve
/// path exists, deliberately: granting this claim gives read access to
/// every customer's data.
final platformRoleProvider = FutureProvider.autoDispose<String?>((ref) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return null;

  final tokenResult = await user.getIdTokenResult(true);
  return tokenResult.claims?['platformRole'] as String?;
});
