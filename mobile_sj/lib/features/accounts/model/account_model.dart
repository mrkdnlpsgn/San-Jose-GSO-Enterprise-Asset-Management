class AccountModel {
  final int id;
  final String username;
  final String? email;
  final String fullName;
  final String role; // ADMIN | ADMIN_STAFF | STAFF
  final int? officeId;
  final String? officeName;
  final bool isActive;

  const AccountModel({
    required this.id,
    required this.username,
    this.email,
    required this.fullName,
    required this.role,
    this.officeId,
    this.officeName,
    required this.isActive,
  });

  factory AccountModel.fromJson(Map<String, dynamic> json) => AccountModel(
        id: json['id'] as int,
        username: json['username'] as String,
        email: json['email'] as String?,
        fullName: json['fullName'] as String,
        role: json['role'] as String,
        officeId: json['officeId'] as int?,
        officeName: json['officeName'] as String?,
        isActive: json['isActive'] as bool? ?? true,
      );
}
