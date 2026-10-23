import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/provider/reference_provider.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/ui.dart';
import '../../auth/model/user_model.dart' show roleLabel;
import '../data/personnel_service.dart';

final personnelListProvider = FutureProvider.autoDispose<List<PersonnelRecord>>((ref) => PersonnelService().getAll());

/// Personnel - mirrors the web page: every account with its office and contact info, and
/// "Assign office" / "Change office". [needsOfficeOnly] opens it filtered to accounts
/// without an office (from Home's "Needs your attention").
class PersonnelListScreen extends ConsumerStatefulWidget {
  final bool needsOfficeOnly;
  const PersonnelListScreen({super.key, this.needsOfficeOnly = false});

  @override
  ConsumerState<PersonnelListScreen> createState() => _PersonnelListScreenState();
}

class _PersonnelListScreenState extends ConsumerState<PersonnelListScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  late bool _needsOfficeOnly = widget.needsOfficeOnly;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _edit(PersonnelRecord p) async {
    final saved = await context.push<PersonnelRecord>('/personnel/${p.id}/edit', extra: p);
    if (saved == null || !mounted) return;
    ref.invalidate(personnelListProvider);
    ref.invalidate(personnelProvider); // asset and transfer forms list personnel too
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${saved.fullName} assigned to ${saved.officeName ?? 'the office'}.'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  bool _matches(PersonnelRecord p, String q) =>
      p.fullName.toLowerCase().contains(q) ||
      (p.username ?? '').toLowerCase().contains(q) ||
      (p.officeName ?? '').toLowerCase().contains(q);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(personnelListProvider);
    final c = context.colors;

    return Scaffold(
      appBar: AppBar(
        title: TitleWithCount('Personnel',
            subtitle: countLabel(async.valueOrNull?.length, singular: 'person', plural: 'people')),
        bottom: ListToolbar(
          controller: _searchCtrl,
          hintText: 'Search name, username, office',
          onSearch: (v) => setState(() => _search = v),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load personnel: $e', textAlign: TextAlign.center),
          ),
        ),
        data: (all) {
          final missing = all.where((p) => p.needsOffice).length;
          final q = _search.trim().toLowerCase();
          final shown = all
              .where((p) => !_needsOfficeOnly || p.needsOffice)
              .where((p) => q.isEmpty || _matches(p, q))
              .toList();

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(personnelListProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: !_needsOfficeOnly,
                      onSelected: (_) => setState(() => _needsOfficeOnly = false),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(missing > 0 ? 'Needs an office ($missing)' : 'Needs an office'),
                      selected: _needsOfficeOnly,
                      onSelected: (_) => setState(() => _needsOfficeOnly = true),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (missing > 0 && !_needsOfficeOnly) ...[
                  Callout(
                    '$missing active ${missing == 1 ? 'account still needs' : 'accounts still need'} an office. '
                    'Staff without one can\'t see any assets.',
                    tone: CalloutTone.warning,
                  ),
                  const SizedBox(height: 12),
                ],
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Text(
                      all.isEmpty
                          ? 'No accounts yet. Create one on the Accounts page.'
                          : _needsOfficeOnly && q.isEmpty
                              ? 'Every active account has an office.'
                              : 'No personnel match your search.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.textTertiary, fontSize: 15),
                    ),
                  ),
                for (final p in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PersonCard(person: p, onEdit: () => _edit(p)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  final PersonnelRecord person;
  final VoidCallback onEdit;
  const _PersonCard({required this.person, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = person;
    final label = TextStyle(color: c.textTertiary, fontSize: 14);

    return RecordCard(
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardTitle(p.fullName),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (p.username != null) CodeText('@${p.username}', size: 13.5),
              if (p.userRole != null)
                StatusBadge(
                  label: roleLabel(p.userRole!),
                  color: p.isAdmin ? AppTheme.brand : AppTheme.statusArchived,
                  dense: true,
                ),
              if (!p.userActive) const StatusBadge(label: 'Inactive', color: AppTheme.statusDisposed, dense: true),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 72, child: Text(p.officeIds.length > 1 ? 'Offices' : 'Office', style: label)),
              Expanded(
                child: p.officeName != null
                    ? Text(p.officeName!, style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w500))
                    : Text('Not assigned',
                        style: TextStyle(
                          color: context.isLight ? const Color(0xFFB45309) : const Color(0xFFFBBF24),
                          fontSize: 15,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w600,
                        )),
              ),
            ],
          ),
          if (p.position != null && p.position!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 72, child: Text('Position', style: label)),
                Expanded(child: Text(p.position!, style: TextStyle(color: c.textSecondary, fontSize: 15))),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 72, child: Text('Contact', style: label)),
              Expanded(child: Text(p.contactInfo ?? 'N/A', style: TextStyle(color: c.textSecondary, fontSize: 15))),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onEdit,
            icon: Icon(p.officeName == null ? Icons.add_business_rounded : Icons.edit_rounded, size: 18),
            label: Text(p.officeName == null ? 'Assign offices' : 'Change offices'),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.brandAccent,
              side: BorderSide(color: AppTheme.brand.withValues(alpha: 0.5)),
              minimumSize: const Size(0, 44),
            ),
          ),
        ],
      ),
    );
  }
}
