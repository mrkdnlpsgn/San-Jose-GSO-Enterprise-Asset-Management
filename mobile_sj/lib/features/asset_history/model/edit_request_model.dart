// One staff request (a maintenance or disposal record a STAFF account filed, e.g. by
// changing an asset's status) as returned by GET /asset-history/requests.
class EditRequestModel {
  final String kind; // MAINTENANCE | DISPOSAL | TRANSFER
  final int recordId;
  final int assetId;
  final String propertyNumber;
  final String? parNumber;
  final String assetDescription;
  final String? detail;
  final String approvalStatus; // PENDING_APPROVAL | APPROVED | REJECTED
  final String? reviewNote;
  final String? requestedAt;
  final String? reviewedAt;
  final int requestedById;
  final String? requestedByName;
  final String? reviewedByName;
  /// Times an Admin-Staff account reminded an administrator about it ("Notify admin").
  final int reminderCount;
  final String? lastRemindedAt;
  final String? lastRemindedByName;

  const EditRequestModel({
    required this.kind,
    required this.recordId,
    required this.assetId,
    required this.propertyNumber,
    this.parNumber,
    required this.assetDescription,
    this.detail,
    required this.approvalStatus,
    this.reviewNote,
    this.requestedAt,
    this.reviewedAt,
    required this.requestedById,
    this.requestedByName,
    this.reviewedByName,
    this.reminderCount = 0,
    this.lastRemindedAt,
    this.lastRemindedByName,
  });

  factory EditRequestModel.fromJson(Map<String, dynamic> json) => EditRequestModel(
        kind: json['kind'] as String,
        recordId: json['recordId'] as int,
        assetId: json['assetId'] as int,
        propertyNumber: json['propertyNumber'] as String? ?? '',
        parNumber: json['parNumber'] as String?,
        assetDescription: json['assetDescription'] as String? ?? '',
        detail: json['detail'] as String?,
        approvalStatus: json['approvalStatus'] as String? ?? '',
        reviewNote: json['reviewNote'] as String?,
        requestedAt: json['requestedAt'] as String?,
        reviewedAt: json['reviewedAt'] as String?,
        requestedById: json['requestedById'] as int,
        requestedByName: json['requestedByName'] as String?,
        reviewedByName: json['reviewedByName'] as String?,
        reminderCount: (json['reminderCount'] as num?)?.toInt() ?? 0,
        lastRemindedAt: json['lastRemindedAt'] as String?,
        lastRemindedByName: json['lastRemindedByName'] as String?,
      );
}
