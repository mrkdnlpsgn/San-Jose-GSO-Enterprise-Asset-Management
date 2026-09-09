import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/data/reference_service.dart';
import '../../../shared/provider/reference_provider.dart';
import '../../../shared/widgets/app_search_field.dart';
import '../../../shared/widgets/delete_dialog.dart';
import '../../../shared/widgets/info_dialog.dart';
import '../../assets/model/asset_model.dart';

class CategoryListScreen extends ConsumerStatefulWidget {
  const CategoryListScreen({super.key});

  @override
  ConsumerState<CategoryListScreen> createState() => _CategoryListScreenState();
}

class _CategoryListScreenState extends ConsumerState<CategoryListScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _delete(CategoryModel cat) async {
    final confirm = await showDeleteDialog(context, requireReason: false);
    if (confirm == null || !mounted) return;
    try {
      await ReferenceService().deleteCategory(cat.id);
      ref.invalidate(categoriesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Category deleted.'), behavior: SnackBarBehavior.floating),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409) {
        showInfoDialog(context, title: "Can't delete this category", message: e.message);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade800, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: AppSearchField(
              controller: _searchCtrl,
              hintText: 'Search categories...',
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.brand,
        child: const Icon(Icons.add_rounded, color: Colors.white),
        onPressed: () async {
          final result = await context.push<bool>('/categories/new');
          if (result == true) ref.invalidate(categoriesProvider);
        },
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.brand)),
        error: (e, _) => Center(child: Text('Failed to load categories: $e')),
        data: (categories) {
          final filtered = _search.trim().isEmpty
              ? categories
              : categories.where((c) => c.categoryName.toLowerCase().contains(_search.trim().toLowerCase())).toList();

          if (filtered.isEmpty) {
            return Center(
              child: Text(
                categories.isEmpty ? 'No categories yet.' : 'No categories match your search.',
                style: TextStyle(color: context.colors.textTertiary),
              ),
            );
          }

          return RefreshIndicator(
            color: AppTheme.brand,
            onRefresh: () async => ref.invalidate(categoriesProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final cat = filtered[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(cat.categoryName,
                                  style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                              if (cat.description != null && cat.description!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(cat.description!,
                                    style: TextStyle(color: context.colors.textTertiary, fontSize: 12.5),
                                    maxLines: 2, overflow: TextOverflow.ellipsis),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.edit_outlined, color: context.colors.textSecondary, size: 20),
                          tooltip: 'Edit',
                          onPressed: () async {
                            final result = await context.push<bool>('/categories/${cat.id}/edit', extra: cat);
                            if (result == true) ref.invalidate(categoriesProvider);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                          tooltip: 'Delete',
                          onPressed: () => _delete(cat),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
