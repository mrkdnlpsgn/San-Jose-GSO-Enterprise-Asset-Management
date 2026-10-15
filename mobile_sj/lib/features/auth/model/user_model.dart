// How a role is shown to people (the stored value stays ADMIN / STAFF).
String roleLabel(String role) => role == 'ADMIN' ? 'Administrator' : 'GSO Staff';

class UserModel {
  final int? id;
  final String username;
  final String? fullName;
  final String? officeName;
  final String role; // ADMIN | STAFF
  final String? privacyAcknowledgedAt;

  const UserModel({
    this.id,
    required this.username,
    this.fullName,
    this.officeName,
    required this.role,
    this.privacyAcknowledgedAt,
  });

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
      role: rawRole.replaceFirst('ROLE_', ''),
      privacyAcknowledgedAt: json['privacyAcknowledgedAt'] as String?,
    );
  }

  bool get isAdmin => role == 'ADMIN';

  /// Full name when the account has one, otherwise the username.
  String get displayName => (fullName != null && fullName!.trim().isNotEmpty) ? fullName!.trim() : username;
}
