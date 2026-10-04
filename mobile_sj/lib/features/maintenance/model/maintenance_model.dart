import '../../assets/model/asset_model.dart';

class MaintenanceUserModel {
  final int id;
  final String username;
  final String fullName;

  const MaintenanceUserModel({required this.id, required this.username, required this.fullName});

  factory MaintenanceUserModel.fromJson(Map<String, dynamic> json) => MaintenanceUserModel(
        id: json['id'] as int,
        username: json['username'] as String,
        fullName: json['fullName'] as String,
      );
}

class MaintenanceModel {
  final int id;
  final AssetModel asset;
  final String maintenanceType;  // PREVENTIVE | CORRECTIVE | REPAIR
  final String findings;
  final String actionsTaken;
  final String? assignedTo;
  final String maintenanceDate;
  final double? cost;
  final String status;           // COMPLETED | ONGOING | SCHEDULED
  final MaintenanceUserModel recordedBy;
  final String createdAt;
  final String? updatedAt;
  // PENDING_APPROVAL (requested by staff) | APPROVED | REJECTED; null = approved.
  final String? approvalStatus;
  final String? reviewNote;
  final String? requestedByName;

  bool get isApproved => approvalStatus == null || approvalStatus == 'APPROVED';

  const MaintenanceModel({
    required this.id,
    required this.asset,
    required this.maintenanceType,
    required this.findings,
    required this.actionsTaken,
    this.assignedTo,
    required this.maintenanceDate,
    this.cost,
    required this.status,
    required this.recordedBy,
    required this.createdAt,
    this.updatedAt,
    this.approvalStatus,
    this.reviewNote,
    this.requestedByName,
  });

  factory MaintenanceModel.fromJson(Map<String, dynamic> json) => MaintenanceModel(
        id: json['id'] as int,
        asset: AssetModel.fromJson(json['asset'] as Map<String, dynamic>),
        maintenanceType: json['maintenanceType'] as String,
        findings: json['findings'] as String,
        actionsTaken: json['actionsTaken'] as String,
        assignedTo: json['assignedTo'] as String?,
        maintenanceDate: json['maintenanceDate'] as String,
        cost: json['cost'] != null ? (json['cost'] as num).toDouble() : null,
        status: json['status'] as String,
        recordedBy: MaintenanceUserModel.fromJson(json['recordedBy'] as Map<String, dynamic>),
        createdAt: json['createdAt'] as String,
        updatedAt: json['updatedAt'] as String?,
        approvalStatus: json['approvalStatus'] as String?,
        reviewNote: json['reviewNote'] as String?,
        requestedByName: json['requestedByName'] as String?,
      );
}
