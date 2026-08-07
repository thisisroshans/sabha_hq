class OrgLimits {
  final int maxTeamMembers;
  final int maxEvents;
  final int maxAttendeesPerEvent;
  final int checkInRateLimitPerMinute;

  const OrgLimits({
    required this.maxTeamMembers,
    required this.maxEvents,
    required this.maxAttendeesPerEvent,
    required this.checkInRateLimitPerMinute,
  });

  factory OrgLimits.fromMap(Map<String, dynamic> map) {
    return OrgLimits(
      maxTeamMembers: (map['maxTeamMembers'] as num).toInt(),
      maxEvents: (map['maxEvents'] as num).toInt(),
      maxAttendeesPerEvent: (map['maxAttendeesPerEvent'] as num).toInt(),
      checkInRateLimitPerMinute: (map['checkInRateLimitPerMinute'] as num).toInt(),
    );
  }
}

class OrgUsage {
  final int eventCount;
  final int teamMemberCount;
  final int attendeeCount;

  const OrgUsage({
    required this.eventCount,
    required this.teamMemberCount,
    required this.attendeeCount,
  });

  factory OrgUsage.fromMap(Map<String, dynamic> map) {
    return OrgUsage(
      eventCount: (map['eventCount'] as num).toInt(),
      teamMemberCount: (map['teamMemberCount'] as num).toInt(),
      attendeeCount: (map['attendeeCount'] as num).toInt(),
    );
  }
}

class OrgSummary {
  final String id;
  final String name;
  final String plan;
  final String status;
  final OrgLimits limits;
  final OrgUsage usage;
  final DateTime? createdAt;

  const OrgSummary({
    required this.id,
    required this.name,
    required this.plan,
    required this.status,
    required this.limits,
    required this.usage,
    required this.createdAt,
  });

  bool get isSuspended => status == 'suspended';

  factory OrgSummary.fromMap(Map<String, dynamic> map) {
    return OrgSummary(
      id: map['id'] as String,
      name: map['name'] as String? ?? '(unnamed)',
      plan: map['plan'] as String? ?? 'free',
      status: map['status'] as String? ?? 'active',
      limits: OrgLimits.fromMap(Map<String, dynamic>.from(map['limits'] as Map)),
      usage: OrgUsage.fromMap(Map<String, dynamic>.from(map['usage'] as Map)),
      createdAt: map['createdAt'] != null ? DateTime.tryParse(map['createdAt'] as String) : null,
    );
  }
}

class PlatformAuditEntry {
  final String id;
  final String uid;
  final String action;
  final String? orgId;
  final Map<String, dynamic> details;
  final DateTime? at;

  const PlatformAuditEntry({
    required this.id,
    required this.uid,
    required this.action,
    required this.orgId,
    required this.details,
    required this.at,
  });

  factory PlatformAuditEntry.fromMap(Map<String, dynamic> map) {
    return PlatformAuditEntry(
      id: map['id'] as String,
      uid: map['uid'] as String? ?? '',
      action: map['action'] as String? ?? '',
      orgId: map['orgId'] as String?,
      details: map['details'] != null ? Map<String, dynamic>.from(map['details'] as Map) : const {},
      at: map['at'] != null ? DateTime.tryParse(map['at'] as String) : null,
    );
  }
}
