class CategoryModel {
  final int id;
  final String categoryName;
  final String? description;
  /// Expected useful life in years, counted from the acquisition date; null when not set.
  final int? usefulLifeYears;

  const CategoryModel({required this.id, required this.categoryName, this.description, this.usefulLifeYears});

  factory CategoryModel.fromJson(Map<String, dynamic> json) => CategoryModel(
        id: json['id'] as int,
        categoryName: json['categoryName'] as String? ?? 'N/A',
        description: json['description'] as String?,
        usefulLifeYears: json['usefulLifeYears'] as int?,
      );
}

/// The kind of item within a category (ICT Equipment > Laptop): the ARTICLE column of the
/// physical count report. Kept per category on the web Categories page.
class ArticleModel {
  final int id;
  /// Absent in the web list's summary of an asset; always present from /articles.
  final int? categoryId;
  final String articleName;

  const ArticleModel({required this.id, this.categoryId, required this.articleName});

  factory ArticleModel.fromJson(Map<String, dynamic> json) => ArticleModel(
        id: json['id'] as int,
        categoryId: json['categoryId'] as int?,
        articleName: json['articleName'] as String? ?? 'N/A',
      );

  Map<String, dynamic> toJson() => {'id': id, 'categoryId': categoryId, 'articleName': articleName};
}

class PersonnelModel {
  final int id;
  final String fullName;
  final String? position;
  /// Primary office.
  final int? officeId;
  /// Every office the person is assigned to (primary first).
  final List<int> officeIds;

  const PersonnelModel({required this.id, required this.fullName, this.position, this.officeId, this.officeIds = const []});

  factory PersonnelModel.fromJson(Map<String, dynamic> json) {
    final office = json['office'] as Map<String, dynamic>?;
    final officeId = office?['id'] as int?;
    final offices = (json['offices'] as List?) ?? const [];
    final ids = [for (final o in offices) ((o as Map<String, dynamic>)['id'] as num).toInt()];
    return PersonnelModel(
      id: json['id'] as int,
      fullName: json['fullName'] as String? ?? 'N/A',
      position: json['position'] as String?,
      officeId: officeId,
      officeIds: ids.isNotEmpty ? ids : [if (officeId != null) officeId],
    );
  }

  bool inOffice(int? id) => id != null && officeIds.contains(id);
}

class OfficeModel {
  final int id;
  final String officeName;
  final int? headUserId;
  final String? headUserName;

  const OfficeModel({required this.id, required this.officeName, this.headUserId, this.headUserName});

  factory OfficeModel.fromJson(Map<String, dynamic> json) {
    final head = json['headUser'] as Map<String, dynamic>?;
    return OfficeModel(
      id: json['id'] as int,
      officeName: json['officeName'] as String,
      headUserId: head?['id'] as int?,
      headUserName: (head?['fullName'] ?? head?['username']) as String?,
    );
  }
}

class AssetModel {
  final int id;
  final String propertyNumber;
  // Property Acknowledgment Receipt no. (YYYY-MM:SERIAL) - distinct from propertyNumber.
  // Null only for assets that predate the field.
  final String? parNumber;
  // Devices added together share a groupId - each is still its own complete asset.
  final String? groupId;
  // Roll-up for a grouped asset, from the server: how many devices are in its group and their
  // combined value - true totals even when only some of them are loaded in a list.
  final int? groupSize;
  final double? groupTotalValue;
  final String? serialNumber;
  final String description;
  final CategoryModel category;
  final ArticleModel? article;
  final int quantity;
  final String acquisitionDate;
  final double unitValue;
  final OfficeModel office;
  final PersonnelModel? accountablePerson;
  final PersonnelModel? currentUser;
  final int? physicalCount;
  // Manually recorded shortage (negative) or overage (positive) found during physical
  // inventory - independent of quantity/physicalCount, which are always 1. Defaults to 0.
  final int shortageOverageQty;
  final double shortageOverageValue;
  final String location;
  final String condition;       // NEW | GOOD | SERVICEABLE | REPAIRABLE | UNSERVICEABLE
  final String lifecycleStatus; // REGISTERED | ASSIGNED | TRANSFERRED | UNDER_MAINTENANCE | DISPOSED | ARCHIVED
  final String? remarks;
  final String? specifications;
  final String createdAt;
  final String updatedAt;
  // Only on a staff edit's response: MAINTENANCE / DISPOSAL when a request for this
  // asset is waiting for an admin (the lifecycle status stays as-is until approved).
  final String? pendingRequest;
  // The signed text the server says goes into this asset's QR sticker:
  // asset:{id}:{propertyNumber}:{tag}. Null from a server older than QR signing.
  final String? qrPayload;

  const AssetModel({
    required this.id,
    required this.propertyNumber,
    this.parNumber,
    this.groupId,
    this.groupSize,
    this.groupTotalValue,
    this.serialNumber,
    required this.description,
    required this.category,
    this.article,
    required this.quantity,
    required this.acquisitionDate,
    required this.unitValue,
    required this.office,
    this.accountablePerson,
    this.currentUser,
    this.physicalCount,
    this.shortageOverageQty = 0,
    this.shortageOverageValue = 0,
    required this.location,
    required this.condition,
    required this.lifecycleStatus,
    this.remarks,
    this.specifications,
    required this.createdAt,
    required this.updatedAt,
    this.pendingRequest,
    this.qrPayload,
  });

  // Compact "property no. · PAR no." label for list rows and headers.
  String get propertyAndPar => parNumber != null && parNumber!.isNotEmpty
      ? '$propertyNumber · PAR $parNumber'
      : propertyNumber;

  // Nested inside Disposal/Maintenance/AssetHistory responses, the backend serializes a
  // partial asset (only id/propertyNumber/description populated - category, office, and
  // most other fields are absent or null). Fall back to placeholders for those so parsing
  // doesn't crash; callers in that context never read the placeholder fields.
  factory AssetModel.fromJson(Map<String, dynamic> json) => AssetModel(
        id: json['id'] as int,
        propertyNumber: json['propertyNumber'] as String,
        parNumber: json['parNumber'] as String?,
        groupId: json['groupId'] as String?,
        groupSize: json['groupSize'] as int?,
        groupTotalValue: (json['groupTotalValue'] as num?)?.toDouble(),
        serialNumber: json['serialNumber'] as String?,
        description: json['description'] as String,
        category: json['category'] != null
            ? CategoryModel.fromJson(json['category'] as Map<String, dynamic>)
            : const CategoryModel(id: 0, categoryName: 'N/A'),
        article: json['article'] != null
            ? ArticleModel.fromJson(json['article'] as Map<String, dynamic>)
            : null,
        quantity: json['quantity'] as int? ?? 1,
        acquisitionDate: json['acquisitionDate'] as String? ?? '',
        unitValue: json['unitValue'] != null ? (json['unitValue'] as num).toDouble() : 0,
        office: json['office'] != null
            ? OfficeModel.fromJson(json['office'] as Map<String, dynamic>)
            : const OfficeModel(id: 0, officeName: 'N/A'),
        accountablePerson: json['accountablePerson'] != null
            ? PersonnelModel.fromJson(json['accountablePerson'] as Map<String, dynamic>)
            : null,
        currentUser: json['currentUser'] != null
            ? PersonnelModel.fromJson(json['currentUser'] as Map<String, dynamic>)
            : null,
        physicalCount: json['physicalCount'] as int?,
        shortageOverageQty: json['shortageOverageQty'] as int? ?? 0,
        shortageOverageValue: (json['shortageOverageValue'] as num?)?.toDouble() ?? 0,
        location: json['location'] as String? ?? '',
        condition: json['condition'] as String? ?? '',
        lifecycleStatus: json['lifecycleStatus'] as String? ?? '',
        remarks: json['remarks'] as String?,
        specifications: json['specifications'] as String?,
        createdAt: json['createdAt'] as String? ?? '',
        updatedAt: json['updatedAt'] as String? ?? '',
        pendingRequest: json['pendingRequest'] as String?,
        qrPayload: json['qrPayload'] as String?,
      );
}
