import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../model/deleted_asset_model.dart';
import '../model/deleted_maintenance_model.dart';
import '../model/deleted_disposal_model.dart';

class RecycleBinService {
  final Dio _dio = ApiClient.instance.dio;

  Future<List<DeletedAssetModel>> getDeletedAssets() async {
    try {
      final res = await _dio.get('/deleted-records/assets');
      return (res.data as List).map((e) => DeletedAssetModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<List<DeletedMaintenanceModel>> getDeletedMaintenance() async {
    try {
      final res = await _dio.get('/deleted-records/maintenance');
      return (res.data as List).map((e) => DeletedMaintenanceModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<List<DeletedDisposalModel>> getDeletedDisposal() async {
    try {
      final res = await _dio.get('/deleted-records/disposal');
      return (res.data as List).map((e) => DeletedDisposalModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> restoreAsset(int id) async {
    try {
      await _dio.post('/deleted-records/assets/$id/restore');
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> restoreMaintenance(int id) async {
    try {
      await _dio.post('/deleted-records/maintenance/$id/restore');
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> restoreDisposal(int id) async {
    try {
      await _dio.post('/deleted-records/disposal/$id/restore');
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  // Step-up 2FA — emails a one-time code to the current user before a permanent delete.
  Future<void> requestDeleteOtp() async {
    try {
      await _dio.post('/auth/delete-otp/request');
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  // Each permanently deletes both the underlying record and its Recycle Bin
  // snapshot — irreversible, and requires the OTP from requestDeleteOtp().
  Future<void> permanentDeleteAsset(int id, String otp) async {
    try {
      await _dio.post('/deleted-records/assets/$id/permanent-delete', data: {'otp': otp});
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> permanentDeleteMaintenance(int id, String otp) async {
    try {
      await _dio.post('/deleted-records/maintenance/$id/permanent-delete', data: {'otp': otp});
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> permanentDeleteDisposal(int id, String otp) async {
    try {
      await _dio.post('/deleted-records/disposal/$id/permanent-delete', data: {'otp': otp});
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}
