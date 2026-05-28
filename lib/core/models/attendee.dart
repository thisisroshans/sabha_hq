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
    );
  }
}
