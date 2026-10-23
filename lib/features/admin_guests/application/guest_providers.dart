import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:sabha_hq/core/models/attendee.dart';
import 'package:sabha_hq/core/providers/current_org_provider.dart';
import 'package:sabha_hq/core/utils/phone.dart';

import '../data/guest_repository.dart';

// 1. Holds the ID of the currently selected event in the dropdown
final selectedEventFilterProvider = StateProvider<String?>((ref) => null);

// 2. Streams the guests ONLY for the selected event
final guestListProvider = StreamProvider.autoDispose<List<Attendee>>((ref) async* {
  final eventId = ref.watch(selectedEventFilterProvider);
  if (eventId == null) {
    yield const [];
    return;
  }

  final orgId = await ref.watch(currentOrgIdProvider.future);
  if (orgId == null) {
    yield const [];
    return;
  }

  yield* ref.watch(guestRepositoryProvider).watchGuests(orgId, eventId);
});

// 3. Handles Add, Remove, and Bulk Add actions
final guestActionControllerProvider =
    AsyncNotifierProvider.autoDispose<GuestActionController, void>(
      GuestActionController.new,
    );

class GuestActionController extends AutoDisposeAsyncNotifier<void> {
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

  /// Adds a single guest from the manual UI form
  Future<bool> addGuest({
    required String name,
    required String phone,
    required String role,
    String email = '',
  }) async {
    state = const AsyncLoading();
    final eventId = ref.read(selectedEventFilterProvider);

    if (eventId == null) return false;

    try {
      final orgId = await _requireOrgId();
      final repository = ref.read(guestRepositoryProvider);
      final newGuest = Attendee(
        id: '',
        eventId: eventId,
        phone: PhoneUtils.normalize(phone),
        name: name,
        email: email,
        role: role,
        isCheckedIn: false,
      );

      await repository.addGuest(orgId, eventId, newGuest);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  /// Bulk adds guests from a CSV/Excel import using WriteBatch
  Future<bool> bulkAddGuests(List<Attendee> guests) async {
    state = const AsyncLoading();
    final eventId = ref.read(selectedEventFilterProvider);

    if (eventId == null || guests.isEmpty) {
      state = const AsyncData(null);
      return false;
    }

    try {
      final orgId = await _requireOrgId();
      final repository = ref.read(guestRepositoryProvider);
      await repository.addGuestsInBatch(orgId, eventId, guests);

      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  /// Prompts the user to pick a CSV file, parses it, and bulk uploads the guests.
  Future<int> importGuestsFromCsv() async {
    final eventId = ref.read(selectedEventFilterProvider);
    if (eventId == null) throw Exception('No event selected.');

    // 1. Pick the file
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );

    if (result == null || result.files.single.bytes == null) {
      return 0; // User canceled
    }

    state = const AsyncLoading();

    try {
      // 2. Decode bytes to String
      final bytes = result.files.single.bytes!;
      final csvString = utf8.decode(bytes);

      // 3. Parse CSV into a List of Lists (Rows and Columns)
      final List<List<dynamic>> rows = Csv().decoder.convert(csvString);

      if (rows.isEmpty) throw Exception('The CSV file is empty.');

      // 4. Assuming Row 0 is headers, start at Row 1
      List<Attendee> guestsToUpload = [];

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];

        if (row.isEmpty || row[0].toString().trim().isEmpty) continue;

        final name = row.isNotEmpty
            ? row[0].toString().trim()
            : 'Unknown Attendee';
        final phone = row.length > 1 ? row[1].toString().trim() : '';
        final email = row.length > 2 ? row[2].toString().trim() : '';
        // Accepts "Mover"/"Pitcher" (what exports write now) as well as
        // the legacy "guest"/"participant" in older spreadsheets.
        final role = AttendeeRole.fromInput(
          row.length > 3 ? row[3].toString() : '',
        );

        if (phone.isNotEmpty) {
          guestsToUpload.add(
            Attendee(
              id: '',
              eventId: eventId,
              name: name,
              phone: PhoneUtils.normalize(phone),
              email: email,
              role: role,
              isCheckedIn: false,
            ),
          );
        }
      }

      // 5. Send to the batch writer
      if (guestsToUpload.isNotEmpty) {
        await bulkAddGuests(guestsToUpload);
      }

      state = const AsyncData(null);
      return guestsToUpload.length;
    } catch (e, st) {
      state = AsyncError(e, st);
      return -1;
    }
  }

  /// Removes a single guest
  Future<bool> removeGuest(String guestId) async {
    state = const AsyncLoading();
    final eventId = ref.read(selectedEventFilterProvider);

    if (eventId == null) return false;

    try {
      final orgId = await _requireOrgId();
      await ref.read(guestRepositoryProvider).removeGuest(orgId, eventId, guestId);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}
