class DeletedAssetModel {
  final int id;
  final String propertyNumber;
  final String description;
  final String categoryName;
  final String officeName;
  final String deletedByUsername;
  final String deletedAt;
  final String? deleteReason;

  const DeletedAssetModel({
    required this.id,
    required this.propertyNumber,
    required this.description,
    required this.categoryName,
    required this.officeName,
    required this.deletedByUsername,
    required this.deletedAt,
    this.deleteReason,
  });

  factory DeletedAssetModel.fromJson(Map<String, dynamic> json) => DeletedAssetModel(
        id: json['id'] as int,
        propertyNumber: json['propertyNumber'] as String,
        description: json['description'] as String,
        categoryName: json['categoryName'] as String,
        officeName: json['officeName'] as String,
        deletedByUsername: json['deletedByUsername'] as String,
        deletedAt: json['deletedAt'] as String,
        deleteReason: json['deleteReason'] as String?,
      );
}
