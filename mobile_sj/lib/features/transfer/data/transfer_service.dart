import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../model/transfer_model.dart';

/// Same endpoints as the web Transfer Asset page (/api/transfers).
class TransferService {
  final Dio _dio = ApiClient.instance.dio;

  /// Admin: every request. Staff: only the ones they filed (the backend scopes it).
  Future<List<TransferModel>> list({String? status}) async {
    try {
      final res = await _dio.get('/transfers', queryParameters: {if (status != null) 'status': status});
      return (res.data as List).map((e) => TransferModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// An admin's transfer is applied at once ("APPLIED"); a staff member's waits for
  /// approval ("PENDING_APPROVAL"). Returns that status.
  Future<String> submit({
    required int assetId,
    required int toOfficeId,
    int? toPersonnelId,
    String? reason,
  }) async {
    try {
      final res = await _dio.post('/transfers', data: {
        'assetId': assetId,
        'toOfficeId': toOfficeId,
        'toPersonnelId': toPersonnelId,
        // no toLocation: the server sets the asset's location to the new office's name
        'reason': (reason == null || reason.trim().isEmpty) ? null : reason.trim(),
      });
      return (res.data as Map<String, dynamic>)['status'] as String? ?? 'APPLIED';
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> approve(int id) async {
    try {
      await _dio.post('/transfers/$id/approve');
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> reject(int id, String note) async {
    try {
      await _dio.post('/transfers/$id/reject', data: {'note': note});
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}
