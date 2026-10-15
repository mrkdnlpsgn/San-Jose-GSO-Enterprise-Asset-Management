import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'ui.dart';

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
    final detail = pending
        ? '${requestedByName != null ? 'Requested by $requestedByName. ' : ''}'
            'It can be edited once an administrator approves it.'
        : (reviewNote != null && reviewNote!.isNotEmpty ? 'Reason: $reviewNote' : 'No reason was given.');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Callout(
        detail,
        title: pending ? 'Awaiting admin approval' : 'Request rejected',
        tone: pending ? CalloutTone.warning : CalloutTone.error,
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
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade800),
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
    return FormActionBar(
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _reject,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                side: const BorderSide(color: Color(0xFFFCA5A5)),
                minimumSize: const Size.fromHeight(50),
              ),
              icon: const Icon(Icons.close_rounded, size: 20),
              label: const Text('Reject'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _busy ? null : () => _run(widget.onApprove),
              icon: _busy
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded, size: 20),
              label: const Text('Approve'),
            ),
          ),
        ],
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
      title: const Text('Reject request?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('The person who sent it will see your reason.',
              style: TextStyle(color: context.colors.textSecondary, fontSize: 15)),
          const SizedBox(height: 14),
          const FieldLabel('Reason', required: true),
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLines: 3,
            maxLength: 255,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: 'e.g. Duplicate of an existing record',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
          onPressed: () {
            final note = _ctrl.text.trim();
            if (note.isEmpty) {
              setState(() => _error = 'Give a reason so the requester knows what to fix.');
              return;
            }
            Navigator.pop(context, note);
          },
          child: const Text('Reject'),
        ),
      ],
    );
  }
}
