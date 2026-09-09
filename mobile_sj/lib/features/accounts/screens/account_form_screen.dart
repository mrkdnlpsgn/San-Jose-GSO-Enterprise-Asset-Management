import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../model/account_model.dart';
import '../data/account_service.dart';
import '../../../shared/widgets/delete_dialog.dart';
import '../widgets/reset_password_dialog.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../auth/provider/auth_provider.dart';
import '../../../shared/utils/idempotency.dart';

class AccountFormScreen extends ConsumerStatefulWidget {
  final AccountModel? account; // null = create, non-null = edit
  const AccountFormScreen({super.key, this.account});

  @override
  ConsumerState<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends ConsumerState<AccountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  final String _idempotencyKey = newIdempotencyKey();

  late final TextEditingController _username;
  late final TextEditingController _email;
  late final TextEditingController _fullName;
  late final TextEditingController _password;

  String _role = 'STAFF';
  int? _officeId;
  bool _isActive = true;
  bool _generatePassword = false;

  bool get _isEdit => widget.account != null;

  static final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  bool get _emailValid => _emailRegex.hasMatch(_email.text.trim());

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    _username = TextEditingController(text: a?.username ?? '');
    _email = TextEditingController(text: a?.email ?? '');
    _fullName = TextEditingController(text: a?.fullName ?? '');
    _password = TextEditingController();
    _role = a?.role ?? 'STAFF';
    _officeId = a?.officeId;
    _isActive = a?.isActive ?? true;
  }

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _fullName.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final usingGenerated = !_isEdit && _generatePassword;
      final data = {
        'username': _username.text.trim(),
        'email': _email.text.trim(),
        'fullName': _fullName.text.trim(),
        'role': _role,
        'officeId': _officeId,
        'isActive': _isActive,
        if (usingGenerated) 'generatePassword': true,
        if (!usingGenerated && _password.text.trim().isNotEmpty) 'password': _password.text.trim(),
      };
      final service = AccountService();
      if (_isEdit) {
        await service.update(widget.account!.id, data);
      } else {
        await service.create(data, idempotencyKey: _idempotencyKey);
      }
      if (!mounted) return;
      if (usingGenerated) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: context.colors.surface,
            title: const Text('Account Created'),
            content: Text(
                'A temporary password was generated and emailed to ${_email.text.trim()}. '
                'The user must change it after logging in for the first time.',
                style: TextStyle(color: context.colors.textSecondary)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
            ],
          ),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleActive() async {
    final activating = !_isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.colors.surface,
        title: Text(activating ? 'Reactivate this account?' : 'Deactivate this account?',
            style: TextStyle(color: ctx.colors.textPrimary)),
        content: Text(
            activating
                ? '${widget.account!.fullName} will be able to log in again.'
                : '${widget.account!.fullName} will no longer be able to log in.',
            style: TextStyle(color: ctx.colors.textTertiary, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: ctx.colors.textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(activating ? 'Reactivate' : 'Deactivate',
                style: TextStyle(color: activating ? AppTheme.brand : Colors.orange)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    try {
      await AccountService().update(widget.account!.id, {
        'fullName': widget.account!.fullName,
        'role': widget.account!.role,
        'officeId': widget.account!.officeId,
        'isActive': activating,
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final newPassword = await showResetPasswordDialog(context, username: widget.account!.username);
    if (newPassword == null || !mounted) return;
    setState(() => _loading = true);
    try {
      await AccountService().resetPassword(widget.account!.id, newPassword);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset successfully.'), behavior: SnackBarBehavior.floating),
        );
      }
    } on ApiException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDeleteDialog(context, requireReason: false);
    if (confirm == null || !mounted) return;
    setState(() => _loading = true);
    try {
      await AccountService().delete(widget.account!.id);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSelf = _isEdit && widget.account!.username == ref.watch(authProvider).value?.username;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Account' : 'New Account'),
        actions: [
          if (_isEdit && !isSelf) ...[
            IconButton(
              icon: const Icon(Icons.key_rounded),
              tooltip: 'Reset Password',
              onPressed: _loading ? null : _resetPassword,
            ),
            IconButton(
              icon: Icon(_isActive ? Icons.block_rounded : Icons.check_circle_outline_rounded,
                  color: _isActive ? Colors.orange : AppTheme.brand),
              tooltip: _isActive ? 'Deactivate' : 'Reactivate',
              onPressed: _loading ? null : _toggleActive,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              tooltip: 'Delete',
              onPressed: _loading ? null : _delete,
            ),
          ],
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (isSelf)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.statusMaintenance.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.statusMaintenance.withValues(alpha: 0.3)),
                    ),
                    child: const Text(
                      "This is your own account — deactivate and delete are disabled here to prevent locking yourself out.",
                      style: TextStyle(color: AppTheme.statusMaintenance, fontSize: 12),
                    ),
                  ),
                ),
              _field(_username, 'Username', required: true, enabled: !_isEdit),
              _field(_email, 'Email',
                  hint: 'Needed for this user to use "Forgot password"',
                  validator: (v) {
                    final trimmed = v?.trim() ?? '';
                    if (trimmed.isEmpty) {
                      return _generatePassword ? 'Email is required to auto-generate and send a password.' : null;
                    }
                    return _emailRegex.hasMatch(trimmed) ? null : 'Enter a valid email address';
                  }),
              _field(_fullName, 'Full Name', required: true),
              if (!_isEdit)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: CheckboxListTile(
                    value: _generatePassword,
                    onChanged: (v) => setState(() => _generatePassword = v ?? false),
                    activeColor: AppTheme.brand,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text('Auto-generate a password and email it to the address above',
                        style: TextStyle(color: context.colors.textPrimary, fontSize: 13.5)),
                  ),
                ),
              if (_generatePassword)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.brand.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.brand.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    _emailValid
                        ? 'A temporary password will be generated and emailed to ${_email.text.trim()}. The user should change it after logging in.'
                        : 'Enter a valid email above to auto-generate and send a password.',
                    style: TextStyle(color: context.colors.textSecondary, fontSize: 12.5),
                  ),
                )
              else
                _field(_password, _isEdit ? 'New Password' : 'Password',
                    obscure: true,
                    hint: _isEdit
                        ? 'Leave blank to keep current password'
                        : '8+ chars, upper/lowercase, number, symbol',
                    validator: (v) {
                      final trimmed = v?.trim() ?? '';
                      if (trimmed.isEmpty) {
                        return _isEdit ? null : 'Password is required.';
                      }
                      return _passwordComplexityError(trimmed);
                    }),
              _dropdown<String>(
                label: 'Role',
                value: _role,
                items: const ['ADMIN', 'STAFF'],
                itemLabel: (r) => r,
                onChanged: (r) => setState(() => _role = r!),
              ),
              // No office field here at all — matches the web app's account form,
              // which has never had one. Office assignment isn't part of an
              // account's identity in this app.
              // No Active/Inactive control here — that's handled by the dedicated
              // Deactivate/Reactivate button in the AppBar (edit mode only). New
              // accounts are always created active.
              const SizedBox(height: 24),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_isEdit ? 'Save Changes' : 'Create Account'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
    );
  }

  // Mirrors backend StrongPasswordValidator.java exactly, so a weak manual
  // password gets caught here instead of surfacing as a raw 400 on submit.
  String? _passwordComplexityError(String password) {
    if (password.length < 8 || password.length > 128) return 'Must be 8-128 characters.';
    if (!RegExp(r'[A-Z]').hasMatch(password)) return 'Add an uppercase letter (A-Z).';
    if (!RegExp(r'[a-z]').hasMatch(password)) return 'Add a lowercase letter (a-z).';
    if (!RegExp(r'[0-9]').hasMatch(password)) return 'Add a number (0-9).';
    if (!RegExp(r'[@$!%*?&_#^\-]').hasMatch(password)) return 'Add a special character (@\$!%*?&_#^-).';
    return null;
  }

  Widget _field(TextEditingController ctrl, String label,
      {bool required = false, bool obscure = false, bool enabled = true, String? hint,
      String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: ctrl,
        obscureText: obscure,
        enabled: enabled,
        decoration: InputDecoration(labelText: label, hintText: hint),
        validator: validator ??
            (required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null),
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) itemLabel,
    required void Function(T?) onChanged,
    bool requireValue = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        dropdownColor: context.colors.surface,
        items: items.map((e) => DropdownMenuItem(
          value: e,
          child: Text(itemLabel(e), overflow: TextOverflow.ellipsis),
        )).toList(),
        onChanged: onChanged,
        validator: requireValue ? (v) => v == null ? 'Required' : null : null,
      ),
    );
  }
}
