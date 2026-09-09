import 'asset_model.dart';

class AssetImportFailure {
  final Map<String, dynamic> row;
  final String reason;

  const AssetImportFailure({required this.row, required this.reason});

  factory AssetImportFailure.fromJson(Map<String, dynamic> json) => AssetImportFailure(
        row: (json['row'] as Map).cast<String, dynamic>(),
        reason: json['reason'] as String? ?? 'Unknown error.',
      );
}

class AssetImportResult {
  final List<AssetModel> saved;
  final List<AssetImportFailure> failed;

  const AssetImportResult({required this.saved, required this.failed});

  factory AssetImportResult.fromJson(Map<String, dynamic> json) => AssetImportResult(
        saved: (json['saved'] as List? ?? [])
            .map((e) => AssetModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        failed: (json['failed'] as List? ?? [])
            .map((e) => AssetImportFailure.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
