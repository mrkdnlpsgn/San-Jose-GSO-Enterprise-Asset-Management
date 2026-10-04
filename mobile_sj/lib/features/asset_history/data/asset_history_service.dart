import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../model/asset_history_model.dart';
import '../model/edit_request_model.dart';

class AssetHistoryService {
  final Dio _dio = ApiClient.instance.dio;

  Future<List<AssetHistoryModel>> getAll({String? search}) async {
    try {
      final res = await _dio.get('/asset-history', queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
      });
      return (res.data as List).map((e) => AssetHistoryModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  // Asset History screen — admin: everything; staff: every event (by anyone) on the assets
  // they're the accountable person for.
  Future<List<AssetHistoryModel>> getAccountable() async {
    try {
      final res = await _dio.get('/asset-history/accountable');
      return (res.data as List).map((e) => AssetHistoryModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  // Staff maintenance/disposal requests and their outcome. Admin: userId narrows to one
  // person (null = everyone). Staff: the backend always returns only their own.
  Future<List<EditRequestModel>> getRequests({int? userId}) async {
    try {
      final res = await _dio.get('/asset-history/requests', queryParameters: {
        if (userId != null) 'userId': userId,
      });
      return (res.data as List).map((e) => EditRequestModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<List<AssetHistoryModel>> getByAsset(int assetId) async {
    try {
      final res = await _dio.get('/asset-history/asset/$assetId');
      return (res.data as List).map((e) => AssetHistoryModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}
