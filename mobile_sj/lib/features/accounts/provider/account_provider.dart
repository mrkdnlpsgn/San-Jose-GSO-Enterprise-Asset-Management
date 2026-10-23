import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/account_service.dart';
import '../model/account_model.dart';
import '../../../shared/provider/paginated_list_notifier.dart';

final accountServiceProvider = Provider<AccountService>((ref) => AccountService());

final accountSearchProvider = StateProvider<String>((ref) => '');

/// The backend accounts endpoint has no page/size params - it returns every
/// matching account in one call. This still fits PaginatedListView's fetch
/// shape (all results on the first "page", nothing after), so Accounts gets
/// the same skeleton/retry/refresh UI as Assets/Maintenance/Disposal without
/// needing real server-side pagination.
final accountsPagedProvider = StateNotifierProvider.autoDispose
    .family<PaginatedListNotifier<AccountModel>, PaginatedListState<AccountModel>, String>((ref, search) {
  final service = ref.watch(accountServiceProvider);
  return PaginatedListNotifier<AccountModel>(
    (search, page, size) async => page > 0 ? <AccountModel>[] : await service.getAll(search: search),
    search.isEmpty ? null : search,
  );
});
