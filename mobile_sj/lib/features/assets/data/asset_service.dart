import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../model/asset_model.dart';
import '../model/asset_import_result.dart';

// Fields read off an asset tag/sticker photo via server-side OCR, meant to
// pre-fill the Add Asset form for review — not saved as-is.
typedef AssetOcrResult = ({String? description, String? serialNumber});

class AssetService {
  final Dio _dio = ApiClient.instance.dio;

  Future<List<AssetModel>> getAll({
    String? search,
    int page = 0,
    int size = 20,
    int? categoryId,
    int? officeId,
    String? condition,
    String? lifecycleStatus,
  }) async {
    try {
      final res = await _dio.get('/assets', queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
        'page': page,
        'size': size,
        if (categoryId != null) 'categoryId': categoryId,
        if (officeId != null) 'officeId': officeId,
        if (condition != null && condition.isNotEmpty) 'condition': condition,
        if (lifecycleStatus != null && lifecycleStatus.isNotEmpty) 'lifecycleStatus': lifecycleStatus,
      });
      return (res.data as List).map((e) => AssetModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<int> count({
    String? search,
    int? categoryId,
    int? officeId,
    String? condition,
    String? lifecycleStatus,
  }) async {
    try {
      final res = await _dio.get('/assets/count', queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
        if (categoryId != null) 'categoryId': categoryId,
        if (officeId != null) 'officeId': officeId,
        if (condition != null && condition.isNotEmpty) 'condition': condition,
        if (lifecycleStatus != null && lifecycleStatus.isNotEmpty) 'lifecycleStatus': lifecycleStatus,
      });
      return res.data as int;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<AssetModel> getById(int id) async {
    try {
      final res = await _dio.get('/assets/$id');
      return AssetModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<AssetModel> create(Map<String, dynamic> data, {String? idempotencyKey}) async {
    try {
      final res = await _dio.post('/assets', data: data,
          options: idempotencyKey != null ? Options(headers: {'Idempotency-Key': idempotencyKey}) : null);
      return AssetModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  // Reads a photo of an asset tag/sticker via server-side OCR (Gemini vision)
  // — the image is processed in memory on the backend and never persisted.
  Future<AssetOcrResult> scanLabel(String imagePath) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(imagePath),
      });
      final res = await _dio.post('/assets/scan-label', data: formData);
      final json = res.data as Map<String, dynamic>;
      return (description: json['description'] as String?, serialNumber: json['serialNumber'] as String?);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<AssetModel> update(int id, Map<String, dynamic> data) async {
    try {
      final res = await _dio.put('/assets/$id', data: data);
      return AssetModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> delete(int id, {String? reason}) async {
    try {
      await _dio.delete('/assets/$id',
          data: reason != null ? {'deleteReason': reason} : null);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  // Create-only bulk import — see AssetImportRow.java for the exact field
  // names each row map must use.
  Future<AssetImportResult> bulkImport(List<Map<String, String>> rows) async {
    try {
      final res = await _dio.post('/assets/bulk-import', data: rows);
      return AssetImportResult.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}
