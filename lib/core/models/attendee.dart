/// Attendee roles — what each one is CALLED vs. what's STORED.
///
/// Guests were renamed "Movers" and participants "Pitchers", but only in
/// what the UI shows: the stored `role` values stay 'guest' and
/// 'participant'. They're baked into every attendee doc already in
/// production, the registerWalkIn Cloud Function
/// (functions/src/checkIn.ts), the check-in push notification
/// (functions/src/notifications.ts), and CSV files admins already keep
/// on disk — rewriting all of that buys nothing a label change doesn't.
/// Always render a role through [label]/[pluralLabel] rather than the raw
/// string so the two can't drift apart.
class AttendeeRole {
  static const mover = 'guest';
  static const pitcher = 'participant';

  static bool isPitcher(String role) => role.trim().toLowerCase() == pitcher;

  /// Anything that isn't a pitcher counts as a mover — same fallback
  /// Attendee.fromMap uses for a doc with no role at all.
  static String label(String role) => isPitcher(role) ? 'Pitcher' : 'Mover';

  static String pluralLabel(String role) =>
      isPitcher(role) ? 'Pitchers' : 'Movers';

  /// Parses a role typed by an admin (CSV import) — accepts the new labels
  /// AND the old ones, so a CSV exported before the rename still imports.
  static String fromInput(String raw) {
    final value = raw.trim().toLowerCase();
    return value == pitcher || value == 'pitcher' ? pitcher : mover;
  }
}

class Attendee {
  final String id;
  final String eventId;
  final String name;
  final String phone;
  final String email;
  final String role;
  final bool isCheckedIn;
  final DateTime? checkInTime;

  // NEW FIELDS
  final String companyName;
  final String designation;
  final String industry;

  // Denormalised org id — see docs/saas-schema.md. The doc's real
  // isolation boundary is the orgs/{orgId}/events/{eventId}/attendees
  // path itself; this field exists only so the admin dashboard's
  // collectionGroup('attendees') "All Events" query (which spans every
  // event's attendees subcollection at once and can't be scoped by path
  // alone) can filter to one org.
  final String orgId;

  Attendee({
    required this.id,
    required this.eventId,
    required this.name,
    required this.phone,
    required this.email,
    required this.role,
    this.isCheckedIn = false,
    this.checkInTime,
    this.companyName = '',
    this.designation = '',
    this.industry = '',
    this.orgId = '',
  });

  bool get isPitcher => AttendeeRole.isPitcher(role);

  /// The "name tag" shown next to an attendee everywhere in the UI.
  String get roleLabel => AttendeeRole.label(role);

  Attendee copyWith({
    String? id,
    String? eventId,
    String? name,
    String? phone,
    String? email,
    String? role,
    bool? isCheckedIn,
    DateTime? checkInTime,
    String? companyName,
    String? designation,
    String? industry,
    String? orgId,
  }) {
    return Attendee(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      role: role ?? this.role,
      isCheckedIn: isCheckedIn ?? this.isCheckedIn,
      checkInTime: checkInTime ?? this.checkInTime,
      companyName: companyName ?? this.companyName,
      designation: designation ?? this.designation,
      industry: industry ?? this.industry,
      orgId: orgId ?? this.orgId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'eventId': eventId,
      'name': name,
      'phone': phone,
      'email': email,
      'role': role,
      'isCheckedIn': isCheckedIn,
      'checkInTime': checkInTime,
      'companyName': companyName,
      'designation': designation,
      'industry': industry,
      'orgId': orgId,
    };
  }

  // checkInTime arrives in two different shapes depending on the source:
  // a real Firestore Timestamp (has .toDate()) when this map came off a
  // document snapshot, or an ISO 8601 String when it came back from the
  // checkIn/registerWalkIn Cloud Functions (functions/src/checkIn.ts) —
  // a Timestamp doesn't survive a callable's JSON response, so those
  // serialize it explicitly. Handle both rather than assuming one.
  static DateTime? _parseCheckInTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }

  factory Attendee.fromMap(Map<String, dynamic> map, String documentId) {
    return Attendee(
      id: documentId,
      eventId: map['eventId'] ?? '',
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      email: map['email'] ?? '',
      role: map['role'] ?? AttendeeRole.mover,
      isCheckedIn: map['isCheckedIn'] ?? false,
      checkInTime: _parseCheckInTime(map['checkInTime']),
      companyName: map['companyName'] ?? '',
      designation: map['designation'] ?? '',
      industry: map['industry'] ?? '',
      orgId: map['orgId'] ?? '',
    );
  }
}
