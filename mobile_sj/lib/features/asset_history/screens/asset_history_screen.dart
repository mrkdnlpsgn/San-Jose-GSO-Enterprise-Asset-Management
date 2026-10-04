import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/auto_refresh_ticker.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../accounts/data/account_service.dart';
import '../../accounts/model/account_model.dart';
import '../../auth/provider/auth_provider.dart';
import '../data/asset_history_service.dart';
import '../model/asset_history_model.dart';
import '../model/edit_request_model.dart';

// Inventory changes ("History") and staff maintenance/disposal requests ("Requests"),
// mirrors web's Asset History page. An admin sees everything and can narrow it to one
// person; a staff account sees every change to the assets it is the accountable person
// for, and its own requests (the backend enforces both).
class AssetHistoryScreen extends ConsumerStatefulWidget {
  const AssetHistoryScreen({super.key});

  @override
  ConsumerState<AssetHistoryScreen> createState() => _AssetHistoryScreenState();
}

class _AssetHistoryScreenState extends ConsumerState<AssetHistoryScreen> {
  final _service = AssetHistoryService();

  List<AssetHistoryModel>? _history;
  List<EditRequestModel>? _requests;
  List<AccountModel> _users = const [];
  Object? _error;
  bool _loading = true;
  int? _performerId; // admin only — null = everyone
  String? _requestStatus; // null = all

  bool get _isAdmin => ref.read(authProvider).value?.isAdmin ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isAdmin) {
        AccountService().getAll().then((u) {
          if (mounted) setState(() => _users = u);
        }).catchError((_) {});
      }
      _load();
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        _service.getAccountable(),
        _service.getRequests(userId: _isAdmin ? _performerId : null),
      ]);
      if (!mounted) return;
      setState(() {
        _history = results[0] as List<AssetHistoryModel>;
        _requests = results[1] as List<EditRequestModel>;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<AssetHistoryModel> get _filteredHistory {
    final all = _history ?? const [];
    if (!_isAdmin || _performerId == null) return all;
    return all.where((h) => h.performedBy.id == _performerId).toList();
  }

  List<EditRequestModel> get _filteredRequests {
    final all = _requests ?? const [];
    if (_requestStatus == null) return all;
    return all.where((r) => r.approvalStatus == _requestStatus).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _isAdmin;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Asset History'),
          bottom: TabBar(
            indicatorColor: AppTheme.brand,
            labelColor: AppTheme.brand,
            tabs: [
              const Tab(text: 'History'),
              Tab(text: isAdmin ? 'Staff Requests' : 'My Requests'),
            ],
          ),
        ),
        body: Column(
          children: [
            _performerFilter(isAdmin),
            Expanded(
              child: _loading && _history == null
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.brand))
                  : _error != null && _history == null
                      ? ErrorState(message: _error.toString(), onRetry: _load)
                      : AutoRefreshTicker(
                          interval: const Duration(seconds: 30),
                          onTick: () => _load(silent: true),
                          child: TabBarView(children: [_historyList(), _requestsTab()]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _performerFilter(bool isAdmin) {
    final me = ref.read(authProvider).value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: isAdmin
          ? DropdownButtonFormField<int?>(
              initialValue: _performerId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Performed / requested by', isDense: true),
              dropdownColor: context.colors.surface,
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Everyone')),
                for (final u in _users)
                  DropdownMenuItem<int?>(
                    value: u.id,
                    child: Text('${u.fullName}${u.role == 'ADMIN' ? ' (Admin)' : ''}', overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) {
                setState(() => _performerId = v);
                _load();
              },
            )
          : InputDecorator(
              decoration: const InputDecoration(labelText: 'Showing', isDense: true),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Assets you are accountable for · your requests (${me?.username ?? ''})',
                        style: TextStyle(color: context.colors.textPrimary)),
                  ),
                  Icon(Icons.lock_outline_rounded, size: 16, color: context.colors.textTertiary),
                ],
              ),
            ),
    );
  }

  Widget _historyList() {
    final items = _filteredHistory;
    return RefreshIndicator(
      color: AppTheme.brand,
      onRefresh: _load,
      child: items.isEmpty
          ? _empty(_history!.isEmpty
              ? (_isAdmin ? 'No history recorded yet.' : 'No history yet for the assets you are accountable for.')
              : 'No changes by this person.')
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _HistoryCard(item: items[i]),
            ),
    );
  }

  Widget _requestsTab() {
    final items = _filteredRequests;
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              for (final (value, label) in const [
                (null, 'All'),
                ('PENDING_APPROVAL', 'Pending'),
                ('APPROVED', 'Approved'),
                ('REJECTED', 'Rejected'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _requestStatus == value,
                    onSelected: (_) => setState(() => _requestStatus = value),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.brand,
            onRefresh: _load,
            child: items.isEmpty
                ? _empty(_requests!.isEmpty ? 'No requests yet.' : 'No requests match this filter.')
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _RequestCard(item: items[i]),
                  ),
          ),
        ),
      ],
    );
  }

  // Scrollable so pull-to-refresh still works on an empty list.
  Widget _empty(String message) => ListView(
        children: [
          const SizedBox(height: 80),
          Center(child: Text(message, style: TextStyle(color: context.colors.textSecondary))),
        ],
      );
}

String _fmtDate(String? iso) {
  final d = iso != null ? DateTime.tryParse(iso) : null;
  if (d == null) return '—';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

Color _eventColor(String type) => switch (type) {
      'REGISTERED' => AppTheme.statusAssigned,
      'ASSIGNED' => AppTheme.brand,
      'TRANSFERRED' => AppTheme.statusTransferred,
      'MAINTENANCE' => AppTheme.statusMaintenance,
      'DISPOSAL' => AppTheme.statusDisposed,
      _ => AppTheme.statusRegistered,
    };

class _HistoryCard extends StatelessWidget {
  final AssetHistoryModel item;
  const _HistoryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/assets/${item.asset.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusBadge(label: item.eventType, color: _eventColor(item.eventType), dense: true),
                  const Spacer(),
                  Text(_fmtDate(item.eventDate), style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 8),
              Text(item.asset.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(item.asset.propertyNumber, style: const TextStyle(color: AppTheme.brand, fontSize: 12)),
              const SizedBox(height: 6),
              Text(
                'By ${item.performedBy.fullName}'
                '${item.fromOffice != null ? ' · from ${item.fromOffice!.officeName}' : ''}',
                style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
              ),
              if (item.notes != null && item.notes!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(item.notes!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final EditRequestModel item;
  const _RequestCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final maintenance = item.kind == 'MAINTENANCE';
    final status = StatusBadge.approval(item.approvalStatus) ??
        const StatusBadge(label: 'Approved', color: AppTheme.brand, dense: true);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(maintenance ? '/maintenance/${item.recordId}' : '/disposal/${item.recordId}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusBadge(
                    label: maintenance ? 'Under Maintenance' : 'Disposal',
                    color: maintenance ? AppTheme.statusMaintenance : AppTheme.statusDisposed,
                    dense: true,
                  ),
                  const SizedBox(width: 6),
                  status,
                  const Spacer(),
                  Text(_fmtDate(item.requestedAt), style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 8),
              Text(item.assetDescription,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(item.propertyNumber, style: const TextStyle(color: AppTheme.brand, fontSize: 12)),
              const SizedBox(height: 6),
              Text('Requested by ${item.requestedByName ?? '—'}',
                  style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
              if (item.approvalStatus != 'PENDING_APPROVAL') ...[
                const SizedBox(height: 2),
                Text('Reviewed by ${item.reviewedByName ?? '—'} · ${_fmtDate(item.reviewedAt)}',
                    style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
              ],
              if (item.reviewNote != null && item.reviewNote!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('Reason: ${item.reviewNote}',
                    style: const TextStyle(color: AppTheme.statusDisposed, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
