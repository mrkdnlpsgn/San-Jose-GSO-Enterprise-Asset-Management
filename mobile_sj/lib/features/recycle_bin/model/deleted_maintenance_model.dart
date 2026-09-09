class DeletedMaintenanceModel {
  final int id;
  final String propertyNumber;
  final String assetDescription;
  final String maintenanceType;
  final String status;
  final String deletedByUsername;
  final String deletedAt;
  final String? deleteReason;

  const DeletedMaintenanceModel({
    required this.id,
    required this.propertyNumber,
    required this.assetDescription,
    required this.maintenanceType,
    required this.status,
    required this.deletedByUsername,
    required this.deletedAt,
    this.deleteReason,
  });

  factory DeletedMaintenanceModel.fromJson(Map<String, dynamic> json) => DeletedMaintenanceModel(
        id: json['id'] as int,
        propertyNumber: json['propertyNumber'] as String,
        assetDescription: json['assetDescription'] as String,
        maintenanceType: json['maintenanceType'] as String,
        status: json['status'] as String,
        deletedByUsername: json['deletedByUsername'] as String,
        deletedAt: json['deletedAt'] as String,
        deleteReason: json['deleteReason'] as String?,
      );
}
