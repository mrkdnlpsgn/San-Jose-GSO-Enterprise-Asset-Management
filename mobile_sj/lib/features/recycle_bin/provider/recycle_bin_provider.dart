import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/recycle_bin_service.dart';
import '../model/deleted_asset_model.dart';
import '../model/deleted_maintenance_model.dart';
import '../model/deleted_disposal_model.dart';

final recycleBinServiceProvider = Provider<RecycleBinService>((ref) => RecycleBinService());

final deletedAssetsProvider = FutureProvider.autoDispose<List<DeletedAssetModel>>((ref) {
  return ref.watch(recycleBinServiceProvider).getDeletedAssets();
});

final deletedMaintenanceProvider = FutureProvider.autoDispose<List<DeletedMaintenanceModel>>((ref) {
  return ref.watch(recycleBinServiceProvider).getDeletedMaintenance();
});

final deletedDisposalProvider = FutureProvider.autoDispose<List<DeletedDisposalModel>>((ref) {
  return ref.watch(recycleBinServiceProvider).getDeletedDisposal();
});
