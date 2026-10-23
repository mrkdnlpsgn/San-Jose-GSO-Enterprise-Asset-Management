import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';

/// One line of "Your recent activity" - the caller's own audit log rows.
class MyActivity {
  final String action;
  final String? details;
  final String? loggedAt;
  const MyActivity({required this.action, this.details, this.loggedAt});

  factory MyActivity.fromJson(Map<String, dynamic> json) => MyActivity(
        action: json['action'] as String? ?? '',
        details: json['details'] as String?,
        loggedAt: json['loggedAt'] as String?,
      );
}

/// GET /api/users/me/overview - what the web's My Account tab shows beyond the login payload.
class MyOverview {
  final String? email;
  final String? memberSince;
  final bool twoFactorEnabled;
  final String? officeName;
  final List<MyActivity> recentActivity;

  const MyOverview({
    this.email,
    this.memberSince,
    required this.twoFactorEnabled,
    this.officeName,
    this.recentActivity = const [],
  });

  factory MyOverview.fromJson(Map<String, dynamic> json) => MyOverview(
        email: json['email'] as String?,
        memberSince: json['memberSince'] as String?,
        twoFactorEnabled: json['twoFactorEnabled'] == true,
        officeName: json['officeName'] as String?,
        recentActivity: ((json['recentActivity'] as List?) ?? [])
            .map((e) => MyActivity.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  MyOverview withTwoFactor(bool enabled) => MyOverview(
        email: email,
        memberSince: memberSince,
        twoFactorEnabled: enabled,
        officeName: officeName,
        recentActivity: recentActivity,
      );
}

/// The signed-in user's own account - same endpoints as the web's userService.
class MyAccountService {
  final Dio _dio = ApiClient.instance.dio;

  Future<MyOverview> overview() async {
    try {
      final res = await _dio.get('/users/me/overview');
      return MyOverview.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Returns the new avatarUrl. The backend takes JPEG, PNG or WEBP up to 2 MB.
  Future<String?> uploadAvatar(String filePath, String filename) async {
    final ext = filename.split('.').last.toLowerCase();
    final type = switch (ext) {
      'png' => DioMediaType('image', 'png'),
      'webp' => DioMediaType('image', 'webp'),
      _ => DioMediaType('image', 'jpeg'),
    };
    try {
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: filename, contentType: type),
      });
      final res = await _dio.post('/users/me/avatar', data: form);
      return (res.data as Map<String, dynamic>)['avatarUrl'] as String?;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> removeAvatar() async {
    try {
      await _dio.delete('/users/me/avatar');
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Turning it off needs the current password.
  Future<bool> setTwoFactor(bool enabled, {String? currentPassword}) async {
    try {
      final res = await _dio.put('/users/me/two-factor', data: {
        'enabled': enabled,
        if (currentPassword != null) 'currentPassword': currentPassword,
      });
      return (res.data as Map<String, dynamic>)['twoFactorEnabled'] == true;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Forgets every device remembered for 2-step - and ends every session, this one included.
  Future<void> forgetDevices() async {
    try {
      await _dio.post('/users/me/forget-devices');
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}
