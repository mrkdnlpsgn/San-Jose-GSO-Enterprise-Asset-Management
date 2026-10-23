import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../model/account_model.dart';

class AccountService {
  final Dio _dio = ApiClient.instance.dio;

  Future<List<AccountModel>> getAll({String? search}) async {
    try {
      final res = await _dio.get('/users', queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
      });
      return (res.data as List).map((e) => AccountModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<AccountModel> create(Map<String, dynamic> data, {String? idempotencyKey}) async {
    try {
      final res = await _dio.post('/users', data: data,
          options: idempotencyKey != null ? Options(headers: {'Idempotency-Key': idempotencyKey}) : null);
      return AccountModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<AccountModel> update(int id, Map<String, dynamic> data) async {
    try {
      final res = await _dio.put('/users/$id', data: data);
      return AccountModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> delete(int id) async {
    try {
      await _dio.delete('/users/$id');
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  // POST /api/users/{id}/reset-password - admin-mediated reset, also clears
  // any lockout state on the target account.
  Future<void> resetPassword(int id, String newPassword) async {
    try {
      await _dio.post('/users/$id/reset-password', data: {'newPassword': newPassword});
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  // PUT /api/users/me/password - self-service change, requires current password.
  Future<void> changePassword(String currentPassword, String newPassword) async {
    try {
      await _dio.put('/users/me/password', data: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      });
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}
