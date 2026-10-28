// How a role is shown to people (the stored value stays ADMIN / ADMIN_STAFF / STAFF).
String roleLabel(String role) => switch (role) {
      'ADMIN' => 'Administrator',
      'ADMIN_STAFF' => 'Admin-Staff',
      _ => 'GSO Staff',
    };

class UserModel {
  final int? id;
  final String username;
  final String? fullName;
  final String? officeName;
  /// The office an admin assigned this account on the Personnel page (null = none yet).
  final int? officeId;
  /// Every office assigned (primary first); staff see the assets of all of them.
  final List<int> officeIds;
  final String role; // ADMIN | ADMIN_STAFF | STAFF
  final String? privacyAcknowledgedAt;
  /// Root-relative, e.g. /uploads/avatars/3-<uuid>.jpg - null when no picture is set.
  final String? avatarUrl;

  const UserModel({
    this.id,
    required this.username,
    this.fullName,
    this.officeName,
    this.officeId,
    this.officeIds = const [],
    required this.role,
    this.privacyAcknowledgedAt,
    this.avatarUrl,
  });

  UserModel copyWith({String? privacyAcknowledgedAt, String? Function()? avatarUrl}) => UserModel(
        id: id,
        username: username,
        fullName: fullName,
        officeName: officeName,
        officeId: officeId,
        officeIds: officeIds,
        role: role,
        privacyAcknowledgedAt: privacyAcknowledgedAt ?? this.privacyAcknowledgedAt,
        avatarUrl: avatarUrl != null ? avatarUrl() : this.avatarUrl,
      );

  // /api/auth/login, /api/auth/me, and /api/auth/force-change-password all
  // return the same shape: { id, username, fullName, officeName, role, privacyAcknowledgedAt, ... }.
  // The authorities fallback below predates that unification and is kept only
  // as a defensive fallback.
  factory UserModel.fromJson(Map<String, dynamic> json) {
    String rawRole;
    if (json['role'] != null) {
      rawRole = json['role'] as String;
    } else {
      final authorities = (json['authorities'] as List?) ?? [];
      rawRole = authorities.isNotEmpty
          ? (authorities.first['authority'] as String)
          : 'ROLE_STAFF';
    }
    return UserModel(
      id: (json['id'] as num?)?.toInt(),
      username: json['username'] as String,
      fullName: json['fullName'] as String?,
      officeName: json['officeName'] as String?,
      officeId: (json['officeId'] as num?)?.toInt(),
      officeIds: [for (final id in (json['officeIds'] as List?) ?? const []) (id as num).toInt()],
      role: rawRole.replaceFirst('ROLE_', ''),
      privacyAcknowledgedAt: json['privacyAcknowledgedAt'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }

  // Same shape fromJson reads - used to remember the signed-in user on the phone.
  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'fullName': fullName,
        'officeName': officeName,
        'officeId': officeId,
        'officeIds': officeIds,
        'role': role,
        'privacyAcknowledgedAt': privacyAcknowledgedAt,
        'avatarUrl': avatarUrl,
      };

  bool get isAdmin => role == 'ADMIN';

  /// Admin-Staff: works like staff (its changes are requests, it can't approve or reject),
  /// but sees the entire inventory and every staff request.
  bool get isAdminStaff => role == 'ADMIN_STAFF';

  /// Sees every office's assets and everyone's requests.
  bool get seesAllAssets => isAdmin || isAdminStaff;

  /// Full name when the account has one, otherwise the username.
  String get displayName => (fullName != null && fullName!.trim().isNotEmpty) ? fullName!.trim() : username;
}
