class UserModel {
  final String username;
  final String role; // ADMIN | STAFF
  final String? privacyAcknowledgedAt;

  const UserModel({required this.username, required this.role, this.privacyAcknowledgedAt});

  // /api/auth/login, /api/auth/me, and /api/auth/force-change-password all
  // return the same shape: { username, role, privacyAcknowledgedAt, ... }.
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
      username: json['username'] as String,
      role: rawRole.replaceFirst('ROLE_', ''),
      privacyAcknowledgedAt: json['privacyAcknowledgedAt'] as String?,
    );
  }

  bool get isAdmin => role == 'ADMIN';
}
