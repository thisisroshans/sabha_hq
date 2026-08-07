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

  factory Attendee.fromMap(Map<String, dynamic> map, String documentId) {
    return Attendee(
      id: documentId,
      eventId: map['eventId'] ?? '',
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      email: map['email'] ?? '',
      role: map['role'] ?? 'guest',
      isCheckedIn: map['isCheckedIn'] ?? false,
      checkInTime: map['checkInTime']?.toDate(),
      companyName: map['companyName'] ?? '',
      designation: map['designation'] ?? '',
      industry: map['industry'] ?? '',
      orgId: map['orgId'] ?? '',
    );
  }
}
