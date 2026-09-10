import '../../assets/model/asset_model.dart';
import '../../maintenance/model/maintenance_model.dart';

class DisposalModel {
  final int id;
  final AssetModel asset;
  final String reason;
  final String inspectionFindings;
  final String recommendedMethod;  // SALE | TRANSFER | DESTRUCTION | OTHERS
  final String disposalStatus;     // PENDING | APPROVED | COMPLETED
  final String inspectionDate;
  final String? approvedBy;
  final double? appraisedValue;
  final String? orNumber;
  final double? amount;
  final double? accumulatedDepreciation; // informational only — never gates disposal
  final double? carryingAmount;
  final MaintenanceUserModel recordedBy;
  final String createdAt;
  final String? updatedAt;

  const DisposalModel({
    required this.id,
    required this.asset,
    required this.reason,
    required this.inspectionFindings,
    required this.recommendedMethod,
    required this.disposalStatus,
    required this.inspectionDate,
    this.approvedBy,
    this.appraisedValue,
    this.orNumber,
    this.amount,
    this.accumulatedDepreciation,
    this.carryingAmount,
    required this.recordedBy,
    required this.createdAt,
    this.updatedAt,
  });

  factory DisposalModel.fromJson(Map<String, dynamic> json) => DisposalModel(
        id: json['id'] as int,
        asset: AssetModel.fromJson(json['asset'] as Map<String, dynamic>),
        reason: json['reason'] as String,
        inspectionFindings: json['inspectionFindings'] as String,
        recommendedMethod: json['recommendedMethod'] as String,
        disposalStatus: json['disposalStatus'] as String,
        inspectionDate: json['inspectionDate'] as String,
        approvedBy: json['approvedBy'] as String?,
        appraisedValue: json['appraisedValue'] != null ? (json['appraisedValue'] as num).toDouble() : null,
        orNumber: json['orNumber'] as String?,
        amount: json['amount'] != null ? (json['amount'] as num).toDouble() : null,
        accumulatedDepreciation: json['accumulatedDepreciation'] != null ? (json['accumulatedDepreciation'] as num).toDouble() : null,
        carryingAmount: json['carryingAmount'] != null ? (json['carryingAmount'] as num).toDouble() : null,
        recordedBy: MaintenanceUserModel.fromJson(json['recordedBy'] as Map<String, dynamic>),
        createdAt: json['createdAt'] as String,
        updatedAt: json['updatedAt'] as String?,
      );
}
