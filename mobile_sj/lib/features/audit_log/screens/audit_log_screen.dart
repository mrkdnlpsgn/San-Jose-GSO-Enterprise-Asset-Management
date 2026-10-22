import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/auto_refresh_ticker.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../shared/widgets/ui.dart';
import '../data/audit_log_service.dart';
import '../model/audit_log_model.dart';

final auditLogServiceProvider = Provider<AuditLogService>((ref) => AuditLogService());

/// The live audit log (the last year — older entries are archived), newest first.
final auditLogsProvider =
    FutureProvider.autoDispose<List<AuditLogModel>>((ref) => ref.watch(auditLogServiceProvider).list());

String _two(int n) => n.toString().padLeft(2, '0');

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

String _time(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${_two(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
}

DateTime? _local(String? iso) => iso == null ? null : DateTime.tryParse(iso)?.toLocal();

/// Admin: who did what, when — the web Audit Logs tab. Search and module filters work on the
/// loaded list; the Archive button exports or moves entries older than the retention limit.
class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  String? _module; // null = all

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matches(AuditLogModel l) {
    if (_module != null && l.module != _module) return false;
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return true;
    bool has(String? s) => s != null && s.toLowerCase().contains(q);
    return has(l.details) || has(l.actionLabel) || has(l.module) || has(l.username) || has(l.fullName);
  }

  // Day headings: Today, Yesterday, or the date.
  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return _date(d);
  }

  @override
  Widget build(BuildContext context) {
    final logsAsync = ref.watch(auditLogsProvider);
    // keep showing what's loaded while a background refresh runs or fails
    final logs = logsAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: TitleWithCount('Audit Logs', subtitle: countLabel(logs?.length, singular: 'entry', plural: 'entries')),
        bottom: ListToolbar(
          controller: _searchCtrl,
          hintText: 'Search activity or user',
          onSearch: (v) => setState(() => _search = v),
          extraButtons: [
            OutlinedButton.icon(
              icon: const Icon(Icons.inventory_2_outlined, size: 20),
              label: const Text('Archive'),
              style: toolbarButtonStyle(context),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                useRootNavigator: true,
                isScrollControlled: true,
                useSafeArea: true,
                showDragHandle: true,
                builder: (_) => _ArchiveSheet(onArchived: () => ref.invalidate(auditLogsProvider)),
              ),
            ),
          ],
        ),
      ),
      body: logs == null
          ? logsAsync.hasError
              ? ErrorState(
                  message: logsAsync.error is ApiException
                      ? (logsAsync.error as ApiException).message
                      : 'Failed to load audit logs.',
                  onRetry: () => ref.invalidate(auditLogsProvider),
                )
              : const Center(child: CircularProgressIndicator())
          : AutoRefreshTicker(
              interval: const Duration(seconds: 30),
              onTick: () => ref.invalidate(auditLogsProvider),
              child: RefreshIndicator(
                onRefresh: () => ref.refresh(auditLogsProvider.future),
                child: _list(context, logs),
              ),
            ),
    );
  }

  Widget _list(BuildContext context, List<AuditLogModel> logs) {
    final c = context.colors;
    final modules = (logs.map((l) => l.module).where((m) => m.isNotEmpty).toSet().toList())..sort();
    final shown = logs.where(_matches).toList();

    // flatten into heading + entry rows so ListView.builder stays lazy for a year of entries
    final rows = <Object>[];
    String? lastDay;
    for (final l in shown) {
      final t = _local(l.loggedAt);
      final day = t == null ? 'Unknown date' : _dayLabel(t);
      if (day != lastDay) {
        rows.add(day);
        lastDay = day;
      }
      rows.add(l);
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: rows.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final m in [null, ...modules]) ...[
                      ChoiceChip(
                        label: Text(m == null
                            ? 'All (${logs.length})'
                            : '$m (${logs.where((l) => l.module == m).length})'),
                        selected: _module == m,
                        onSelected: (_) => setState(() => _module = m),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 56),
                  child: Text(
                    logs.isEmpty ? 'No activity recorded yet.' : 'No entries match your search.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.textTertiary, fontSize: 15),
                  ),
                ),
            ],
          );
        }
        final row = rows[i - 1];
        if (row is String) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
            child: Text(row,
                style: TextStyle(color: c.textSecondary, fontSize: 15, fontWeight: FontWeight.w600)),
          );
        }
        final log = row as AuditLogModel;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _LogCard(log: log),
        );
      },
    );
  }
}

class _LogCard extends StatelessWidget {
  final AuditLogModel log;
  const _LogCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = _local(log.loggedAt);
    return RecordCard(
      onTap: () => _showDetails(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: CardTitle(log.actionLabel, maxLines: 1)),
              const SizedBox(width: 8),
              _ModuleBadge(log.module),
            ],
          ),
          if (log.details != null && log.details!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(log.details!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.textSecondary, fontSize: 14, height: 1.35)),
          ],
          const SizedBox(height: 6),
          MetaLine(Icons.person_outline_rounded, '${log.performedBy}${t != null ? ' · ${_time(t)}' : ''}'),
        ],
      ),
    );
  }

  void _showDetails(BuildContext context) {
    final t = _local(log.loggedAt);
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final c = ctx.colors;
        Widget row(String label, String? value) => value == null || value.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(color: c.textTertiary, fontSize: 13)),
                    const SizedBox(height: 2),
                    SelectableText(value, style: TextStyle(color: c.textPrimary, fontSize: 15, height: 1.4)),
                  ],
                ),
              );
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(log.actionLabel, style: TextStyle(color: c.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              row('Description', log.details),
              row('Module', log.module),
              row('Done by', log.username != null && log.fullName != null && log.fullName!.trim().isNotEmpty
                  ? '${log.fullName} (${log.username})'
                  : log.performedBy),
              row('Date and time', t == null ? null : '${_date(t)}, ${_time(t)}'),
              row('Record', log.targetType == null
                  ? null
                  : '${log.targetType}${log.targetId != null ? ' #${log.targetId}' : ''}'),
              row('Log ID', '${log.id}'),
            ],
          ),
        );
      },
    );
  }
}

class _ModuleBadge extends StatelessWidget {
  final String module;
  const _ModuleBadge(this.module);

  @override
  Widget build(BuildContext context) {
    final color = switch (module.toLowerCase()) {
      'assets' || 'asset' => AppTheme.statusAssigned,
      'maintenance' => AppTheme.statusMaintenance,
      'disposal' => AppTheme.statusDisposed,
      _ => AppTheme.statusArchived,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isLight ? 0.12 : 0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(module, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Entries older than the limit (one year by default) leave the list every night and go to an
/// archive. Here: how much is archived, export it (all or a date range) as CSV, or archive now.
class _ArchiveSheet extends ConsumerStatefulWidget {
  final VoidCallback onArchived;
  const _ArchiveSheet({required this.onArchived});

  @override
  ConsumerState<_ArchiveSheet> createState() => _ArchiveSheetState();
}

class _ArchiveSheetState extends ConsumerState<_ArchiveSheet> {
  late final AuditLogService _service = ref.read(auditLogServiceProvider);
  AuditArchiveSummary? _summary;
  String? _error;
  DateTime? _from;
  DateTime? _to;
  bool _exporting = false;
  bool _archiving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await _service.archiveSummary();
      if (mounted) setState(() => _summary = s);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.red.shade800 : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _pick({required bool from}) async {
    final s = _summary;
    final first = _local(s?.archivedOldest) ?? DateTime(2020);
    final last = _local(s?.archivedNewest) ?? DateTime.now();
    final current = from ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(first.year, first.month, first.day),
      lastDate: DateTime(last.year, last.month, last.day),
      initialDate: current ?? (from ? first : last),
      helpText: from ? 'Export from' : 'Export to',
    );
    if (picked != null) setState(() => from ? _from = picked : _to = picked);
  }

  Future<void> _export() async {
    if (_from != null && _to != null && _from!.isAfter(_to!)) {
      _toast('The start date is after the end date.', error: true);
      return;
    }
    setState(() => _exporting = true);
    try {
      await _service.exportArchive(from: _from, to: _to);
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _archiveNow() async {
    setState(() => _archiving = true);
    try {
      final s = await _service.archiveNow();
      if (!mounted) return;
      setState(() => _summary = s);
      final moved = s.moved ?? 0;
      _toast(moved > 0
          ? 'Moved $moved old ${moved == 1 ? 'entry' : 'entries'} to the archive.'
          : 'Nothing to archive — no entries are older than ${s.retentionLabel}.');
      if (moved > 0) widget.onArchived();
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    } finally {
      if (mounted) setState(() => _archiving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = _summary;
    final oldest = _local(s?.archivedOldest);
    final newest = _local(s?.archivedNewest);

    Widget dateButton(String label, DateTime? value, bool from) => Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_rounded, size: 18),
            label: Text(value == null ? label : _date(value), overflow: TextOverflow.ellipsis),
            style: toolbarButtonStyle(context, active: value != null),
            onPressed: () => _pick(from: from),
          ),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Archive', style: TextStyle(color: c.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (_error != null)
            Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 15))
          else if (s == null)
            const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()))
          else ...[
            Text(
              'Entries older than ${s.retentionLabel} move to the archive every night, so the list stays fast. '
              'Nothing is deleted.',
              style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.45),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.isLight ? const Color(0xFFF2F2F7) : const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                s.archivedCount == 0
                    ? 'The archive is empty.'
                    : '${s.archivedCount} archived ${s.archivedCount == 1 ? 'entry' : 'entries'}'
                        '${oldest != null && newest != null ? ', ${_date(oldest)} – ${_date(newest)}' : ''}.',
                style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
            if (s.archivedCount > 0) ...[
              const SizedBox(height: 20),
              Text('Export', style: TextStyle(color: c.textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Choose dates, or leave them empty to export everything. The file opens in Excel or Sheets.',
                  style: TextStyle(color: c.textTertiary, fontSize: 14, height: 1.4)),
              const SizedBox(height: 10),
              Row(children: [
                dateButton('From', _from, true),
                const SizedBox(width: 8),
                dateButton('To', _to, false),
              ]),
              if (_from != null || _to != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() => _from = _to = null),
                    child: const Text('Clear dates'),
                  ),
                ),
              const SizedBox(height: 10),
              FilledButton.icon(
                icon: _exporting
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.ios_share_rounded, size: 20),
                label: const Text('Export as CSV'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _exporting ? null : _export,
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              onPressed: _archiving ? null : _archiveNow,
              child: Text(_archiving ? 'Archiving…' : 'Archive old entries now'),
            ),
          ],
        ],
      ),
    );
  }
}
