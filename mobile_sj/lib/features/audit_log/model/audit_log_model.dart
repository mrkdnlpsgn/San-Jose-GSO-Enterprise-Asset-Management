/// One entry of GET /api/audit-logs (admin only).
class AuditLogModel {
  final int id;
  final String action; // e.g. ASSET_TRANSFERRED, MAINTENANCE_UPDATED
  final String module; // e.g. Assets, Maintenance
  final String? details;
  final String? targetType;
  final int? targetId;
  final String loggedAt; // UTC, "…Z"
  final String? username;
  final String? fullName;

  const AuditLogModel({
    required this.id,
    required this.action,
    required this.module,
    this.details,
    this.targetType,
    this.targetId,
    required this.loggedAt,
    this.username,
    this.fullName,
  });

  factory AuditLogModel.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return AuditLogModel(
      id: (json['id'] as num).toInt(),
      action: json['action'] as String? ?? '',
      module: json['module'] as String? ?? '',
      details: json['details'] as String?,
      targetType: json['targetType'] as String?,
      targetId: (json['targetId'] as num?)?.toInt(),
      loggedAt: json['loggedAt'] as String? ?? '',
      username: user?['username'] as String?,
      fullName: user?['fullName'] as String?,
    );
  }

  /// "MAINTENANCE_UPDATED" → "Maintenance updated", "AI_RECOMMENDATION_GENERATED" → "AI recommendation generated".
  String get actionLabel {
    final words = [
      for (final w in action.toLowerCase().split('_'))
        if (w.isNotEmpty) w == 'ai' || w == 'qr' || w == 'otp' ? w.toUpperCase() : w,
    ];
    if (words.isEmpty) return 'Activity';
    final text = words.join(' ');
    return text[0].toUpperCase() + text.substring(1);
  }

  /// Who did it: full name when known, otherwise the username.
  String get performedBy {
    final name = fullName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return username ?? 'System';
  }
}

/// GET /api/audit-logs/archive/summary - old entries moved out of the live list.
class AuditArchiveSummary {
  final int retentionDays;
  final int liveCount;
  final int archivedCount;
  final String? archivedOldest;
  final String? archivedNewest;
  /// Only from "archive now": how many entries that run moved.
  final int? moved;

  const AuditArchiveSummary({
    required this.retentionDays,
    required this.liveCount,
    required this.archivedCount,
    this.archivedOldest,
    this.archivedNewest,
    this.moved,
  });

  factory AuditArchiveSummary.fromJson(Map<String, dynamic> json) => AuditArchiveSummary(
        retentionDays: (json['retentionDays'] as num?)?.toInt() ?? 365,
        liveCount: (json['liveCount'] as num?)?.toInt() ?? 0,
        archivedCount: (json['archivedCount'] as num?)?.toInt() ?? 0,
        archivedOldest: json['archivedOldest'] as String?,
        archivedNewest: json['archivedNewest'] as String?,
        moved: (json['moved'] as num?)?.toInt(),
      );

  /// "1 year", "2 years", "90 days".
  String get retentionLabel => retentionDays % 365 == 0
      ? '${retentionDays ~/ 365} year${retentionDays == 365 ? '' : 's'}'
      : '$retentionDays days';
}
