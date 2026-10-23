import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/offline/asset_snapshot.dart';
import '../model/asset_model.dart';
import '../model/asset_import_result.dart';

// Fields read off an asset tag/sticker photo, or a property document (e.g. a
// Property Acknowledgment Receipt listing technical specifications), via
// server-side OCR - meant to pre-fill the Add Asset form for review, not
// saved as-is.
typedef AssetOcrResult = ({String? description, String? serialNumber, String? specifications});

/// One QR sticker for bulk printing: the signed QR text and the property number under it.
typedef QrSticker = ({String propertyNumber, String qrPayload});

class AssetService {
  final Dio _dio = ApiClient.instance.dio;
  final AssetSnapshot _snapshot = AssetSnapshot.instance;

  /// Offline (or the server didn't answer): read from the asset list saved on the phone,
  /// if there is one; otherwise the original error stands.
  Future<T> _orSnapshot<T>(Object error, Future<T?> Function() local) async {
    final e = ApiException.from(error);
    if (!e.serverAsleep) throw e;
    final fromPhone = await local();
    if (fromPhone == null) throw e;
    return fromPhone;
  }

  Future<List<AssetModel>> getAll({
    String? search,
    int page = 0,
    int size = 20,
    int? categoryId,
    int? officeId,
    String? condition,
    String? lifecycleStatus,
  }) async {
    Future<List<AssetModel>?> local() => _snapshot.query(
        search: search,
        page: page,
        size: size,
        categoryId: categoryId,
        officeId: officeId,
        condition: condition,
        lifecycleStatus: lifecycleStatus);
    // The whole list, unfiltered - the same download the offline copy is made of.
    final everything = page == 0 &&
        size >= 100000 &&
        (search == null || search.isEmpty) &&
        categoryId == null &&
        officeId == null &&
        (condition ?? '').isEmpty &&
        (lifecycleStatus ?? '').isEmpty;
    if (ApiClient.instance.deviceOffline) {
      final fromPhone = await local();
      if (fromPhone != null) return fromPhone;
    }
    try {
      final res = await _dio.get('/assets',
          queryParameters: {
            if (search != null && search.isNotEmpty) 'search': search,
            'page': page,
            'size': size,
            if (categoryId != null) 'categoryId': categoryId,
            if (officeId != null) 'officeId': officeId,
            if (condition != null && condition.isNotEmpty) 'condition': condition,
            if (lifecycleStatus != null && lifecycleStatus.isNotEmpty) 'lifecycleStatus': lifecycleStatus,
          },
          // kept as the offline asset list instead of a second copy in the response cache
          options: everything ? Options(extra: {'noCache': true}) : null);
      final rows = res.data as List;
      if (everything) {
        await _snapshot.replaceAll(rows);
        return (await local()) ?? const [];
      }
      return rows.map((e) => AssetModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      return _orSnapshot(e, local);
    }
  }

  /// Downloads every asset the account can see into the offline copy.
  Future<void> refreshOfflineCopy() => getAll(size: 100000);

  // Every device of one group - loaded when a group is opened, so the view doesn't depend on
  // which page (or search results) happened to be loaded in the list.
  Future<List<AssetModel>> getGroup(String groupId) async {
    try {
      final res = await _dio.get('/assets/group/$groupId');
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
    Future<int?> local() => _snapshot.count(
        search: search,
        categoryId: categoryId,
        officeId: officeId,
        condition: condition,
        lifecycleStatus: lifecycleStatus);
    if (ApiClient.instance.deviceOffline) {
      final fromPhone = await local();
      if (fromPhone != null) return fromPhone;
    }
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
      return _orSnapshot(e, local);
    }
  }

  Future<AssetModel> getById(int id) async {
    // added offline (negative id) or no network: the phone's copy, with waiting edits
    if (id < 0 || ApiClient.instance.deviceOffline) {
      final fromPhone = await _snapshot.byId(id);
      if (fromPhone != null) return fromPhone;
    }
    try {
      final res = await _dio.get('/assets/$id');
      return AssetModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      return _orSnapshot(e, () => _snapshot.byId(id));
    }
  }

  /// Sticker data for many assets at once (bulk QR export), in the order given. The server
  /// leaves out deleted assets and, for staff, assets outside their office, and logs the export.
  /// Offline: built from the asset list saved on the phone (its QR text is the same signed text).
  Future<List<QrSticker>> qrStickers(List<int> ids) async {
    try {
      final res = await _dio.post('/assets/qr-stickers', data: {'ids': ids});
      return (res.data as List)
          .cast<Map<String, dynamic>>()
          .map((m) => (propertyNumber: m['propertyNumber'] as String, qrPayload: m['qrPayload'] as String))
          .toList();
    } catch (e) {
      return _orSnapshot(e, () async {
        final out = <QrSticker>[];
        for (final id in ids) {
          final a = await _snapshot.byId(id);
          if (a?.qrPayload != null) out.add((propertyNumber: a!.propertyNumber, qrPayload: a.qrPayload!));
        }
        return out;
      });
    }
  }

  /// Checks a scanned sticker's signature on the server:
  /// VERIFIED, UNSIGNED, INVALID or NOT_FOUND.
  Future<String> verifyQr(String code) async {
    try {
      final res = await _dio.get('/assets/verify-qr', queryParameters: {'code': code});
      return (res.data as Map<String, dynamic>)['status'] as String;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<AssetModel> create(Map<String, dynamic> data, {String? idempotencyKey}) async {
    try {
      final res = await _dio.post('/assets',
          data: data, options: idempotencyKey != null ? Options(headers: {'Idempotency-Key': idempotencyKey}) : null);
      await _snapshot.upsert(res.data as Map<String, dynamic>);
      return AssetModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  // Reads a photo of an asset tag/sticker via server-side OCR (Gemini vision)
  // - the image is processed in memory on the backend and never persisted.
  Future<AssetOcrResult> scanLabel(String imagePath) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(imagePath),
      });
      final res = await _dio.post('/assets/scan-label', data: formData);
      final json = res.data as Map<String, dynamic>;
      return (
        description: json['description'] as String?,
        serialNumber: json['serialNumber'] as String?,
        specifications: json['specifications'] as String?,
      );
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<AssetModel> update(int id, Map<String, dynamic> data) async {
    try {
      final res = await _dio.put('/assets/$id', data: data);
      await _snapshot.upsert(res.data as Map<String, dynamic>);
      return AssetModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> delete(int id, {String? reason}) async {
    try {
      await _dio.delete('/assets/$id', data: reason != null ? {'deleteReason': reason} : null);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  // Create-only bulk import - see AssetImportRow.java for the exact field
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
