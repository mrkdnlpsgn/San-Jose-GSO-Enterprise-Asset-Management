import 'package:flutter/material.dart';
import '../../../shared/widgets/ui.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/password_requirements.dart';

/// Returns the new password on confirm, or null if cancelled.
Future<String?> showResetPasswordDialog(BuildContext context, {required String username}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _ResetPasswordDialog(username: username),
  );
}

class _ResetPasswordDialog extends StatefulWidget {
  final String username;
  const _ResetPasswordDialog({required this.username});

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!passwordMeetsRequirements(_passwordCtrl.text)) {
      setState(() => _error = 'Password does not meet the requirements below.');
      return;
    }
    if (_passwordCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    HapticFeedback.mediumImpact();
    Navigator.pop(context, _passwordCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset password'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Set a new password for ${widget.username}.',
                style: TextStyle(color: context.colors.textSecondary, fontSize: 15)),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Callout(_error!, tone: CalloutTone.error),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New Password'),
              onChanged: (_) => setState(() {}),
            ),
            PasswordRequirementsList(password: _passwordCtrl.text),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm New Password'),
            ),
            const SizedBox(height: 12),
            Text(
              'This also clears any failed login attempts and unlocks the account if it was locked.',
              style: TextStyle(color: context.colors.textTertiary, fontSize: 14),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Reset password')),
      ],
    );
  }
}
