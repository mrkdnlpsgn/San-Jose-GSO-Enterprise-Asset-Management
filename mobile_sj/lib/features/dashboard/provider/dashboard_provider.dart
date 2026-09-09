import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../assets/provider/asset_provider.dart';
import '../../maintenance/provider/maintenance_provider.dart';
import '../../maintenance/model/maintenance_model.dart';
import '../../disposal/provider/disposal_provider.dart';
import '../../disposal/model/disposal_model.dart';

class DashboardStats {
  final int totalAssets;
  final double totalValue;
  final int underMaintenance;
  final int disposed;
  final Map<String, int> conditionDist;
  final Map<String, int> lifecycleDist;

  const DashboardStats({
    required this.totalAssets,
    required this.totalValue,
    required this.underMaintenance,
    required this.disposed,
    required this.conditionDist,
    required this.lifecycleDist,
  });
}

final dashboardStatsProvider = FutureProvider.autoDispose<DashboardStats>((ref) async {
  final service = ref.watch(assetServiceProvider);
  final maintenanceService = ref.watch(maintenanceServiceProvider);
  final disposalService = ref.watch(disposalServiceProvider);
  // Stats need the full dataset, not a page — matches web's assetService.js
  // getAssets(), which requests size: 100000 for the same reason. A capped
  // size here silently undercounts totalAssets once the table grows past it.
  final assets = await service.getAll(size: 100000);
  final maintenanceRecords = await maintenanceService.getAll(size: 100000);
  final disposalRecords = await disposalService.getAll(size: 100000);

  final conditionDist = <String, int>{};
  double totalValue = 0;
  int underMaintenance = 0;
  int disposed = 0;

  for (final a in assets) {
    conditionDist[a.condition] = (conditionDist[a.condition] ?? 0) + 1;
    totalValue += a.unitValue * a.quantity;
    if (a.lifecycleStatus == 'UNDER_MAINTENANCE') underMaintenance++;
    if (a.lifecycleStatus == 'DISPOSED') disposed++;
  }

  // Every asset is counted exactly once, so this always sums to totalAssets.
  // Registered+Assigned merge into one bucket; an UNDER_MAINTENANCE/DISPOSED
  // asset is further split into its 3 sub-buckets by looking up that asset's
  // own active maintenance/disposal ledger record (there's at most one, per
  // handleConditionLedger's delete-on-transition design) rather than counting
  // ledger rows independently — a ledger record for an asset that's since
  // moved on (e.g. repaired and now SERVICEABLE again) isn't double-counted.
  // Keep keys in sync with the web dashboard's LIFECYCLE_CFG
  // (frontend_sj/frontend/src/pages/Dashboard/index.jsx).
  final maintByAsset = <int, MaintenanceModel>{};
  for (final m in maintenanceRecords) {
    maintByAsset[m.asset.id] = m;
  }
  final dispByAsset = <int, DisposalModel>{};
  for (final d in disposalRecords) {
    dispByAsset[d.asset.id] = d;
  }

  final lifecycleDist = <String, int>{};
  for (final a in assets) {
    final status = a.lifecycleStatus;
    String? key;
    if (status == 'REGISTERED' || status == 'ASSIGNED') {
      key = 'REGISTERED';
    } else if (status == 'TRANSFERRED' || status == 'ARCHIVED') {
      key = status;
    } else if (status == 'UNDER_MAINTENANCE') {
      final m = maintByAsset[a.id];
      key = m?.status == 'SCHEDULED'
          ? 'MAINT_SCHEDULED'
          : m?.status == 'COMPLETED'
              ? 'MAINT_REPAIRED'
              : 'MAINT_ONGOING';
    } else if (status == 'DISPOSED') {
      final d = dispByAsset[a.id];
      if (d == null || d.disposalStatus != 'COMPLETED') {
        key = 'DISP_PENDING';
      } else if (d.recommendedMethod == 'TRANSFER') {
        key = 'DISP_TRANSFERRED';
      } else {
        key = 'DISP_DESTRUCTED';
      }
    }
    if (key != null) lifecycleDist[key] = (lifecycleDist[key] ?? 0) + 1;
  }

  return DashboardStats(
    totalAssets: assets.length,
    totalValue: totalValue,
    underMaintenance: underMaintenance,
    disposed: disposed,
    conditionDist: conditionDist,
    lifecycleDist: lifecycleDist,
  );
});
