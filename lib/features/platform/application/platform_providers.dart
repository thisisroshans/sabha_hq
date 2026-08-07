import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/firebase/firestore_refs.dart';
import 'package:sabha_hq/core/models/attendee.dart';
import 'package:sabha_hq/core/models/event.dart';
import 'package:sabha_hq/features/admin_events/data/event_repository.dart';
import 'package:sabha_hq/features/admin_org/application/team_providers.dart' show TeamMember;
import 'platform_models.dart';

// Must match functions' setGlobalOptions({ region: 'asia-south1' }) in
// functions/src/index.ts.
const _functionsRegion = 'asia-south1';
FirebaseFunctions _functions() => FirebaseFunctions.instanceFor(region: _functionsRegion);

Map<String, dynamic> _asMap(Object? data) => Map<String, dynamic>.from(data as Map);

/// Every org, with live usage — backs the org directory screen.
final platformOverviewProvider = FutureProvider.autoDispose<List<OrgSummary>>((ref) async {
  final result = await _functions().httpsCallable('getPlatformOverview').call();
  final data = _asMap(result.data);
  final orgs = data['orgs'] as List;
  return orgs.map((o) => OrgSummary.fromMap(_asMap(o))).toList();
});

/// One org, with live usage — backs the org detail screen. Separate call
/// from the overview (not just filtering the list client-side) since
/// getOrgDetail only pays for one org's count() queries, not every org's.
final orgDetailProvider = FutureProvider.autoDispose.family<OrgSummary, String>((ref, orgId) async {
  final result = await _functions().httpsCallable('getOrgDetail').call({'orgId': orgId});
  return OrgSummary.fromMap(_asMap(result.data));
});

/// Platform audit log, optionally filtered to one org (null = every org).
final platformAuditLogProvider = FutureProvider.autoDispose.family<List<PlatformAuditEntry>, String?>((
  ref,
  orgId,
) async {
  final result = await _functions().httpsCallable('getPlatformAuditLog').call(
    orgId != null ? {'orgId': orgId} : {},
  );
  final data = _asMap(result.data);
  final entries = data['entries'] as List;
  return entries.map((e) => PlatformAuditEntry.fromMap(_asMap(e))).toList();
});

final platformActionControllerProvider =
    AsyncNotifierProvider.autoDispose<PlatformActionController, void>(
      PlatformActionController.new,
    );

class PlatformActionController extends AutoDisposeAsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<bool> updateLimits(String orgId, Map<String, int> limits) async {
    state = const AsyncLoading();
    try {
      await _functions().httpsCallable('updateOrgLimits').call({'orgId': orgId, 'limits': limits});
      ref.invalidate(orgDetailProvider(orgId));
      ref.invalidate(platformOverviewProvider);
      ref.invalidate(platformAuditLogProvider(orgId));
      ref.invalidate(platformAuditLogProvider(null));
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

  Future<bool> setStatus(String orgId, String status) async {
    state = const AsyncLoading();
    try {
      await _functions().httpsCallable('setOrgStatus').call({'orgId': orgId, 'status': status});
      ref.invalidate(orgDetailProvider(orgId));
      ref.invalidate(platformOverviewProvider);
      ref.invalidate(platformAuditLogProvider(orgId));
      ref.invalidate(platformAuditLogProvider(null));
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

// ---------------------------------------------------------------------
// Read-only drill-in: full view parity with what an org's own owner/admin
// can see (per explicit request), NOT the ability to act as the org.
// These all take orgId explicitly rather than resolving it from
// currentOrgIdProvider, because a platform-staff account has no orgId
// claim at all — the same reasoning as eventForGuestProvider/
// eventAttendeesStreamProvider (lib/features/admin_events/application/
// event_providers.dart, lib/features/admin_dashboard/application/
// live_feed_providers.dart) being separate from their claim-resolving
// counterparts.
// ---------------------------------------------------------------------

/// EventRepository.watchAllEvents(orgId) already takes orgId explicitly
/// — no new repository code needed, just a provider that doesn't run it
/// through currentOrgIdProvider first.
final platformOrgEventsProvider = StreamProvider.autoDispose.family<List<Event>, String>((ref, orgId) {
  return ref.watch(eventRepositoryProvider).watchAllEvents(orgId);
});

final platformOrgMembersProvider = StreamProvider.autoDispose.family<List<TeamMember>, String>((ref, orgId) {
  return FirebaseFirestore.instance
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

/// FirestoreRefs.attendees(orgId, eventId) is already explicit-orgId —
/// reused as-is, same reasoning as platformOrgEventsProvider above.
final platformEventAttendeesProvider = StreamProvider.autoDispose
    .family<List<Attendee>, ({String orgId, String eventId})>((ref, key) {
      return FirestoreRefs.attendees(key.orgId, key.eventId)
          .orderBy('name')
          .snapshots()
          .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
    });
