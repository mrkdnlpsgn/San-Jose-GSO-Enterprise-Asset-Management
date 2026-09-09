import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../model/maintenance_model.dart';

class MaintenanceService {
  final Dio _dio = ApiClient.instance.dio;

  Future<List<MaintenanceModel>> getAll({
    String? search,
    int page = 0,
    int size = 20,
    String? maintenanceType,
    String? status,
  }) async {
    try {
      final res = await _dio.get('/maintenance', queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
        'page': page,
        'size': size,
        if (maintenanceType != null && maintenanceType.isNotEmpty) 'maintenanceType': maintenanceType,
        if (status != null && status.isNotEmpty) 'status': status,
      });
      return (res.data as List).map((e) => MaintenanceModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<int> count({String? search, String? maintenanceType, String? status}) async {
    try {
      final res = await _dio.get('/maintenance/count', queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
        if (maintenanceType != null && maintenanceType.isNotEmpty) 'maintenanceType': maintenanceType,
        if (status != null && status.isNotEmpty) 'status': status,
      });
      return res.data as int;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<MaintenanceModel> getById(int id) async {
    try {
      final res = await _dio.get('/maintenance/$id');
      return MaintenanceModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<List<MaintenanceModel>> getByAsset(int assetId) async {
    try {
      final res = await _dio.get('/maintenance/asset/$assetId');
      return (res.data as List).map((e) => MaintenanceModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<MaintenanceModel> create(Map<String, dynamic> data, {String? idempotencyKey}) async {
    try {
      final res = await _dio.post('/maintenance', data: data,
          options: idempotencyKey != null ? Options(headers: {'Idempotency-Key': idempotencyKey}) : null);
      return MaintenanceModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<MaintenanceModel> update(int id, Map<String, dynamic> data) async {
    try {
      final res = await _dio.put('/maintenance/$id', data: data);
      return MaintenanceModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> delete(int id, {String? reason}) async {
    try {
      await _dio.delete('/maintenance/$id',
          data: reason != null ? {'deleteReason': reason} : null);
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}
