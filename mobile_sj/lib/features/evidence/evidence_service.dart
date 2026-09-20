import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';

/// One evidence photo attached to a record (maintenance record, asset, or disposal record).
class EvidencePhoto {
  final int id;
  final String url; // relative, e.g. /uploads/assets/<uuid>.jpg
  final String? originalFilename;
  final int? fileSize;
  final String? uploadedByName;
  final String? uploadedAt;

  const EvidencePhoto({
    required this.id,
    required this.url,
    this.originalFilename,
    this.fileSize,
    this.uploadedByName,
    this.uploadedAt,
  });

  factory EvidencePhoto.fromJson(Map<String, dynamic> json) => EvidencePhoto(
        id: json['id'] as int,
        url: json['url'] as String,
        originalFilename: json['originalFilename'] as String?,
        fileSize: (json['fileSize'] as num?)?.toInt(),
        uploadedByName: json['uploadedByName'] as String?,
        uploadedAt: json['uploadedAt'] as String?,
      );

  /// Full URL for Image.network — uploads are served from the backend root, outside /api.
  String get fullUrl {
    final base = ApiClient.instance.dio.options.baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    return '$base$url';
  }
}

/// Evidence photos of one record. `path` is that record's photo endpoint, e.g.
/// /maintenance/5/photos, /assets/5/evidence or /disposal/5/evidence:
/// GET lists, POST uploads a `file`, DELETE {path}/{photoId} removes one.
class EvidenceService {
  final String path;
  final Dio _dio = ApiClient.instance.dio;

  EvidenceService(this.path);

  Future<List<EvidencePhoto>> list() async {
    try {
      final res = await _dio.get(path);
      return (res.data as List).map((e) => EvidencePhoto.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  static DioMediaType _mediaTypeFor(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'png' => DioMediaType('image', 'png'),
      'webp' => DioMediaType('image', 'webp'),
      'heic' => DioMediaType('image', 'heic'),
      'heif' => DioMediaType('image', 'heif'),
      _ => DioMediaType('image', 'jpeg'),
    };
  }

  Future<EvidencePhoto> upload(String filePath, String filename) async {
    try {
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: filename, contentType: _mediaTypeFor(filename)),
      });
      final res = await _dio.post(path, data: form);
      return EvidencePhoto.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> delete(int photoId) async {
    try {
      await _dio.delete('$path/$photoId');
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}
