import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

// Maintenance / disposal records a STAFF account adds are requests: they wait for an
// admin to approve (then staff can edit them) or reject them with a reason — mirrors
// web's ApprovalControls.
class ApprovalBanner extends StatelessWidget {
  final String? approvalStatus;
  final String? requestedByName;
  final String? reviewNote;

  const ApprovalBanner({super.key, this.approvalStatus, this.requestedByName, this.reviewNote});

  @override
  Widget build(BuildContext context) {
    final pending = approvalStatus == 'PENDING_APPROVAL';
    if (!pending && approvalStatus != 'REJECTED') return const SizedBox.shrink();
    final color = pending ? AppTheme.statusMaintenance : AppTheme.statusDisposed;
    final title = pending ? 'Awaiting admin approval' : 'Request rejected';
    final detail = pending
        ? '${requestedByName != null ? 'Requested by $requestedByName. ' : ''}'
            'It can be edited once an administrator approves it.'
        : (reviewNote != null && reviewNote!.isNotEmpty ? 'Reason: $reviewNote' : null);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(pending ? Icons.hourglass_top_rounded : Icons.block_rounded, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(detail, style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Approve / Reject for an admin looking at a pending staff request — mirrors web's
// ApprovalActions. Reject asks for a reason, which the requester sees.
class ApprovalActionsBar extends StatefulWidget {
  final Future<void> Function() onApprove;
  final Future<void> Function(String note) onReject;

  const ApprovalActionsBar({super.key, required this.onApprove, required this.onReject});

  @override
  State<ApprovalActionsBar> createState() => _ApprovalActionsBarState();
}

class _ApprovalActionsBarState extends State<ApprovalActionsBar> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade800, behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final note = await showDialog<String>(context: context, builder: (_) => const _RejectReasonDialog());
    if (note != null) await _run(() => widget.onReject(note));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _reject,
                style: OutlinedButton.styleFrom(foregroundColor: AppTheme.statusDisposed),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Reject'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : () => _run(widget.onApprove),
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_rounded, size: 18),
                label: const Text('Approve'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RejectReasonDialog extends StatefulWidget {
  const _RejectReasonDialog();

  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.colors.surface,
      title: Text('Reject request?', style: TextStyle(color: context.colors.textPrimary)),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLines: 3,
        maxLength: 255,
        decoration: InputDecoration(
          labelText: 'Reason',
          hintText: 'e.g. Duplicate of an existing record',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: context.colors.textTertiary)),
        ),
        TextButton(
          onPressed: () {
            final note = _ctrl.text.trim();
            if (note.isEmpty) {
              setState(() => _error = 'Give a reason so the requester knows what to fix.');
              return;
            }
            Navigator.pop(context, note);
          },
          child: const Text('Reject Request', style: TextStyle(color: AppTheme.statusDisposed)),
        ),
      ],
    );
  }
}
