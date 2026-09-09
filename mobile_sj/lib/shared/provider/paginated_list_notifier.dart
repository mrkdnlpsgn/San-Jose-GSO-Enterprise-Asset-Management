import 'package:flutter_riverpod/flutter_riverpod.dart';

const paginatedPageSize = 20;

class PaginatedListState<T> {
  final List<T> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final Object? error;
  final Object? loadMoreError;

  const PaginatedListState({
    this.items = const [],
    this.isLoading = true,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.loadMoreError,
  });

  PaginatedListState<T> copyWith({
    List<T>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    Object? error,
    Object? loadMoreError,
  }) {
    return PaginatedListState<T>(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error,
      loadMoreError: loadMoreError,
    );
  }
}

typedef PageFetcher<T> = Future<List<T>> Function(String? search, int page, int size);

class PaginatedListNotifier<T> extends StateNotifier<PaginatedListState<T>> {
  PaginatedListNotifier(this._fetch, this._search) : super(const PaginatedListState()) {
    _loadFirstPage();
  }

  final PageFetcher<T> _fetch;
  final String? _search;
  int _page = 0;

  Future<void> _loadFirstPage() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final items = await _fetch(_search, 0, paginatedPageSize);
      _page = 0;
      state = PaginatedListState<T>(
        items: items,
        isLoading: false,
        hasMore: items.length == paginatedPageSize,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e);
    }
  }

  Future<void> refresh() => _loadFirstPage();

  // For background auto-refresh polling — unlike refresh()/_loadFirstPage(),
  // this never flips isLoading, so PaginatedListView keeps showing the
  // current items (no skeleton flash) while fresh data loads underneath.
  // A failed background poll is silently ignored rather than disrupting
  // whatever's already on screen.
  Future<void> silentRefresh() async {
    try {
      final items = await _fetch(_search, 0, paginatedPageSize);
      _page = 0;
      state = state.copyWith(items: items, hasMore: items.length == paginatedPageSize, error: null);
    } catch (_) {
      // Ignored — see comment above.
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.isLoading) return;
    state = state.copyWith(isLoadingMore: true, loadMoreError: null);
    try {
      final nextPage = _page + 1;
      final items = await _fetch(_search, nextPage, paginatedPageSize);
      _page = nextPage;
      state = state.copyWith(
        items: [...state.items, ...items],
        isLoadingMore: false,
        hasMore: items.length == paginatedPageSize,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, loadMoreError: e);
    }
  }
}
