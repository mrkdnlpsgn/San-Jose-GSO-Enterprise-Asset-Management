import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/connectivity/connectivity_provider.dart';
import '../../core/offline/outbox.dart';
import '../../core/theme/app_theme.dart';
import '../dashboard/widgets/ios_style.dart';
import 'sync_engine.dart';

/// Changes made on this phone that haven't reached the server yet: what's waiting, what needs
/// the user (a clash with someone else's edit, a refusal), and an Upload button.
class OutboxScreen extends ConsumerWidget {
  const OutboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(outboxProvider).items;
    final sync = ref.watch(syncEngineProvider);
    final online = ref.watch(isOnlineProvider).valueOrNull ?? !ApiClient.instance.deviceOffline;
    final attention = items.where((i) => i.needsAttention).toList();
    final waiting = items.where((i) => !i.needsAttention).toList();

    return Theme(
      data: Ios.theme(context),
      child: Scaffold(
        backgroundColor: Ios.groupedBg(context),
        appBar: AppBar(title: const Text('Waiting to Upload')),
        body: items.isEmpty
            ? const _Empty()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _StatusCard(
                    online: online,
                    syncing: sync.syncing,
                    done: sync.done,
                    total: sync.total,
                    waiting: waiting.length,
                    onUpload: online && !sync.syncing && waiting.isNotEmpty
                        ? () => ref.read(syncEngineProvider.notifier).sync()
                        : null,
                  ),
                  if (attention.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    const IosSectionHeader('Needs Your Attention'),
                    _Group(children: [for (final i in attention) _ItemRow(item: i, online: online)]),
                  ],
                  if (waiting.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    const IosSectionHeader('Waiting'),
                    _Group(children: [for (final i in waiting) _ItemRow(item: i, online: online)]),
                  ],
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'These changes are kept on this phone and upload on their own when there is a connection. '
                      'Signing out keeps them; they upload the next time you sign in.',
                      style: TextStyle(color: context.colors.textTertiary, fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const IosIconTile(icon: Icons.cloud_done_rounded, color: Ios.green, size: 52),
              const SizedBox(height: 16),
              Text('Everything is uploaded',
                  style: TextStyle(color: context.colors.textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('Changes you make offline will wait here until you\'re back online.',
                  textAlign: TextAlign.center, style: TextStyle(color: context.colors.textTertiary, fontSize: 15)),
            ],
          ),
        ),
      );
}

class _StatusCard extends StatelessWidget {
  final bool online;
  final bool syncing;
  final int done;
  final int total;
  final int waiting;
  final VoidCallback? onUpload;

  const _StatusCard({
    required this.online,
    required this.syncing,
    required this.done,
    required this.total,
    required this.waiting,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (icon, color, title, detail) = !online
        ? (Icons.wifi_off_rounded, Ios.orange, 'Offline', 'Changes will upload when the phone reconnects.')
        : syncing
            ? (Icons.cloud_upload_rounded, Ios.blue, 'Uploading…', '$done of $total done')
            : waiting > 0
                ? (Icons.cloud_queue_rounded, Ios.blue, 'Ready to upload', 'Uploads automatically, or tap Upload Now.')
                : (Icons.cloud_done_rounded, Ios.green, 'Nothing waiting', 'Only items that need you are left.');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Ios.cell(context), borderRadius: BorderRadius.circular(Ios.sectionRadius)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IosIconTile(icon: icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: c.textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(detail, style: TextStyle(color: c.textTertiary, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
          if (syncing && total > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: done / total),
                duration: AppTheme.motionMedium,
                curve: AppTheme.motionCurve,
                builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 4, color: Ios.blue),
              ),
            ),
          ],
          if (online && !syncing && waiting > 0) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onUpload,
              icon: const Icon(Icons.cloud_upload_rounded, size: 18),
              label: const Text('Upload Now'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: Ios.cell(context), borderRadius: BorderRadius.circular(Ios.sectionRadius)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, indent: 58, color: Ios.separator(context)),
              children[i],
            ],
          ],
        ),
      );
}

class _ItemRow extends ConsumerWidget {
  final OutboxItem item;
  final bool online;
  const _ItemRow({required this.item, required this.online});

  static (IconData, Color) _look(OutboxItem i) => switch (i.kind.split('.').first) {
        'asset' => (Icons.inventory_2_rounded, Ios.blue),
        'maintenance' => (Icons.build_rounded, Ios.orange),
        'disposal' => (Icons.delete_sweep_rounded, Ios.red),
        'transfer' => (Icons.swap_horiz_rounded, Ios.indigo),
        'photo' => (Icons.photo_camera_rounded, Ios.teal),
        _ => (Icons.edit_rounded, Ios.gray),
      };

  static String _ago(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final (icon, color) = _look(item);
    final engine = ref.read(syncEngineProvider.notifier);
    final waitsOnOther = !item.needsAttention && RegExp(r'/-\d+(/|$)').hasMatch(item.path);

    final (statusText, statusColor) = switch (item.status) {
      OutboxStatus.needsCode => ('Not sent yet.', Ios.orange),
      OutboxStatus.conflict => (item.error ?? 'Changed on the server.', Ios.orange),
      OutboxStatus.failed => (item.error ?? 'The server refused this change.', Ios.red),
      OutboxStatus.pending => (
          waitsOnOther ? 'Uploads after the new record it belongs to.' : 'Saved ${_ago(item.createdAt)}',
          c.textTertiary
        ),
    };

    final actions = <Widget>[
      if (item.status == OutboxStatus.needsCode) _action('Try Again', online ? () => engine.retry(item) : null),
      if (item.status == OutboxStatus.conflict) _action('Review', () => _showConflict(context, ref)),
      if (item.status == OutboxStatus.failed) _action('Try Again', online ? () => engine.retry(item) : null),
      _action('Discard', () => _confirmDiscard(context, ref), destructive: true),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IosIconTile(icon: icon, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(statusText, style: TextStyle(color: statusColor, fontSize: 14, height: 1.3)),
                const SizedBox(height: 4),
                Wrap(spacing: 4, children: actions),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(String label, VoidCallback? onTap, {bool destructive = false}) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: destructive ? Ios.red : Ios.blue,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 15, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      );

  Future<void> _confirmDiscard(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this change?'),
        content: Text('"${item.label}" will be removed from this phone and never uploaded.'),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(syncEngineProvider.notifier).discard(item);
  }

  void _showConflict(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ConflictSheet(item: item, online: online),
    );
  }
}

/// Side by side: what this phone will upload vs. what the server has now, for the fields that
/// differ. The user keeps theirs (overwrites the server) or the server's (drops theirs).
class _ConflictSheet extends ConsumerWidget {
  final OutboxItem item;
  final bool online;
  const _ConflictSheet({required this.item, required this.online});

  // `categoryId` in a request is `category.id` (and its name) in the server's copy.
  static const _nested = {
    'categoryId': ('category', 'categoryName'),
    'officeId': ('office', 'officeName'),
    'personnelId': ('accountablePerson', 'fullName'),
    'currentUserId': ('currentUser', 'fullName'),
    'assetId': ('asset', 'propertyNumber'),
  };

  static String _label(String key) {
    final base = key.endsWith('Id') && key != 'assetId' ? key.substring(0, key.length - 2) : key;
    final words = base.replaceAllMapped(RegExp(r'[A-Z]'), (m) => ' ${m[0]!.toLowerCase()}');
    return words[0].toUpperCase() + words.substring(1);
  }

  static String _show(Object? v) => v == null || '$v'.isEmpty ? 'N/A' : '$v';

  List<(String, String, String)> _differences() {
    final mine = item.body ?? const {};
    final server = item.serverCopy ?? const {};
    final preview = item.preview ?? const {};
    final out = <(String, String, String)>[];
    for (final key in mine.keys) {
      final nested = _nested[key];
      Object? serverValue, mineShown, serverShown;
      if (nested != null) {
        final obj = server[nested.$1];
        serverValue = obj is Map ? obj['id'] : null;
        serverShown = obj is Map ? obj[nested.$2] : null;
        final p = preview[nested.$1];
        mineShown = p is Map ? p[nested.$2] : mine[key];
      } else {
        serverValue = server[key];
        serverShown = serverValue;
        mineShown = mine[key];
      }
      final same = '${mine[key] ?? ''}' == '${serverValue ?? ''}' ||
          (mine[key] is num && serverValue is num && (mine[key] as num) == serverValue);
      if (!same) out.add((_label(key), _show(mineShown), _show(serverShown)));
    }
    return out;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final diffs = _differences();
    final engine = ref.read(syncEngineProvider.notifier);
    final modifiedBy = item.serverCopy?['updatedAt'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(item.label, style: TextStyle(color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Someone changed this record on the server${modifiedBy != null ? ' (${_ItemRow._ago('$modifiedBy')})' : ''} '
            'after you opened it on this phone. Choose which version to keep.',
            style: TextStyle(color: c.textSecondary, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: diffs.isEmpty
                ? Text('The fields you edited match the server, keeping yours changes nothing else.',
                    style: TextStyle(color: c.textTertiary, fontSize: 14))
                : SingleChildScrollView(
                    child: Table(
                      columnWidths: const {0: FlexColumnWidth(1.1), 1: FlexColumnWidth(1.4), 2: FlexColumnWidth(1.4)},
                      defaultVerticalAlignment: TableCellVerticalAlignment.top,
                      children: [
                        TableRow(children: [
                          _cell(context, '', header: true),
                          _cell(context, 'This phone', header: true),
                          _cell(context, 'Server', header: true),
                        ]),
                        for (final (label, mine, server) in diffs)
                          TableRow(
                            decoration: BoxDecoration(border: Border(top: BorderSide(color: Ios.separator(context)))),
                            children: [
                              _cell(context, label, muted: true),
                              _cell(context, mine),
                              _cell(context, server),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: online
                ? () {
                    Navigator.pop(context);
                    engine.keepMine(item);
                  }
                : null,
            child: Text(online ? 'Keep Mine' : 'Keep Mine (needs a connection)'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              engine.discard(item);
            },
            child: const Text("Use the Server's"),
          ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, String text, {bool header = false, bool muted = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: header ? 13 : 14,
            fontWeight: header ? FontWeight.w600 : FontWeight.normal,
            color: header || muted ? context.colors.textTertiary : context.colors.textPrimary,
          ),
        ),
      );
}
