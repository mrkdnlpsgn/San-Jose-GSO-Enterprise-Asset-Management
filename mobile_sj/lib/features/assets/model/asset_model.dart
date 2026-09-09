class CategoryModel {
  final int id;
  final String categoryName;
  final String? description;

  const CategoryModel({required this.id, required this.categoryName, this.description});

  factory CategoryModel.fromJson(Map<String, dynamic> json) => CategoryModel(
        id: json['id'] as int,
        categoryName: json['categoryName'] as String,
        description: json['description'] as String?,
      );
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
  final String description;
  final CategoryModel category;
  final int quantity;
  final String acquisitionDate;
  final double unitValue;
  final OfficeModel office;
  final String? accountablePerson;
  final int? physicalCount;
  final String location;
  final String condition;       // SERVICEABLE | REPAIRABLE | UNSERVICEABLE
  final String lifecycleStatus; // REGISTERED | ASSIGNED | TRANSFERRED | UNDER_MAINTENANCE | DISPOSED | ARCHIVED
  final String? remarks;
  final String createdAt;
  final String updatedAt;

  const AssetModel({
    required this.id,
    required this.propertyNumber,
    required this.description,
    required this.category,
    required this.quantity,
    required this.acquisitionDate,
    required this.unitValue,
    required this.office,
    this.accountablePerson,
    this.physicalCount,
    required this.location,
    required this.condition,
    required this.lifecycleStatus,
    this.remarks,
    required this.createdAt,
    required this.updatedAt,
  });

  // Nested inside Disposal/Maintenance/AssetHistory responses, the backend serializes a
  // partial asset (only id/propertyNumber/description populated — category, office, and
  // most other fields are absent or null). Fall back to placeholders for those so parsing
  // doesn't crash; callers in that context never read the placeholder fields.
  factory AssetModel.fromJson(Map<String, dynamic> json) => AssetModel(
        id: json['id'] as int,
        propertyNumber: json['propertyNumber'] as String,
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
        accountablePerson: json['accountablePerson'] as String?,
        physicalCount: json['physicalCount'] as int?,
        location: json['location'] as String? ?? '',
        condition: json['condition'] as String? ?? '',
        lifecycleStatus: json['lifecycleStatus'] as String? ?? '',
        remarks: json['remarks'] as String?,
        createdAt: json['createdAt'] as String? ?? '',
        updatedAt: json['updatedAt'] as String? ?? '',
      );
}
