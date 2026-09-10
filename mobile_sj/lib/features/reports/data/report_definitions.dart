import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../assets/data/asset_service.dart';
import '../../assets/model/asset_model.dart';
import '../../asset_history/data/asset_history_service.dart';
import '../../disposal/data/disposal_service.dart';
import '../../disposal/model/disposal_model.dart';
import '../../maintenance/data/maintenance_service.dart';
import '../model/report_definition.dart';
import '../utils/formatters.dart';

/// Reports need the full dataset, not one paginated page. AssetService/DisposalService/
/// MaintenanceService default to the backend's page size of 20 (fine for list screens,
/// wrong here), so ask for a size large enough to always cover a single municipal
/// office's inventory in one request.
const _kAllRowsSize = 100000;

String _cell(dynamic row, String Function(AssetModel) fromAsset) =>
    row is AssetModel ? fromAsset(row) : '';

class _ConditionSummary {
  final String condition;
  final int count;
  final double totalValue;
  final String offices;
  const _ConditionSummary(this.condition, this.count, this.totalValue, this.offices);
}

// RPCPPE physical-count variance: quantity per records vs. quantity per physical count.
// physicalCount is null until someone has actually counted the asset — don't assume a shortage.
int? _assetVariance(AssetModel a) {
  if (a.physicalCount == null) return null;
  return a.physicalCount! - a.quantity;
}

String _fmtVariance(AssetModel a) {
  final v = _assetVariance(a);
  if (v == null) return 'Not yet counted';
  if (v == 0) return 'None';
  return v > 0 ? '+$v (Overage)' : '$v (Shortage)';
}

double _varianceValue(AssetModel a) {
  final v = _assetVariance(a);
  return v == null ? 0 : v * a.unitValue;
}

List<ReportDefinition> buildReportDefinitions() {
  final assetService = AssetService();
  final disposalService = DisposalService();
  final maintenanceService = MaintenanceService();
  final historyService = AssetHistoryService();

  return [
    ReportDefinition(
      id: 'inventory',
      title: 'Asset Inventory',
      subtitle: 'Complete list of all ICT assets with condition, lifecycle status, and location.',
      icon: Icons.inventory_2_outlined,
      color: AppTheme.brand,
      load: () => assetService.getAll(size: _kAllRowsSize),
      columns: [
        ReportColumn('Property No.', (row) => (row as AssetModel).propertyNumber),
        ReportColumn('Description', (row) => (row as AssetModel).description),
        ReportColumn('Category', (row) => (row as AssetModel).category.categoryName),
        ReportColumn('Condition', (row) => (row as AssetModel).condition),
        ReportColumn('Lifecycle', (row) => (row as AssetModel).lifecycleStatus.replaceAll('_', ' ')),
        ReportColumn('Office', (row) => (row as AssetModel).office.officeName),
        ReportColumn('Location', (row) => (row as AssetModel).location),
        ReportColumn('Accountable', (row) => (row as AssetModel).accountablePerson ?? '—'),
        ReportColumn('Qty', (row) => (row as AssetModel).quantity.toString()),
        ReportColumn('Unit Value', (row) => fmtMoney((row as AssetModel).unitValue)),
        ReportColumn('Acq. Date', (row) => fmtDate((row as AssetModel).acquisitionDate)),
      ],
    ),
    ReportDefinition(
      id: 'condition',
      title: 'Condition Report',
      subtitle: 'Asset breakdown by condition — serviceable, repairable, and unserviceable counts.',
      icon: Icons.pie_chart_outline_rounded,
      color: AppTheme.statusAssigned,
      load: () async {
        final assets = await assetService.getAll(size: _kAllRowsSize);
        final map = <String, _RunningSummary>{};
        for (final a in assets) {
          final s = map.putIfAbsent(a.condition, () => _RunningSummary());
          s.count++;
          s.totalValue += a.unitValue * a.quantity;
          s.offices.add(a.office.officeName);
        }
        final rows = map.entries
            .map((e) => _ConditionSummary(e.key, e.value.count, e.value.totalValue, e.value.offices.join(', ')))
            .toList()
          ..sort((a, b) => b.count.compareTo(a.count));
        return rows;
      },
      columns: [
        ReportColumn('Condition', (row) => (row as _ConditionSummary).condition),
        ReportColumn('Count', (row) => (row as _ConditionSummary).count.toString()),
        ReportColumn('Total Value', (row) {
          final r = row as _ConditionSummary;
          return r.totalValue > 0 ? fmtMoney(r.totalValue) : '—';
        }),
        ReportColumn('Offices', (row) {
          final offices = (row as _ConditionSummary).offices;
          return offices.isEmpty ? '—' : offices;
        }),
      ],
    ),
    ReportDefinition(
      id: 'history',
      title: 'Asset History',
      subtitle: 'Full log of all asset events — assignments, transfers, maintenance, and disposals.',
      icon: Icons.history_rounded,
      color: AppTheme.statusTransferred,
      load: () => historyService.getAll(),
      columns: [
        ReportColumn('Asset', (row) => row.asset.description as String),
        ReportColumn('Property No.', (row) => row.asset.propertyNumber as String),
        ReportColumn('Event Type', (row) => row.eventType as String),
        ReportColumn('From Office', (row) => row.fromOffice?.officeName ?? '—'),
        ReportColumn('To Office', (row) => row.toOffice?.officeName ?? '—'),
        ReportColumn('Performed By', (row) => row.performedBy.fullName as String),
        ReportColumn('Notes', (row) => row.notes ?? '—'),
        ReportColumn('Date', (row) => fmtDate(row.eventDate as String)),
      ],
    ),
    ReportDefinition(
      id: 'valuation',
      title: 'Asset Valuation',
      subtitle: 'Financial summary of ICT asset acquisition values, sorted by unit value.',
      icon: Icons.payments_outlined,
      color: AppTheme.statusMaintenance,
      load: () async {
        final assets = await assetService.getAll(size: _kAllRowsSize);
        final sorted = [...assets]..sort((a, b) => b.unitValue.compareTo(a.unitValue));
        return sorted;
      },
      extraRows: (rows) {
        final total = rows.fold<double>(
            0, (s, r) => s + (r as AssetModel).unitValue * r.quantity);
        return [...rows, {'label': 'TOTAL ACQUISITION VALUE', 'total': total}];
      },
      columns: [
        ReportColumn('Property No.', (row) => row is Map ? row['label'] as String : (row as AssetModel).propertyNumber),
        ReportColumn('Description', (row) => _cell(row, (a) => a.description)),
        ReportColumn('Category', (row) => _cell(row, (a) => a.category.categoryName)),
        ReportColumn('Condition', (row) => _cell(row, (a) => a.condition)),
        ReportColumn('Unit Value', (row) => row is Map ? '' : fmtMoney((row as AssetModel).unitValue)),
        ReportColumn('Quantity', (row) => _cell(row, (a) => a.quantity.toString())),
        ReportColumn('Total Value', (row) =>
            row is Map ? fmtMoney(row['total'] as num) : fmtMoney((row as AssetModel).unitValue * row.quantity)),
        ReportColumn('Acq. Date', (row) => _cell(row, (a) => fmtDate(a.acquisitionDate))),
        ReportColumn('Office', (row) => _cell(row, (a) => a.office.officeName)),
      ],
    ),
    ReportDefinition(
      id: 'maintenance',
      title: 'Maintenance Ledger',
      subtitle: 'All maintenance and repair records for ICT assets.',
      icon: Icons.build_outlined,
      color: AppTheme.statusMaintenance,
      load: () => maintenanceService.getAll(size: _kAllRowsSize),
      columns: [
        ReportColumn('Asset', (row) => row.asset.description as String),
        ReportColumn('Type', (row) => row.maintenanceType as String),
        ReportColumn('Findings', (row) => row.findings as String),
        ReportColumn('Status', (row) => row.status as String),
        ReportColumn('Assigned To', (row) => row.assignedTo ?? '—'),
        ReportColumn('Cost', (row) => fmtMoney(row.cost)),
        ReportColumn('Date', (row) => fmtDate(row.maintenanceDate as String)),
        ReportColumn('Recorded By', (row) => row.recordedBy.fullName as String),
      ],
    ),
    ReportDefinition(
      id: 'rpcppe',
      title: 'RPCPPE (Physical Count)',
      subtitle: 'COA-format Report on the Physical Count of Property, Plant and Equipment — '
          'records vs. physical count variance.',
      icon: Icons.fact_check_outlined,
      color: AppTheme.brandDark,
      load: () => assetService.getAll(size: _kAllRowsSize),
      columns: [
        ReportColumn('Article', (row) => (row as AssetModel).category.categoryName),
        ReportColumn('Description', (row) => (row as AssetModel).description),
        ReportColumn('Property No.', (row) => (row as AssetModel).propertyNumber),
        ReportColumn('Unit Value', (row) => fmtMoney((row as AssetModel).unitValue)),
        ReportColumn('Qty per Records', (row) => (row as AssetModel).quantity.toString()),
        ReportColumn('Qty per Phys. Count', (row) => (row as AssetModel).physicalCount?.toString() ?? '—'),
        ReportColumn('Shortage/Overage', (row) => _fmtVariance(row as AssetModel)),
        ReportColumn('Value of Variance', (row) {
          final v = _varianceValue(row as AssetModel);
          return v != 0 ? fmtMoney(v) : '—';
        }),
        ReportColumn('Location', (row) => (row as AssetModel).location),
        ReportColumn('Condition', (row) => (row as AssetModel).condition),
        ReportColumn('Remarks', (row) => (row as AssetModel).remarks ?? '—'),
      ],
      certification: const [
        'Prepared by: Property Custodian / GSO Staff',
        'Certified Correct by: Inventory Committee Chairman',
        'Member, Inventory Committee',
        'Member, Inventory Committee',
        'Verified by: COA Representative',
      ],
    ),
    ReportDefinition(
      id: 'iirup',
      title: 'IIRUP (Unserviceable Property)',
      subtitle: 'COA-format Inventory and Inspection Report of Unserviceable Property, '
          'for items pending disposal.',
      icon: Icons.delete_forever_outlined,
      color: AppTheme.statusDisposed,
      load: () => disposalService.getAll(size: _kAllRowsSize),
      columns: [
        ReportColumn('Date Acquired', (row) => fmtDate((row as DisposalModel).asset.acquisitionDate)),
        ReportColumn('Particulars/Article', (row) => (row as DisposalModel).asset.description),
        ReportColumn('Property No.', (row) => (row as DisposalModel).asset.propertyNumber),
        ReportColumn('Qty.', (row) => (row as DisposalModel).asset.quantity.toString()),
        ReportColumn('Unit Cost', (row) => fmtMoney((row as DisposalModel).asset.unitValue)),
        ReportColumn('Total Cost', (row) {
          final d = row as DisposalModel;
          return fmtMoney(d.asset.unitValue * d.asset.quantity);
        }),
        ReportColumn('Accumulated Depreciation', (row) => fmtMoney((row as DisposalModel).accumulatedDepreciation)),
        ReportColumn('Accumulated Impairment Losses', (row) => '—'),
        ReportColumn('Carrying Amount', (row) => fmtMoney((row as DisposalModel).carryingAmount)),
        ReportColumn('Remarks', (row) => (row as DisposalModel).inspectionFindings),
        ReportColumn('Sale', (row) {
          final d = row as DisposalModel;
          return d.recommendedMethod == 'SALE' ? d.asset.quantity.toString() : '—';
        }),
        ReportColumn('Transfer', (row) {
          final d = row as DisposalModel;
          return d.recommendedMethod == 'TRANSFER' ? d.asset.quantity.toString() : '—';
        }),
        ReportColumn('Destruction', (row) {
          final d = row as DisposalModel;
          return d.recommendedMethod == 'DESTRUCTION' ? d.asset.quantity.toString() : '—';
        }),
        ReportColumn('Others (Specify)', (row) {
          final d = row as DisposalModel;
          return d.recommendedMethod == 'OTHERS' ? d.asset.quantity.toString() : '—';
        }),
        ReportColumn('Total', (row) => (row as DisposalModel).asset.quantity.toString()),
        ReportColumn('Appraised Value', (row) => fmtMoney((row as DisposalModel).appraisedValue)),
        ReportColumn('OR No.', (row) => (row as DisposalModel).orNumber ?? '—'),
        ReportColumn('Amount', (row) => fmtMoney((row as DisposalModel).amount)),
      ],
      certification: const [
        'Inspected by: GSO Inspector',
        'Certified Correct by: Inventory Committee Chairman',
        'Recommending Approval: Head of Office',
        'Approved by: Local Chief Executive (Municipal Mayor)',
      ],
    ),
  ];
}

class _RunningSummary {
  int count = 0;
  double totalValue = 0;
  final Set<String> offices = {};
}
