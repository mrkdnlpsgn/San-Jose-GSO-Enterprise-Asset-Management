import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../features/assets/model/asset_model.dart';

class ReferenceService {
  final Dio _dio = ApiClient.instance.dio;

  Future<List<CategoryModel>> getCategories() async {
    try {
      final res = await _dio.get('/categories');
      return (res.data as List).map((e) => CategoryModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<List<OfficeModel>> getOffices() async {
    try {
      final res = await _dio.get('/offices');
      return (res.data as List).map((e) => OfficeModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<CategoryModel> suggestCategory(String description) async {
    try {
      final res = await _dio.post('/categories/suggest', data: {'description': description});
      return CategoryModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<CategoryModel> createCategory(String categoryName, String? description, {String? idempotencyKey}) async {
    try {
      final res = await _dio.post('/categories',
          data: {'categoryName': categoryName, 'description': description},
          options: idempotencyKey != null ? Options(headers: {'Idempotency-Key': idempotencyKey}) : null);
      return CategoryModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<CategoryModel> updateCategory(int id, String categoryName, String? description) async {
    try {
      final res = await _dio.put('/categories/$id',
          data: {'categoryName': categoryName, 'description': description});
      return CategoryModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> deleteCategory(int id) async {
    try {
      await _dio.delete('/categories/$id');
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<OfficeModel> createOffice(String officeName, int? headUserId, {String? idempotencyKey}) async {
    try {
      final res = await _dio.post('/offices',
          data: {'officeName': officeName, 'headUserId': headUserId},
          options: idempotencyKey != null ? Options(headers: {'Idempotency-Key': idempotencyKey}) : null);
      return OfficeModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<OfficeModel> updateOffice(int id, String officeName, int? headUserId) async {
    try {
      final res = await _dio.put('/offices/$id',
          data: {'officeName': officeName, 'headUserId': headUserId});
      return OfficeModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> deleteOffice(int id) async {
    try {
      await _dio.delete('/offices/$id');
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}
