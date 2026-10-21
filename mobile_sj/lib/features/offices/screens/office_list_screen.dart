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

class OfficeListScreen extends ConsumerStatefulWidget {
  const OfficeListScreen({super.key});

  @override
  ConsumerState<OfficeListScreen> createState() => _OfficeListScreenState();
}

class _OfficeListScreenState extends ConsumerState<OfficeListScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _delete(OfficeModel office) async {
    final confirm = await showDeleteDialog(context, requireReason: false);
    if (confirm == null || !mounted) return;
    try {
      await ReferenceService().deleteOffice(office.id);
      ref.invalidate(officesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Office deleted.'), behavior: SnackBarBehavior.floating),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409) {
        showInfoDialog(context, title: "Can't delete this office", message: e.message);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade800, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final officesAsync = ref.watch(officesProvider);

    return Scaffold(
      appBar: AppBar(
        title: TitleWithCount('Offices',
            subtitle: countLabel(officesAsync.valueOrNull?.length, singular: 'office', plural: 'offices')),
        bottom: ListToolbar(
          primaryAction: FilledButton.icon(
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Add Office'),
            onPressed: () async {
              final result = await context.push<bool>('/offices/new');
              if (result == true) ref.invalidate(officesProvider);
            },
          ),
          controller: _searchCtrl,
          hintText: 'Search offices',
          onSearch: (v) => setState(() => _search = v),
        ),
      ),
      body: officesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load offices: $e')),
        data: (offices) {
          final filtered = _search.trim().isEmpty
              ? offices
              : offices.where((o) => o.officeName.toLowerCase().contains(_search.trim().toLowerCase())).toList();

          if (filtered.isEmpty) {
            return Center(
              child: Text(
                offices.isEmpty ? 'No offices yet.' : 'No offices match your search.',
                style: TextStyle(color: context.colors.textTertiary, fontSize: 15),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(officesProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final office = filtered[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: RecordCard(
                    onTap: () async {
                      final result = await context.push<bool>('/offices/${office.id}/edit', extra: office);
                      if (result == true) ref.invalidate(officesProvider);
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
                      tooltip: 'Delete',
                      onPressed: () => _delete(office),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CardTitle(office.officeName),
                        const SizedBox(height: 4),
                        MetaLine(Icons.person_rounded, office.headUserName ?? 'No head assigned'),
                        const SizedBox(height: 6),
                        Text('Tap to edit',
                            style: TextStyle(color: context.brandAccent, fontSize: 14, fontWeight: FontWeight.w600)),
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
