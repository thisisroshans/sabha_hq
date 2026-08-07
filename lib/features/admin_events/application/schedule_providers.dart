import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/models/schedule_item.dart';
import 'package:sabha_hq/core/providers/current_org_provider.dart';
import '../data/schedule_repository.dart';

/// Admin-side: resolves orgId internally (currentOrgIdProvider), same
/// pattern as eventProvider in event_providers.dart — no screen-level
/// orgId threading needed.
final scheduleItemsProvider = StreamProvider.autoDispose
    .family<List<ScheduleItem>, String>((ref, eventId) async* {
      final orgId = await ref.watch(currentOrgIdProvider.future);
      if (orgId == null) {
        yield const [];
        return;
      }
      final repo = ref.watch(scheduleRepositoryProvider);
      yield* repo.watchScheduleItems(orgId, eventId);
    });

/// Guest-side: orgId explicit, same reasoning as eventForGuestProvider —
/// a guest viewing the agenda has no admin claims to resolve an org from.
final scheduleItemsForGuestProvider = StreamProvider.autoDispose
    .family<List<ScheduleItem>, ({String orgId, String eventId})>((ref, key) {
      final repo = ref.watch(scheduleRepositoryProvider);
      return repo.watchScheduleItems(key.orgId, key.eventId);
    });

final scheduleActionControllerProvider =
    AsyncNotifierProvider.autoDispose<ScheduleActionController, void>(
      ScheduleActionController.new,
    );

class ScheduleActionController extends AutoDisposeAsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<String> _requireOrgId() async {
    final orgId = await ref.read(currentOrgIdProvider.future);
    if (orgId == null) {
      throw Exception(
        'No organization found for this account. Contact an owner to be invited.',
      );
    }
    return orgId;
  }

  Future<bool> addItem(String eventId, ScheduleItem item) async {
    state = const AsyncLoading();
    try {
      final orgId = await _requireOrgId();
      await ref.read(scheduleRepositoryProvider).addScheduleItem(orgId, eventId, item);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> updateItem(String eventId, ScheduleItem item) async {
    state = const AsyncLoading();
    try {
      final orgId = await _requireOrgId();
      await ref.read(scheduleRepositoryProvider).updateScheduleItem(orgId, eventId, item);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> deleteItem(String eventId, String itemId) async {
    state = const AsyncLoading();
    try {
      final orgId = await _requireOrgId();
      await ref.read(scheduleRepositoryProvider).deleteScheduleItem(orgId, eventId, itemId);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}
