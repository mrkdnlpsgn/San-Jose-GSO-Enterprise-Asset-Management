import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../../core/theme/app_theme.dart';

Future<String?> showDeleteDialog(BuildContext context, {bool requireReason = true}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _DeleteDialog(requireReason: requireReason),
  );
}

class _DeleteDialog extends StatefulWidget {
  final bool requireReason;
  const _DeleteDialog({required this.requireReason});

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete this record?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // records that ask for a reason go to the Recycle Bin; reference data (offices, categories) doesn't
          Text(
              widget.requireReason
                  ? 'It moves to the Recycle Bin, where an administrator can restore it.'
                  : 'This cannot be undone.',
              style: TextStyle(color: context.colors.textSecondary, fontSize: 15, height: 1.45)),
          if (widget.requireReason) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              maxLines: 2,
              style: const TextStyle(fontSize: 16),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Reason for deletion (required)',
                hintText: 'e.g. Entered twice by mistake',
              ),
            ),
          ],
        ],
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
          // disabled until a reason is typed, instead of silently ignoring the tap
          onPressed: widget.requireReason && _ctrl.text.trim().isEmpty ? null : () {
            HapticFeedback.mediumImpact();
            Navigator.pop(context, widget.requireReason ? _ctrl.text.trim() : 'deleted');
          },
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
