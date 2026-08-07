import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/providers/current_org_provider.dart';

const _functionsRegion = 'asia-south1';
FirebaseFunctions _functions() =>
    FirebaseFunctions.instanceFor(region: _functionsRegion);

class TeamMember {
  final String uid;
  final String email;
  final String role;

  const TeamMember({required this.uid, required this.email, required this.role});
}

/// orgs/{orgId}/members — readable by any org member per firestore.rules.
final teamMembersProvider = StreamProvider.autoDispose<List<TeamMember>>((ref) async* {
  final orgId = await ref.watch(currentOrgIdProvider.future);
  if (orgId == null) {
    yield const [];
    return;
  }

  yield* FirebaseFirestore.instance
      .collection('orgs')
      .doc(orgId)
      .collection('members')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map((doc) {
          final data = doc.data();
          return TeamMember(
            uid: doc.id,
            email: (data['email'] as String?) ?? '',
            role: (data['role'] as String?) ?? 'staff',
          );
        }).toList(),
      );
});

final inviteControllerProvider =
    AsyncNotifierProvider.autoDispose<InviteController, void>(
      InviteController.new,
    );

/// Wraps createInvite (functions/src/invites.ts) — no transactional email
/// exists yet, so this hands back a shareable link for the caller to
/// send however they normally would (Slack, WhatsApp, copy-paste).
class InviteController extends AutoDisposeAsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<String?> createInvite({
    required String email,
    required String role,
  }) async {
    state = const AsyncLoading();
    try {
      final orgId = await ref.read(currentOrgIdProvider.future);
      if (orgId == null) {
        throw Exception('No organization found for this account.');
      }

      final result = await _functions().httpsCallable('createInvite').call({
        'orgId': orgId,
        'email': email,
        'role': role,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final token = data['token'] as String;

      state = const AsyncData(null);
      return '${Uri.base.origin}/accept-invite?orgId=$orgId&token=$token';
    } on FirebaseFunctionsException catch (e) {
      state = AsyncError(Exception(e.message ?? e.code), StackTrace.current);
      return null;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }
}

final acceptInviteControllerProvider =
    AsyncNotifierProvider.autoDispose<AcceptInviteController, void>(
      AcceptInviteController.new,
    );

class AcceptInviteController extends AutoDisposeAsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<bool> acceptInvite({required String orgId, required String token}) async {
    state = const AsyncLoading();
    try {
      await _functions().httpsCallable('acceptInvite').call({
        'orgId': orgId,
        'token': token,
      });

      // Same refresh caveat as OrgActionController.createOrg: the claim
      // was just set server-side, this client's cached token predates
      // it, and authStateProvider won't emit on its own since the User
      // object identity doesn't change on a token refresh.
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      ref.invalidate(currentOrgIdProvider);

      state = const AsyncData(null);
      return true;
    } on FirebaseFunctionsException catch (e) {
      state = AsyncError(Exception(e.message ?? e.code), StackTrace.current);
      return false;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}
