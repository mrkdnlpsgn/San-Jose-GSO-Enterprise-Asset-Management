import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../model/disposal_model.dart';

class DisposalService {
  final Dio _dio = ApiClient.instance.dio;

  Future<List<DisposalModel>> getAll({
    String? search,
    int page = 0,
    int size = 20,
    String? recommendedMethod,
    String? disposalStatus,
  }) async {
    try {
      final res = await _dio.get('/disposal', queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
        'page': page,
        'size': size,
        if (recommendedMethod != null && recommendedMethod.isNotEmpty) 'recommendedMethod': recommendedMethod,
        if (disposalStatus != null && disposalStatus.isNotEmpty) 'disposalStatus': disposalStatus,
      });
      return (res.data as List).map((e) => DisposalModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<int> count({String? search, String? recommendedMethod, String? disposalStatus}) async {
    try {
      final res = await _dio.get('/disposal/count', queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
        if (recommendedMethod != null && recommendedMethod.isNotEmpty) 'recommendedMethod': recommendedMethod,
        if (disposalStatus != null && disposalStatus.isNotEmpty) 'disposalStatus': disposalStatus,
      });
      return res.data as int;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<DisposalModel> getById(int id) async {
    try {
      final res = await _dio.get('/disposal/$id');
      return DisposalModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<List<DisposalModel>> getByAsset(int assetId) async {
    try {
      final res = await _dio.get('/disposal/asset/$assetId');
      return (res.data as List).map((e) => DisposalModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<DisposalModel> create(Map<String, dynamic> data, {String? idempotencyKey}) async {
    try {
      final res = await _dio.post('/disposal', data: data,
          options: idempotencyKey != null ? Options(headers: {'Idempotency-Key': idempotencyKey}) : null);
      return DisposalModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<DisposalModel> update(int id, Map<String, dynamic> data) async {
    try {
      final res = await _dio.put('/disposal/$id', data: data);
      return DisposalModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> delete(int id, {String? reason}) async {
    try {
      await _dio.delete('/disposal/$id',
          data: reason != null ? {'deleteReason': reason} : null);
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}
