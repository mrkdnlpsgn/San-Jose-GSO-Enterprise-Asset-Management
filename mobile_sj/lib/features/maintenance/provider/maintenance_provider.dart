import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/maintenance_service.dart';
import '../model/maintenance_model.dart';
import '../../../shared/provider/paginated_list_notifier.dart';

final maintenanceServiceProvider = Provider<MaintenanceService>((ref) => MaintenanceService());

final maintenanceSearchProvider = StateProvider<String>((ref) => '');

final maintenanceTypeFilterProvider = StateProvider<String?>((ref) => null);
final maintenanceStatusFilterProvider = StateProvider<String?>((ref) => null);

final maintenancePagedProvider = StateNotifierProvider.autoDispose
    .family<PaginatedListNotifier<MaintenanceModel>, PaginatedListState<MaintenanceModel>, String>((ref, search) {
  final service = ref.watch(maintenanceServiceProvider);
  final maintenanceType = ref.watch(maintenanceTypeFilterProvider);
  final status = ref.watch(maintenanceStatusFilterProvider);
  return PaginatedListNotifier<MaintenanceModel>(
    (search, page, size) => service.getAll(
      search: search, page: page, size: size,
      maintenanceType: maintenanceType, status: status,
    ),
    search.isEmpty ? null : search,
  );
});

final maintenanceCountProvider = FutureProvider.autoDispose.family<int, String>((ref, search) {
  final service = ref.watch(maintenanceServiceProvider);
  final maintenanceType = ref.watch(maintenanceTypeFilterProvider);
  final status = ref.watch(maintenanceStatusFilterProvider);
  return service.count(
    search: search.isEmpty ? null : search,
    maintenanceType: maintenanceType,
    status: status,
  );
});

final maintenanceDetailProvider =
    FutureProvider.autoDispose.family<MaintenanceModel, int>((ref, id) {
  return ref.watch(maintenanceServiceProvider).getById(id);
});

final maintenanceByAssetProvider =
    FutureProvider.autoDispose.family<List<MaintenanceModel>, int>((ref, assetId) {
  return ref.watch(maintenanceServiceProvider).getByAsset(assetId);
});
