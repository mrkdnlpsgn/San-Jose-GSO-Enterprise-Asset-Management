import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/auto_refresh_ticker.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/ui.dart';
import '../../../shared/widgets/main_shell.dart';
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
  /// 1 opens straight on the requests tab (e.g. from Home's "waiting for approval" item).
  final int initialTab;
  const AssetHistoryScreen({super.key, this.initialTab = 0});

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
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Asset History'),
          bottom: TabBar(
            indicatorColor: context.brandAccent,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerHeight: 0,
            labelColor: context.brandAccent,
            unselectedLabelColor: context.colors.textSecondary,
            labelStyle: const TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 16, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 16, fontWeight: FontWeight.w500),
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
                  ? const Center(child: CircularProgressIndicator())
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: isAdmin
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FieldLabel('Done or requested by'),
                DropdownButtonFormField<int?>(
              initialValue: _performerId,
              isExpanded: true,
              style: TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 16, color: context.colors.textPrimary),
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
            ),
              ],
            )
          : Callout('Showing the assets you are accountable for, and your own requests (${me?.username ?? ''}).'),
    );
  }

  Widget _historyList() {
    final items = _filteredHistory;
    return RefreshIndicator(
      onRefresh: _load,
      child: items.isEmpty
          ? _empty(_history!.isEmpty
              ? (_isAdmin ? 'No history recorded yet.' : 'No history yet for the assets you are accountable for.')
              : 'No changes by this person.')
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + context.mainShellBottomInset),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
            onRefresh: _load,
            child: items.isEmpty
                ? _empty(_requests!.isEmpty ? 'No requests yet.' : 'No requests match this filter.')
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + context.mainShellBottomInset),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
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
          Center(child: Text(message, style: TextStyle(color: context.colors.textSecondary, fontSize: 15))),
        ],
      );
}

String _fmtDate(String? iso) {
  final d = iso != null ? DateTime.tryParse(iso)?.toLocal() : null;
  if (d == null) return '—';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

Color _eventColor(String type) => switch (type) {
      'REGISTERED' => AppTheme.statusRegistered,
      'ASSIGNED' => AppTheme.brand,
      'TRANSFERRED' => AppTheme.statusTransferred,
      'MAINTENANCE' => AppTheme.statusMaintenance,
      'DISPOSAL' => AppTheme.statusDisposed,
      _ => AppTheme.statusArchived,
    };

/// "UNDER_MAINTENANCE" → "Under Maintenance"
String _titleCase(String raw) => raw
    .split('_')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');

class _HistoryCard extends StatelessWidget {
  final AssetHistoryModel item;
  const _HistoryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return RecordCard(
      onTap: () => context.push('/assets/${item.asset.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: StatusBadge(label: _titleCase(item.eventType), color: _eventColor(item.eventType))),
              const Spacer(),
              Text(_fmtDate(item.eventDate), style: TextStyle(color: c.textTertiary, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          CodeText(item.asset.propertyNumber),
          const SizedBox(height: 2),
          CardTitle(item.asset.description, maxLines: 1),
          const SizedBox(height: 6),
          MetaLine(Icons.person_rounded, 'By ${item.performedBy.fullName}'),
          if (item.fromOffice != null || item.toOffice != null) ...[
            const SizedBox(height: 4),
            MetaLine(
              Icons.swap_horiz_rounded,
              [item.fromOffice?.officeName, item.toOffice?.officeName].whereType<String>().join(' → '),
            ),
          ],
          if (item.notes != null && item.notes!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(item.notes!,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary, fontSize: 14)),
          ],
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final EditRequestModel item;
  const _RequestCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (String kindLabel, Color kindColor, String route) = switch (item.kind) {
      'MAINTENANCE' => ('Maintenance', AppTheme.statusMaintenance, '/maintenance/${item.recordId}'),
      // transfer requests are reviewed on the Transfer Asset screen, as on the web
      'TRANSFER' => ('Transfer', AppTheme.statusTransferred, '/transfers'),
      _ => ('Disposal', AppTheme.statusDisposed, '/disposal/${item.recordId}'),
    };
    final status =
        StatusBadge.approval(item.approvalStatus) ?? const StatusBadge(label: 'Approved', color: AppTheme.brand);
    final rejected = item.approvalStatus == 'REJECTED';
    return RecordCard(
      onTap: () => context.push(route),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  StatusBadge(label: kindLabel, color: kindColor),
                  status,
                ]),
              ),
              Text(_fmtDate(item.requestedAt), style: TextStyle(color: c.textTertiary, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          CodeText(item.propertyNumber),
          const SizedBox(height: 2),
          CardTitle(item.assetDescription, maxLines: 1),
          if (item.kind == 'TRANSFER' && item.detail != null && item.detail!.isNotEmpty) ...[
            const SizedBox(height: 6),
            MetaLine(Icons.swap_horiz_rounded, item.detail!),
          ],
          const SizedBox(height: 6),
          MetaLine(Icons.person_rounded, 'Requested by ${item.requestedByName ?? '—'}'),
          if (item.approvalStatus != 'PENDING_APPROVAL') ...[
            const SizedBox(height: 4),
            MetaLine(Icons.how_to_reg_rounded,
                'Reviewed by ${item.reviewedByName ?? '—'} · ${_fmtDate(item.reviewedAt)}'),
          ],
          if (item.reviewNote != null && item.reviewNote!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Callout(item.reviewNote!,
                title: rejected ? 'Reason for rejection' : 'Reviewer note',
                tone: rejected ? CalloutTone.error : CalloutTone.info),
          ],
        ],
      ),
    );
  }
}
