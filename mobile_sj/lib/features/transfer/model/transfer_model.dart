// One asset transfer request, as returned by GET /api/transfers (TransferService.TransferView).
class TransferModel {
  final int id;
  final int assetId;
  final String propertyNumber;
  final String assetDescription;
  final int? currentPersonnelId;
  final String? currentPersonnelName;
  final String? fromOfficeName;
  final String? toOfficeName;
  final int? toPersonnelId;
  final String? toPersonnelName;
  final String? toLocation;
  final String? reason;
  final String status; // PENDING_APPROVAL | APPROVED | REJECTED
  final String? reviewNote;
  final String? requestedByName;
  final String? requestedAt;
  final String? reviewedByName;
  final String? reviewedAt;

  const TransferModel({
    required this.id,
    required this.assetId,
    required this.propertyNumber,
    required this.assetDescription,
    this.currentPersonnelId,
    this.currentPersonnelName,
    this.fromOfficeName,
    this.toOfficeName,
    this.toPersonnelId,
    this.toPersonnelName,
    this.toLocation,
    this.reason,
    required this.status,
    this.reviewNote,
    this.requestedByName,
    this.requestedAt,
    this.reviewedByName,
    this.reviewedAt,
  });

  bool get isPending => status == 'PENDING_APPROVAL';

  /// The asset goes to a new end user: approving it needs the new PAR No.
  bool get changesEndUser => toPersonnelId != null && toPersonnelId != currentPersonnelId;

  factory TransferModel.fromJson(Map<String, dynamic> j) => TransferModel(
        id: (j['id'] as num).toInt(),
        assetId: (j['assetId'] as num).toInt(),
        propertyNumber: j['propertyNumber'] as String? ?? '',
        assetDescription: j['assetDescription'] as String? ?? '',
        currentPersonnelId: (j['currentPersonnelId'] as num?)?.toInt(),
        currentPersonnelName: j['currentPersonnelName'] as String?,
        fromOfficeName: j['fromOfficeName'] as String?,
        toOfficeName: j['toOfficeName'] as String?,
        toPersonnelId: (j['toPersonnelId'] as num?)?.toInt(),
        toPersonnelName: j['toPersonnelName'] as String?,
        toLocation: j['toLocation'] as String?,
        reason: j['reason'] as String?,
        status: j['status'] as String? ?? '',
        reviewNote: j['reviewNote'] as String?,
        requestedByName: j['requestedByName'] as String?,
        requestedAt: j['requestedAt']?.toString(),
        reviewedByName: j['reviewedByName'] as String?,
        reviewedAt: j['reviewedAt']?.toString(),
      );
}
