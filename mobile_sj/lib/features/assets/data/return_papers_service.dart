import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../model/return_papers_model.dart';

/// The asset's Property Return Slips and PARs - the web's "PARs & Return Slips" tab.
class ReturnPapersService {
  final Dio _dio = ApiClient.instance.dio;

  Future<ReturnPapersModel> forAsset(int assetId) async {
    try {
      final res = await _dio.get('/assets/$assetId/return-papers');
      return ReturnPapersModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}

final returnPapersProvider =
    FutureProvider.autoDispose.family<ReturnPapersModel, int>((ref, assetId) => ReturnPapersService().forAsset(assetId));
