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
}
