import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabha_hq/core/models/attendee.dart';

final checkInRepositoryProvider = Provider<CheckInRepository>(
  (ref) => CheckInRepository(),
);

/// Check-in no longer writes to Firestore directly — both operations go
/// through Cloud Functions (functions/src/checkIn.ts), which run as the
/// Admin SDK and add validation, phone-format tolerance, rate limiting,
/// and an audit trail (orgs/{orgId}/events/{eventId}/checkInLog) that a
/// client-side write never could. firestore.rules denies guest sessions
/// direct create/update on attendees now — this is the only path.
class CheckInRepository {
  // Must match functions' setGlobalOptions({ region: 'asia-south1' }) in
  // functions/src/index.ts — the default region (us-central1) has
  // nothing deployed there.
  static const _functionsRegion = 'asia-south1';

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: _functionsRegion);

  Map<String, dynamic> _asMap(Object? data) =>
      Map<String, dynamic>.from(data as Map);

  /// Searches for a guest by phone. If found, checks them in.
  /// Returns NULL if the guest is not found (Walk-In required).
  Future<Attendee?> searchAndCheckIn(
    String orgId,
    String eventId,
    String phone,
  ) async {
    try {
      final result = await _functions.httpsCallable('checkIn').call(
        {'orgId': orgId, 'eventId': eventId, 'phone': phone},
      );

      final data = _asMap(result.data);
      if (data['found'] != true) return null;

      final attendeeMap = _asMap(data['attendee']);
      return Attendee.fromMap(attendeeMap, attendeeMap['id'] as String);
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? e.code);
    }
  }

  /// Registers a brand new walk-in guest with full details and instantly checks them in.
  Future<Attendee> registerFullWalkIn({
    required String orgId,
    required String eventId,
    required String phone,
    required String name,
    required String email,
    required String companyName,
    required String designation,
    required String industry,
  }) async {
    try {
      final result = await _functions.httpsCallable('registerWalkIn').call({
        'orgId': orgId,
        'eventId': eventId,
        'phone': phone,
        'name': name,
        'email': email,
        'companyName': companyName,
        'designation': designation,
        'industry': industry,
      });

      final data = _asMap(result.data);
      return Attendee.fromMap(data, data['id'] as String);
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? e.code);
    }
  }
}
