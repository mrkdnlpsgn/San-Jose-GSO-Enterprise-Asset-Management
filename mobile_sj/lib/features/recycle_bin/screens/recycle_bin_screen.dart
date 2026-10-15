import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/main_shell.dart';
import '../../../shared/widgets/auto_refresh_ticker.dart';
import '../../../shared/widgets/app_search_field.dart';
import '../../../shared/widgets/ui.dart';
import '../data/recycle_bin_service.dart';
import '../model/deleted_asset_model.dart';
import '../model/deleted_maintenance_model.dart';
import '../model/deleted_disposal_model.dart';
import '../provider/recycle_bin_provider.dart';

class RecycleBinScreen extends ConsumerWidget {
  const RecycleBinScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Recycle Bin'),
          bottom: TabBar(
            indicatorColor: context.brandAccent,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerHeight: 0,
            labelColor: context.brandAccent,
            unselectedLabelColor: context.colors.textSecondary,
            labelStyle: const TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 15, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 15, fontWeight: FontWeight.w500),
            tabs: const [
              Tab(text: 'Assets'),
              Tab(text: 'Maintenance'),
              Tab(text: 'Disposal'),
            ],
          ),
        ),
        body: AutoRefreshTicker(
          interval: const Duration(seconds: 30),
          onTick: () {
            ref.invalidate(deletedAssetsProvider);
            ref.invalidate(deletedMaintenanceProvider);
            ref.invalidate(deletedDisposalProvider);
          },
          child: const TabBarView(
            children: [_AssetsTab(), _MaintenanceTab(), _DisposalTab()],
          ),
        ),
      ),
    );
  }
}

// Shared shape for all three tabs: watch a provider, render the standard
// loading/error/empty/list states, with the item widget supplied per-type.
// Keeps the last successful snapshot on screen while a background poll
// (AutoRefreshTicker invalidating the provider every 30s) refetches, instead
// of dropping back to the skeleton — the same "don't flicker on silent
// refresh" approach as the Dashboard's stats section.
class _RecycleBinTab<T> extends ConsumerStatefulWidget {
  final AutoDisposeFutureProvider<List<T>> provider;
  final Widget Function(BuildContext, WidgetRef, T) itemBuilder;
  final String emptyMessage;
  final String searchHint;
  final bool Function(T, String) matches;

  const _RecycleBinTab({
    required this.provider,
    required this.itemBuilder,
    required this.emptyMessage,
    required this.searchHint,
    required this.matches,
  });

  @override
  ConsumerState<_RecycleBinTab<T>> createState() => _RecycleBinTabState<T>();
}

class _RecycleBinTabState<T> extends ConsumerState<_RecycleBinTab<T>> {
  List<T>? _lastItems;
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(widget.provider);
    if (async.hasValue) _lastItems = async.value;
    final items = _lastItems;

    final searchBar = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: AppSearchField(
        controller: _searchCtrl,
        hintText: widget.searchHint,
        onChanged: (v) => setState(() => _search = v),
      ),
    );

    if (items == null) {
      return Column(
        children: [
          searchBar,
          Expanded(
            child: async.when(
              loading: () => const ListSkeleton(),
              error: (e, _) => ErrorState(message: e.toString(), onRetry: () => ref.invalidate(widget.provider)),
              data: (_) => const SizedBox.shrink(), // unreachable: _lastItems would already be set
            ),
          ),
        ],
      );
    }

    final q = _search.trim().toLowerCase();
    final filtered = q.isEmpty ? items : items.where((item) => widget.matches(item, q)).toList();

    return Column(
      children: [
        searchBar,
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    items.isEmpty ? widget.emptyMessage : 'No records match your search.',
                    style: TextStyle(color: context.colors.textTertiary, fontSize: 15),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async => ref.invalidate(widget.provider),
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + context.mainShellBottomInset),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => widget.itemBuilder(context, ref, filtered[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

// A simple yes/no prompt — restoring isn't destructive, but it does modify
// live data, so a lightweight confirmation avoids accidental taps.
Future<bool> _confirmRestore(BuildContext context, String label) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Restore this $label?'),
      content: Text(
        'It will reappear in its original list, exactly as it was before deletion.',
        style: TextStyle(color: ctx.colors.textSecondary, fontSize: 15, height: 1.45),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
      ],
    ),
  );
  return confirmed ?? false;
}

Future<void> _handleRestore(
  BuildContext context,
  WidgetRef ref,
  String label,
  Future<void> Function() restoreCall,
  AutoDisposeFutureProvider provider,
) async {
  final confirmed = await _confirmRestore(context, label.toLowerCase());
  if (!confirmed || !context.mounted) return;
  try {
    await restoreCall();
    ref.invalidate(provider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label restored.')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade800),
      );
    }
  }
}

const _kResendCooldownSeconds = 60;

// Step-up 2FA before an irreversible delete: emails a one-time code on open,
// then requires it back before calling deleteCall. Pops `true` only once the
// permanent delete actually succeeds; verification failures stay in the
// dialog so the user can retry without re-triggering the whole flow.
class _PermanentDeleteDialog extends StatefulWidget {
  final String label;
  final Future<void> Function(String otp) deleteCall;
  const _PermanentDeleteDialog({required this.label, required this.deleteCall});

  @override
  State<_PermanentDeleteDialog> createState() => _PermanentDeleteDialogState();
}

class _PermanentDeleteDialogState extends State<_PermanentDeleteDialog> {
  final _otpCtrl = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  bool _deleting = false;
  int _cooldown = 0;
  String? _error;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _sendCode();
  }

  @override
  void dispose() {
    _otpCtrl.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _cooldown = _kResendCooldownSeconds);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        if (_cooldown <= 1) { _cooldown = 0; t.cancel(); } else { _cooldown--; }
      });
    });
  }

  Future<void> _sendCode() async {
    setState(() { _sending = true; _error = null; });
    try {
      await RecycleBinService().requestDeleteOtp();
      if (!mounted) return;
      setState(() => _sent = true);
      _startCooldown();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _confirm() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) { setState(() => _error = 'Enter the 6-digit code from your email.'); return; }
    setState(() { _deleting = true; _error = null; });
    try {
      await widget.deleteCall(otp);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _deleting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Permanently delete this ${widget.label.toLowerCase()}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This cannot be undone — the record will be completely removed, not just moved out of the '
            'Recycle Bin.${_sending ? ' Sending a verification code to your email…' : _sent ? ' Enter the verification code we emailed you to confirm.' : ''}',
            style: TextStyle(color: context.colors.textSecondary, fontSize: 15, height: 1.45),
          ),
          if (_sent) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _otpCtrl,
              autofocus: true,
              maxLength: 6,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(letterSpacing: 8, fontSize: 22, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(counterText: '', hintText: '••••••'),
              onChanged: (_) => setState(() => _error = null),
            ),
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: (_cooldown > 0 || _sending) ? null : _sendCode,
                child: Text(_cooldown > 0 ? 'Resend code in ${_cooldown}s' : 'Resend code'),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 4),
            Callout(_error!, tone: CalloutTone.error),
          ],
        ],
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: (!_sent || _deleting || _otpCtrl.text.trim().length != 6) ? null : _confirm,
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
          child: Text(_deleting ? 'Deleting…' : 'Delete forever'),
        ),
      ],
    );
  }
}

Future<void> _handlePermanentDelete(
  BuildContext context,
  WidgetRef ref,
  String label,
  Future<void> Function(String otp) deleteCall,
  AutoDisposeFutureProvider provider,
) async {
  final deleted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _PermanentDeleteDialog(label: label.toLowerCase(), deleteCall: deleteCall),
  );
  if (deleted != true || !context.mounted) return;
  ref.invalidate(provider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$label permanently deleted.'), backgroundColor: Colors.red.shade800),
  );
}

class _RecycleBinCard extends StatelessWidget {
  final String propertyNumber;
  final String? parNumber;
  final String description;
  final List<Widget> badges;
  final String deletedByUsername;
  final String deletedAt;
  final String? deleteReason;
  final VoidCallback onRestore;
  final VoidCallback onPermanentDelete;

  const _RecycleBinCard({
    required this.propertyNumber,
    this.parNumber,
    required this.description,
    required this.badges,
    required this.deletedByUsername,
    required this.deletedAt,
    this.deleteReason,
    required this.onRestore,
    required this.onPermanentDelete,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CodeText(parNumber != null && parNumber!.isNotEmpty ? '$propertyNumber · PAR $parNumber' : propertyNumber),
            const SizedBox(height: 4),
            CardTitle(description),
            if (badges.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: badges),
            ],
            const SizedBox(height: 10),
            MetaLine(Icons.delete_outline_rounded, 'Deleted by $deletedByUsername · ${_fmt(deletedAt)}'),
            if (deleteReason != null && deleteReason!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Reason: $deleteReason', style: TextStyle(fontSize: 14, color: c.textSecondary)),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPermanentDelete,
                    icon: const Icon(Icons.delete_forever_rounded, size: 20),
                    label: const Text('Delete forever'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onRestore,
                    icon: const Icon(Icons.restore_rounded, size: 20),
                    label: const Text('Restore'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _AssetsTab extends StatelessWidget {
  const _AssetsTab();

  @override
  Widget build(BuildContext context) {
    return _RecycleBinTab<DeletedAssetModel>(
      provider: deletedAssetsProvider,
      emptyMessage: 'No deleted assets.',
      searchHint: 'Search name or property no.',
      matches: (a, q) =>
          a.description.toLowerCase().contains(q) ||
          a.propertyNumber.toLowerCase().contains(q) ||
          (a.parNumber?.toLowerCase().contains(q) ?? false) ||
          a.categoryName.toLowerCase().contains(q) ||
          a.officeName.toLowerCase().contains(q),
      itemBuilder: (context, ref, a) => _RecycleBinCard(
        propertyNumber: a.propertyNumber,
        parNumber: a.parNumber,
        description: a.description,
        badges: [
          _InfoChip(a.categoryName),
          _InfoChip(a.officeName),
        ],
        deletedByUsername: a.deletedByUsername,
        deletedAt: a.deletedAt,
        deleteReason: a.deleteReason,
        onRestore: () => _handleRestore(
          context, ref, 'Asset',
          () => ref.read(recycleBinServiceProvider).restoreAsset(a.id),
          deletedAssetsProvider,
        ),
        onPermanentDelete: () => _handlePermanentDelete(
          context, ref, 'Asset',
          (otp) => ref.read(recycleBinServiceProvider).permanentDeleteAsset(a.id, otp),
          deletedAssetsProvider,
        ),
      ),
    );
  }
}

class _MaintenanceTab extends StatelessWidget {
  const _MaintenanceTab();

  @override
  Widget build(BuildContext context) {
    return _RecycleBinTab<DeletedMaintenanceModel>(
      provider: deletedMaintenanceProvider,
      emptyMessage: 'No deleted maintenance records.',
      searchHint: 'Search name or property no.',
      matches: (m, q) =>
          m.assetDescription.toLowerCase().contains(q) ||
          m.propertyNumber.toLowerCase().contains(q) ||
          (m.parNumber?.toLowerCase().contains(q) ?? false),
      itemBuilder: (context, ref, m) => _RecycleBinCard(
        propertyNumber: m.propertyNumber,
        parNumber: m.parNumber,
        description: m.assetDescription,
        badges: [
          StatusBadge.maintenanceType(m.maintenanceType),
          StatusBadge.maintenanceStatus(m.status),
        ],
        deletedByUsername: m.deletedByUsername,
        deletedAt: m.deletedAt,
        deleteReason: m.deleteReason,
        onRestore: () => _handleRestore(
          context, ref, 'Maintenance record',
          () => ref.read(recycleBinServiceProvider).restoreMaintenance(m.id),
          deletedMaintenanceProvider,
        ),
        onPermanentDelete: () => _handlePermanentDelete(
          context, ref, 'Maintenance record',
          (otp) => ref.read(recycleBinServiceProvider).permanentDeleteMaintenance(m.id, otp),
          deletedMaintenanceProvider,
        ),
      ),
    );
  }
}

class _DisposalTab extends StatelessWidget {
  const _DisposalTab();

  @override
  Widget build(BuildContext context) {
    return _RecycleBinTab<DeletedDisposalModel>(
      provider: deletedDisposalProvider,
      emptyMessage: 'No deleted disposal records.',
      searchHint: 'Search name or property no.',
      matches: (d, q) =>
          d.assetDescription.toLowerCase().contains(q) ||
          d.propertyNumber.toLowerCase().contains(q) ||
          (d.parNumber?.toLowerCase().contains(q) ?? false),
      itemBuilder: (context, ref, d) => _RecycleBinCard(
        propertyNumber: d.propertyNumber,
        parNumber: d.parNumber,
        description: d.assetDescription,
        badges: [
          StatusBadge.disposalMethod(d.recommendedMethod),
          StatusBadge.disposalStatus(d.disposalStatus),
        ],
        deletedByUsername: d.deletedByUsername,
        deletedAt: d.deletedAt,
        deleteReason: d.deleteReason,
        onRestore: () => _handleRestore(
          context, ref, 'Disposal record',
          () => ref.read(recycleBinServiceProvider).restoreDisposal(d.id),
          deletedDisposalProvider,
        ),
        onPermanentDelete: () => _handlePermanentDelete(
          context, ref, 'Disposal record',
          (otp) => ref.read(recycleBinServiceProvider).permanentDeleteDisposal(d.id, otp),
          deletedDisposalProvider,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  const _InfoChip(this.label);

  @override
  Widget build(BuildContext context) => StatusBadge(label: label, color: AppTheme.statusArchived);
}
