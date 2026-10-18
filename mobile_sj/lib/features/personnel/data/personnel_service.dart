import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';

/// One row of the Personnel page. Personnel are the accounts (each made on Accounts);
/// this is the only place an admin sets an account's offices (one or more), position and contact info.
class PersonnelRecord {
  final int id;
  final String fullName;
  final String? username;
  final String? position;
  /// Primary office.
  final int? officeId;
  /// Every assigned office's name, comma-separated (primary first).
  final String? officeName;
  final List<int> officeIds;
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
    this.officeIds = const [],
    this.contactInfo,
    this.userRole,
    this.userActive = true,
  });

  factory PersonnelRecord.fromJson(Map<String, dynamic> json) {
    final office = json['office'] as Map<String, dynamic>?;
    final offices = [
      for (final o in (json['offices'] as List?) ?? const []) o as Map<String, dynamic>,
    ];
    if (offices.isEmpty && office != null) offices.add(office);
    return PersonnelRecord(
      id: (json['id'] as num).toInt(),
      fullName: json['fullName'] as String? ?? '—',
      username: json['username'] as String?,
      position: json['position'] as String?,
      officeId: (office?['id'] as num?)?.toInt(),
      officeName: offices.isEmpty ? null : offices.map((o) => o['officeName'] as String? ?? '—').join(', '),
      officeIds: [for (final o in offices) (o['id'] as num).toInt()],
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

  /// PUT /api/personnel/{id} — at least one office is required (the first is the primary);
  /// position and contact info are optional.
  Future<PersonnelRecord> update(int id, {required List<int> officeIds, String? position, String? contactInfo}) async {
    try {
      final res = await _dio.put('/personnel/$id', data: {
        'officeId': officeIds.first,
        'officeIds': officeIds,
        'position': position,
        'contactInfo': contactInfo,
      });
      return PersonnelRecord.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}
