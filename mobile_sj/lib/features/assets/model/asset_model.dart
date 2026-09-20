class CategoryModel {
  final int id;
  final String categoryName;
  final String? description;

  const CategoryModel({required this.id, required this.categoryName, this.description});

  factory CategoryModel.fromJson(Map<String, dynamic> json) => CategoryModel(
        id: json['id'] as int,
        categoryName: json['categoryName'] as String? ?? '—',
        description: json['description'] as String?,
      );
}

class PersonnelModel {
  final int id;
  final String fullName;
  final String? position;
  final int? officeId;

  const PersonnelModel({required this.id, required this.fullName, this.position, this.officeId});

  factory PersonnelModel.fromJson(Map<String, dynamic> json) {
    final office = json['office'] as Map<String, dynamic>?;
    return PersonnelModel(
      id: json['id'] as int,
      fullName: json['fullName'] as String? ?? '—',
      position: json['position'] as String?,
      officeId: office?['id'] as int?,
    );
  }
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
  // Property Acknowledgment Receipt no. (YYYY-MM:SERIAL) — distinct from propertyNumber.
  // Null only for assets that predate the field.
  final String? parNumber;
  // Devices added together share a groupId — each is still its own complete asset.
  final String? groupId;
  // Roll-up for a grouped asset, from the server: how many devices are in its group and their
  // combined value — true totals even when only some of them are loaded in a list.
  final int? groupSize;
  final double? groupTotalValue;
  final String? serialNumber;
  final String description;
  final CategoryModel category;
  final int quantity;
  final String acquisitionDate;
  final double unitValue;
  final OfficeModel office;
  final PersonnelModel? accountablePerson;
  final PersonnelModel? currentUser;
  final int? physicalCount;
  final String location;
  final String condition;       // SERVICEABLE | REPAIRABLE | UNSERVICEABLE
  final String lifecycleStatus; // REGISTERED | ASSIGNED | TRANSFERRED | UNDER_MAINTENANCE | DISPOSED | ARCHIVED
  final String? remarks;
  final String? specifications;
  final double? accumulatedDepreciation; // informational only — never gates disposal
  final double? carryingAmount;
  final String createdAt;
  final String updatedAt;

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
    required this.quantity,
    required this.acquisitionDate,
    required this.unitValue,
    required this.office,
    this.accountablePerson,
    this.currentUser,
    this.physicalCount,
    required this.location,
    required this.condition,
    required this.lifecycleStatus,
    this.remarks,
    this.specifications,
    this.accumulatedDepreciation,
    this.carryingAmount,
    required this.createdAt,
    required this.updatedAt,
  });

  // Compact "property no. · PAR no." label for list rows and headers.
  String get propertyAndPar => parNumber != null && parNumber!.isNotEmpty
      ? '$propertyNumber · PAR $parNumber'
      : propertyNumber;

  // Nested inside Disposal/Maintenance/AssetHistory responses, the backend serializes a
  // partial asset (only id/propertyNumber/description populated — category, office, and
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
            : const CategoryModel(id: 0, categoryName: '—'),
        quantity: json['quantity'] as int? ?? 1,
        acquisitionDate: json['acquisitionDate'] as String? ?? '',
        unitValue: json['unitValue'] != null ? (json['unitValue'] as num).toDouble() : 0,
        office: json['office'] != null
            ? OfficeModel.fromJson(json['office'] as Map<String, dynamic>)
            : const OfficeModel(id: 0, officeName: '—'),
        accountablePerson: json['accountablePerson'] != null
            ? PersonnelModel.fromJson(json['accountablePerson'] as Map<String, dynamic>)
            : null,
        currentUser: json['currentUser'] != null
            ? PersonnelModel.fromJson(json['currentUser'] as Map<String, dynamic>)
            : null,
        physicalCount: json['physicalCount'] as int?,
        location: json['location'] as String? ?? '',
        condition: json['condition'] as String? ?? '',
        lifecycleStatus: json['lifecycleStatus'] as String? ?? '',
        remarks: json['remarks'] as String?,
        specifications: json['specifications'] as String?,
        accumulatedDepreciation: json['accumulatedDepreciation'] != null ? (json['accumulatedDepreciation'] as num).toDouble() : null,
        carryingAmount: json['carryingAmount'] != null ? (json['carryingAmount'] as num).toDouble() : null,
        createdAt: json['createdAt'] as String? ?? '',
        updatedAt: json['updatedAt'] as String? ?? '',
      );
}
