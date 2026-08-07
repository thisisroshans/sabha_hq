import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/providers/current_org_provider.dart';

// Must match functions' setGlobalOptions({ region: 'asia-south1' }) in
// functions/src/index.ts — the default region (us-central1) has nothing
// deployed there.
const _functionsRegion = 'asia-south1';
FirebaseFunctions _functions() =>
    FirebaseFunctions.instanceFor(region: _functionsRegion);

final orgActionControllerProvider =
    AsyncNotifierProvider.autoDispose<OrgActionController, void>(
      OrgActionController.new,
    );

/// Self-serve org creation (functions/src/orgs.ts's createOrg) — the
/// thing that used to only be possible by running
/// functions/scripts/migrate-to-orgs.js by hand.
class OrgActionController extends AutoDisposeAsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<bool> createOrg(String orgName) async {
    state = const AsyncLoading();
    try {
      await _functions().httpsCallable('createOrg').call({'orgName': orgName});

      // The claim was just set server-side — this client's cached ID
      // token predates it. Force a refresh, then invalidate
      // currentOrgIdProvider so it re-reads with the new token instead
      // of serving its cached (null) result; authStateProvider's stream
      // won't emit on its own here since the User object identity
      // doesn't change on a token refresh, only on sign-in/out.
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
