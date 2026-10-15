import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/ui.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/data/reference_service.dart';
import '../../../shared/provider/reference_provider.dart';
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
        title: TitleWithCount('Categories', subtitle: countLabel(categoriesAsync.value?.length, singular: 'category', plural: 'categories')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add Category'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 14)),
              onPressed: () async {
                final result = await context.push<bool>('/categories/new');
                if (result == true) ref.invalidate(categoriesProvider);
              },
            ),
          ),
        ],
        bottom: ListToolbar(
          controller: _searchCtrl,
          hintText: 'Search categories',
          onSearch: (v) => setState(() => _search = v),
        ),
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load categories: $e')),
        data: (categories) {
          final filtered = _search.trim().isEmpty
              ? categories
              : categories.where((c) => c.categoryName.toLowerCase().contains(_search.trim().toLowerCase())).toList();

          if (filtered.isEmpty) {
            return Center(
              child: Text(
                categories.isEmpty ? 'No categories yet.' : 'No categories match your search.',
                style: TextStyle(color: context.colors.textTertiary, fontSize: 15),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(categoriesProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final cat = filtered[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: RecordCard(
                    onTap: () async {
                      final result = await context.push<bool>('/categories/${cat.id}/edit', extra: cat);
                      if (result == true) ref.invalidate(categoriesProvider);
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
                      tooltip: 'Delete',
                      onPressed: () => _delete(cat),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CardTitle(cat.categoryName),
                          if (cat.description != null && cat.description!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(cat.description!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: context.colors.textTertiary, fontSize: 14)),
                          ],
                          const SizedBox(height: 6),
                          Text('Tap to edit', style: TextStyle(color: context.brandAccent, fontSize: 14, fontWeight: FontWeight.w600)),
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
