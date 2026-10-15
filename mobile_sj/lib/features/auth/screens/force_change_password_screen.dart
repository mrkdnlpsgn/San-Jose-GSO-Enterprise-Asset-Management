import 'package:flutter/material.dart';
import '../../../shared/widgets/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/password_requirements.dart';
import '../provider/auth_provider.dart';

// Shown in place of the login screen when the backend reports mustChangePassword —
// a fresh account or an admin-mediated reset. Re-collects the temp password (never
// persisted client-side) alongside a new one, then exchanges both for a real
// session via /auth/force-change-password. Mirrors the web app's ForceChangePasswordForm.
class ForceChangePasswordScreen extends ConsumerStatefulWidget {
  final String identifier;
  final String currentPassword;

  const ForceChangePasswordScreen({
    super.key,
    required this.identifier,
    required this.currentPassword,
  });

  @override
  ConsumerState<ForceChangePasswordScreen> createState() => _ForceChangePasswordScreenState();
}

class _ForceChangePasswordScreenState extends ConsumerState<ForceChangePasswordScreen> {
  final _newPasswordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _newPasswordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!passwordMeetsRequirements(_newPasswordCtrl.text)) {
      setState(() => _error = 'New password does not meet the requirements below.');
      return;
    }
    if (_newPasswordCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(authProvider.notifier).completeForceChangePassword(
            widget.identifier,
            widget.currentPassword,
            _newPasswordCtrl.text,
          );
      if (!mounted) return;
      final error = ref.read(authProvider).error;
      if (error != null) {
        setState(() => _error = error is ApiException ? error.message : 'Failed to change password. Please try again.');
        return;
      }
      // authProvider now holds the logged-in user — pop back so go_router's
      // redirect (listening to authProvider) takes it from here to the dashboard.
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set a New Password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'This account is using a temporary password. Choose a new one to continue.',
                    style: TextStyle(color: context.colors.textSecondary, fontSize: 15, height: 1.45),
                  ),
                  const SizedBox(height: 24),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Callout(_error!, tone: CalloutTone.error),
                    ),
                  TextFormField(
                    controller: _newPasswordCtrl,
                    autofocus: true,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newPassword],
                    onChanged: (_) => setState(() {}),
                  ),
                  PasswordRequirementsList(password: _newPasswordCtrl.text),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmCtrl,
                    obscureText: _obscure,
                    decoration: const InputDecoration(labelText: 'Confirm New Password'),
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.newPassword],
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Set Password & Sign In'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
