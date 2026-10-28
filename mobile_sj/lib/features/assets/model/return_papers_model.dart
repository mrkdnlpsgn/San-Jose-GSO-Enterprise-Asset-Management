// An asset's Property Return Slips and PARs, from GET /api/assets/{id}/return-papers
// (ReturnSlipService.AssetPapers): made each time a transfer changed its end user.

/// What the two papers share: the asset's details as they were the day the paper was made.
abstract class PaperAsset {
  String get propertyNumber;
  String? get description;
  String? get specifications;
  double? get unitValue;
  String? get acquisitionDate;
}

class ReturnSlipModel implements PaperAsset {
  final int id;
  final String slipNumber;
  final int? transferId;
  final String purpose;
  final String? officeName;
  final String returnedByName;
  final String? returnedByPosition;
  final String returnDate;
  @override
  final String propertyNumber;
  final String? parNumber;
  @override
  final String? description;
  @override
  final String? specifications;
  @override
  final double? unitValue;
  @override
  final String? acquisitionDate;
  final String createdAt;

  const ReturnSlipModel({
    required this.id,
    required this.slipNumber,
    this.transferId,
    required this.purpose,
    this.officeName,
    required this.returnedByName,
    this.returnedByPosition,
    required this.returnDate,
    required this.propertyNumber,
    this.parNumber,
    this.description,
    this.specifications,
    this.unitValue,
    this.acquisitionDate,
    required this.createdAt,
  });

  factory ReturnSlipModel.fromJson(Map<String, dynamic> j) => ReturnSlipModel(
        id: (j['id'] as num).toInt(),
        slipNumber: j['slipNumber'] as String? ?? '',
        transferId: (j['transferId'] as num?)?.toInt(),
        purpose: j['purpose'] as String? ?? 'RETURNED_TO_STOCK',
        officeName: j['officeName'] as String?,
        returnedByName: j['returnedByName'] as String? ?? '',
        returnedByPosition: j['returnedByPosition'] as String?,
        returnDate: j['returnDate'] as String? ?? '',
        propertyNumber: j['propertyNumber'] as String? ?? '',
        parNumber: j['parNumber'] as String?,
        description: j['description'] as String?,
        specifications: j['specifications'] as String?,
        unitValue: (j['unitValue'] as num?)?.toDouble(),
        acquisitionDate: j['acquisitionDate'] as String?,
        createdAt: j['createdAt']?.toString() ?? '',
      );
}

class ParIssueModel implements PaperAsset {
  final int id;
  final String parNumber;
  final int? transferId;
  final String? personnelName;
  final String? personnelPosition;
  final String? officeName;
  final String? issueDate;
  @override
  final String propertyNumber;
  @override
  final String? description;
  @override
  final String? specifications;
  @override
  final double? unitValue;
  @override
  final String? acquisitionDate;
  /// The PAR the asset was registered with, kept when it was first reissued.
  final bool original;
  final String createdAt;

  const ParIssueModel({
    required this.id,
    required this.parNumber,
    this.transferId,
    this.personnelName,
    this.personnelPosition,
    this.officeName,
    this.issueDate,
    required this.propertyNumber,
    this.description,
    this.specifications,
    this.unitValue,
    this.acquisitionDate,
    required this.original,
    required this.createdAt,
  });

  factory ParIssueModel.fromJson(Map<String, dynamic> j) => ParIssueModel(
        id: (j['id'] as num).toInt(),
        parNumber: j['parNumber'] as String? ?? '',
        transferId: (j['transferId'] as num?)?.toInt(),
        personnelName: j['personnelName'] as String?,
        personnelPosition: j['personnelPosition'] as String?,
        officeName: j['officeName'] as String?,
        issueDate: j['issueDate'] as String?,
        propertyNumber: j['propertyNumber'] as String? ?? '',
        description: j['description'] as String?,
        specifications: j['specifications'] as String?,
        unitValue: (j['unitValue'] as num?)?.toDouble(),
        acquisitionDate: j['acquisitionDate'] as String?,
        original: j['original'] as bool? ?? false,
        createdAt: j['createdAt']?.toString() ?? '',
      );
}

/// One end-user change (its return slip and the new PAR), or an asset's original PAR on its own.
class PaperRow {
  final ReturnSlipModel? slip;
  final ParIssueModel? par;
  final String at;
  const PaperRow({this.slip, this.par, required this.at});

  bool get isOriginal => slip == null && par != null && (par!.original || par!.transferId == null);
}

class ReturnPapersModel {
  final List<ReturnSlipModel> returnSlips;
  final List<ParIssueModel> pars;
  const ReturnPapersModel(this.returnSlips, this.pars);

  bool get isEmpty => returnSlips.isEmpty && pars.isEmpty;

  factory ReturnPapersModel.fromJson(Map<String, dynamic> j) => ReturnPapersModel(
        [for (final e in (j['returnSlips'] as List? ?? const [])) ReturnSlipModel.fromJson(e as Map<String, dynamic>)],
        [for (final e in (j['pars'] as List? ?? const [])) ParIssueModel.fromJson(e as Map<String, dynamic>)],
      );

  /// Newest change first; original PARs after the changes. Same grouping as the web.
  List<PaperRow> get rows {
    final byTransfer = <Object, ({ReturnSlipModel? slip, ParIssueModel? par, String at})>{};
    for (final s in returnSlips) {
      final key = s.transferId ?? 's${s.id}';
      final cur = byTransfer[key];
      byTransfer[key] = (slip: s, par: cur?.par, at: cur?.at ?? s.createdAt);
    }
    final originals = <PaperRow>[];
    for (final p in pars) {
      if (p.original || p.transferId == null) {
        originals.add(PaperRow(par: p, at: p.createdAt));
      } else {
        final cur = byTransfer[p.transferId!];
        byTransfer[p.transferId!] = (slip: cur?.slip, par: p, at: cur?.at ?? p.createdAt);
      }
    }
    final changes = [for (final v in byTransfer.values) PaperRow(slip: v.slip, par: v.par, at: v.at)]
      ..sort((a, b) => b.at.compareTo(a.at));
    originals.sort((a, b) => b.at.compareTo(a.at));
    return [...changes, ...originals];
  }
}
