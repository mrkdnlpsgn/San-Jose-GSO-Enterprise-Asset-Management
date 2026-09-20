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
            indicatorColor: AppTheme.brand,
            labelColor: AppTheme.brand,
            unselectedLabelColor: context.colors.textSecondary,
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
                    style: TextStyle(color: context.colors.textTertiary),
                  ),
                )
              : RefreshIndicator(
                  color: AppTheme.brand,
                  onRefresh: () async => ref.invalidate(widget.provider),
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + context.mainShellBottomInset),
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
      backgroundColor: ctx.colors.surface,
      title: Text('Restore this $label?', style: TextStyle(color: ctx.colors.textPrimary)),
      content: Text(
        'It will reappear in its original list, exactly as it was before deletion.',
        style: TextStyle(color: ctx.colors.textTertiary, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Cancel', style: TextStyle(color: ctx.colors.textTertiary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Restore', style: TextStyle(color: AppTheme.brand)),
        ),
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
        SnackBar(content: Text('$label restored.'), backgroundColor: Colors.green.shade800),
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
      backgroundColor: context.colors.surface,
      title: Text('Permanently delete this ${widget.label.toLowerCase()}?',
          style: TextStyle(color: context.colors.textPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This cannot be undone — the record will be completely removed, not just moved out of the '
            'Recycle Bin.${_sending ? ' Sending a verification code to your email…' : _sent ? ' Enter the verification code we emailed you to confirm.' : ''}',
            style: TextStyle(color: context.colors.textTertiary, fontSize: 13),
          ),
          if (_sent) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _otpCtrl,
              autofocus: true,
              maxLength: 6,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(letterSpacing: 8, fontSize: 18),
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
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: TextStyle(color: context.colors.textTertiary)),
        ),
        TextButton(
          onPressed: (!_sent || _deleting || _otpCtrl.text.trim().length != 6) ? null : _confirm,
          child: Text(_deleting ? 'Deleting…' : 'Permanently Delete', style: const TextStyle(color: Colors.red)),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(propertyNumber,
                style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: context.colors.textSecondary)),
            if (parNumber != null && parNumber!.isNotEmpty)
              Text('PAR: $parNumber',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: context.colors.textTertiary)),
            const SizedBox(height: 2),
            Text(description,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: context.colors.textPrimary)),
            if (badges.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: badges),
            ],
            const SizedBox(height: 10),
            Text('Deleted by $deletedByUsername · ${_fmt(deletedAt)}',
                style: TextStyle(fontSize: 11.5, color: context.colors.textTertiary)),
            if (deleteReason != null && deleteReason!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(deleteReason!,
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: context.colors.textTertiary)),
            ],
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onPermanentDelete,
                  icon: const Icon(Icons.delete_forever_rounded, size: 16),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
                TextButton.icon(
                  onPressed: onRestore,
                  icon: const Icon(Icons.restore_rounded, size: 16),
                  label: const Text('Restore'),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.brand),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(String iso) {
    final dt = DateTime.tryParse(iso);
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
      searchHint: 'Search by device name or property number...',
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
      searchHint: 'Search by device name or property number...',
      matches: (m, q) =>
          m.assetDescription.toLowerCase().contains(q) ||
          m.propertyNumber.toLowerCase().contains(q) ||
          (m.parNumber?.toLowerCase().contains(q) ?? false),
      itemBuilder: (context, ref, m) => _RecycleBinCard(
        propertyNumber: m.propertyNumber,
        parNumber: m.parNumber,
        description: m.assetDescription,
        badges: [
          StatusBadge.maintenanceType(m.maintenanceType, dense: true),
          StatusBadge.maintenanceStatus(m.status, dense: true),
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
      searchHint: 'Search by device name or property number...',
      matches: (d, q) =>
          d.assetDescription.toLowerCase().contains(q) ||
          d.propertyNumber.toLowerCase().contains(q) ||
          (d.parNumber?.toLowerCase().contains(q) ?? false),
      itemBuilder: (context, ref, d) => _RecycleBinCard(
        propertyNumber: d.propertyNumber,
        parNumber: d.parNumber,
        description: d.assetDescription,
        badges: [
          StatusBadge.disposalMethod(d.recommendedMethod, dense: true),
          StatusBadge.disposalStatus(d.disposalStatus, dense: true),
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
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.colors.border.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: context.colors.textSecondary)),
    );
  }
}
