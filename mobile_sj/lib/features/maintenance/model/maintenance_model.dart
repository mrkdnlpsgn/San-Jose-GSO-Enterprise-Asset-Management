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

/// A parts or labor line, as on the GSO's Repair and Maintenance Card. kind: PART | LABOR.
/// A part's photos are tied to its id; an additional part (found needed during the repair)
/// has no pre-maintenance photo.
class MaintenanceItemModel {
  final int? id;
  final String kind;
  final String particular;
  final String? unit;
  final double? quantity;
  final double? unitCost;
  final double totalCost;
  final bool additional;

  const MaintenanceItemModel({
    this.id,
    required this.kind,
    required this.particular,
    this.unit,
    this.quantity,
    this.unitCost,
    required this.totalCost,
    this.additional = false,
  });

  bool get isPart => kind != 'LABOR';

  factory MaintenanceItemModel.fromJson(Map<String, dynamic> json) => MaintenanceItemModel(
        id: (json['id'] as num?)?.toInt(),
        kind: json['kind'] as String? ?? 'PART',
        particular: json['particular'] as String? ?? '',
        unit: json['unit'] as String?,
        quantity: (json['quantity'] as num?)?.toDouble(),
        unitCost: (json['unitCost'] as num?)?.toDouble(),
        totalCost: (json['totalCost'] as num?)?.toDouble() ?? 0,
        additional: json['additional'] as bool? ?? false,
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
  // the day the repair was finished (records completed before it was asked for have none)
  final String? completedDate;
  final List<MaintenanceItemModel> items;
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
    this.completedDate,
    this.items = const [],
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
        completedDate: json['completedDate'] as String?,
        items: [
          for (final i in (json['items'] as List? ?? const []))
            MaintenanceItemModel.fromJson(Map<String, dynamic>.from(i as Map)),
        ],
        recordedBy: MaintenanceUserModel.fromJson(json['recordedBy'] as Map<String, dynamic>),
        createdAt: json['createdAt'] as String,
        updatedAt: json['updatedAt'] as String?,
        approvalStatus: json['approvalStatus'] as String?,
        reviewNote: json['reviewNote'] as String?,
        requestedByName: json['requestedByName'] as String?,
      );
}
