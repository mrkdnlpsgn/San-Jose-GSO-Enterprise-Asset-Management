class DeletedDisposalModel {
  final int id;
  final String propertyNumber;
  final String assetDescription;
  final String recommendedMethod;
  final String disposalStatus;
  final String deletedByUsername;
  final String deletedAt;
  final String? deleteReason;

  const DeletedDisposalModel({
    required this.id,
    required this.propertyNumber,
    required this.assetDescription,
    required this.recommendedMethod,
    required this.disposalStatus,
    required this.deletedByUsername,
    required this.deletedAt,
    this.deleteReason,
  });

  factory DeletedDisposalModel.fromJson(Map<String, dynamic> json) => DeletedDisposalModel(
        id: json['id'] as int,
        propertyNumber: json['propertyNumber'] as String,
        assetDescription: json['assetDescription'] as String,
        recommendedMethod: json['recommendedMethod'] as String,
        disposalStatus: json['disposalStatus'] as String,
        deletedByUsername: json['deletedByUsername'] as String,
        deletedAt: json['deletedAt'] as String,
        deleteReason: json['deleteReason'] as String?,
      );
}
