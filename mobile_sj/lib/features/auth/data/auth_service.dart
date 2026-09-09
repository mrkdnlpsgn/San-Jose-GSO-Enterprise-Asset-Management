import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../model/user_model.dart';

// Thrown by [AuthService.login] when the account has a temporary password
// (fresh account or admin-mediated reset) — the backend withholds the session
// until the caller collects a new password via [AuthService.forceChangePassword].
class MustChangePasswordRequired implements Exception {
  final String username;
  MustChangePasswordRequired(this.username);
}

// Thrown by [AuthService.login] when the account has 2FA enabled (every account
// except admin and ict_staff) — the backend emails a code and withholds the
// session until the caller verifies it via [AuthService.verifyLoginOtp].
class RequiresTwoFactor implements Exception {
  final String username;
  RequiresTwoFactor(this.username);
}

class AuthService {
  final Dio _dio = ApiClient.instance.dio;

  // POST /api/auth/login — body uses "identifier" (username or email), not "email"
  Future<UserModel> login(String identifier, String password) async {
    try {
      final res = await _dio.post('/auth/login', data: {
        'identifier': identifier,
        'password': password,
      });
      // Correct credentials, but a temp password — no session/cookie yet, backend
      // returns { mustChangePassword: true, username } instead of { user: {...} }.
      if (res.data['mustChangePassword'] == true) {
        throw MustChangePasswordRequired(res.data['username'] as String);
      }
      // Correct credentials, but 2FA is enabled on this account — no session/cookie
      // yet, backend returns { requiresTwoFactor: true, username } instead.
      if (res.data['requiresTwoFactor'] == true) {
        throw RequiresTwoFactor(res.data['username'] as String);
      }
      // Backend returns { "user": { username, role, ... } }
      // Cookie is automatically stored by CookieManager
      return UserModel.fromJson(res.data['user'] as Map<String, dynamic>);
    } on MustChangePasswordRequired {
      rethrow;
    } on RequiresTwoFactor {
      rethrow;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  // POST /api/auth/login/verify-otp — completes a login that was interrupted by
  // 2FA: proves the emailed code and returns a real session, same shape as a
  // normal login response.
  Future<UserModel> verifyLoginOtp(String identifier, String otp) async {
    try {
      final res = await _dio.post('/auth/login/verify-otp', data: {
        'identifier': identifier,
        'otp': otp,
      });
      return UserModel.fromJson(res.data['user'] as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  // POST /api/auth/force-change-password — completes a login that was interrupted
  // by a mandatory password change: proves the temp password, then swaps it and
  // returns a real session, same shape as a normal login response.
  Future<UserModel> forceChangePassword(String identifier, String currentPassword, String newPassword) async {
    try {
      final res = await _dio.post('/auth/force-change-password', data: {
        'identifier': identifier,
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      });
      return UserModel.fromJson(res.data['user'] as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  // GET /api/auth/me — returns null on 401 (not logged in), throws on other errors
  Future<UserModel?> fetchCurrentUser() async {
    try {
      final res = await _dio.get('/auth/me');
      return UserModel.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) return null;
      throw ApiException.from(e);
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post('/auth/logout');
    } catch (_) {}
    await ApiClient.instance.clearCookies();
  }

  // POST /api/auth/acknowledge-privacy — records that the current user has
  // reviewed the Privacy, Terms & Conditions. Returns the new timestamp.
  Future<String> acknowledgePrivacy() async {
    try {
      final res = await _dio.post('/auth/acknowledge-privacy');
      return res.data['privacyAcknowledgedAt'] as String;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  // POST /api/auth/forgot-password/request — step 1: emails a one-time code to the
  // account's registered address. Requiring possession of the inbox (not just the
  // username) is what prevents anyone who merely knows/guesses a username from
  // taking over the account. Rate-limited server-side to once every 15 minutes.
  Future<void> requestPasswordReset(String username) async {
    try {
      await _dio.post('/auth/forgot-password/request', data: {'username': username});
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  // POST /api/auth/forgot-password/confirm — step 2: verify the emailed code and
  // set the new password in one call.
  Future<void> confirmPasswordReset(String username, String otp, String newPassword) async {
    try {
      await _dio.post('/auth/forgot-password/confirm', data: {
        'username': username,
        'otp': otp,
        'newPassword': newPassword,
      });
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}
