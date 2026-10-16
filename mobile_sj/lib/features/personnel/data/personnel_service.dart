import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';

/// One row of the Personnel page. Personnel are the accounts (each made on Accounts);
/// this is the only place an admin sets an account's office, position and contact info.
class PersonnelRecord {
  final int id;
  final String fullName;
  final String? username;
  final String? position;
  final int? officeId;
  final String? officeName;
  final String? contactInfo;
  final String? userRole; // ADMIN | STAFF
  final bool userActive;

  const PersonnelRecord({
    required this.id,
    required this.fullName,
    this.username,
    this.position,
    this.officeId,
    this.officeName,
    this.contactInfo,
    this.userRole,
    this.userActive = true,
  });

  factory PersonnelRecord.fromJson(Map<String, dynamic> json) {
    final office = json['office'] as Map<String, dynamic>?;
    return PersonnelRecord(
      id: (json['id'] as num).toInt(),
      fullName: json['fullName'] as String? ?? '—',
      username: json['username'] as String?,
      position: json['position'] as String?,
      officeId: (office?['id'] as num?)?.toInt(),
      officeName: office?['officeName'] as String?,
      contactInfo: json['contactInfo'] as String?,
      userRole: json['userRole'] as String?,
      userActive: json['userActive'] != false,
    );
  }

  bool get isAdmin => userRole == 'ADMIN';
  bool get needsOffice => officeId == null && userActive;
}

class PersonnelService {
  final Dio _dio = ApiClient.instance.dio;

  Future<List<PersonnelRecord>> getAll() async {
    try {
      final res = await _dio.get('/personnel');
      return (res.data as List).map((e) => PersonnelRecord.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// PUT /api/personnel/{id} — office is required; position and contact info are optional.
  Future<PersonnelRecord> update(int id, {required int officeId, String? position, String? contactInfo}) async {
    try {
      final res = await _dio.put('/personnel/$id', data: {
        'officeId': officeId,
        'position': position,
        'contactInfo': contactInfo,
      });
      return PersonnelRecord.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}
