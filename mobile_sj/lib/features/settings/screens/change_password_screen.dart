import 'package:flutter/material.dart';
import '../../../shared/widgets/ui.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/widgets/password_requirements.dart';
import '../../../shared/widgets/main_shell.dart';
import '../../accounts/data/account_service.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (!passwordMeetsRequirements(_newCtrl.text)) {
      setState(() => _error = 'New password does not meet the requirements below.');
      return;
    }
    if (_newCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'New passwords do not match.');
      return;
    }
    setState(() => _loading = true);
    try {
      await AccountService().changePassword(_currentCtrl.text, _newCtrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated successfully.'), behavior: SnackBarBehavior.floating),
      );
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change Password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + context.mainShellBottomInset),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  Callout(_error!, tone: CalloutTone.error),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _currentCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _newCtrl,
                  obscureText: _obscure,
                  decoration: const InputDecoration(
                    labelText: 'New Password',
                    prefixIcon: Icon(Icons.lock_reset_rounded),
                  ),
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                PasswordRequirementsList(password: _newCtrl.text),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: _obscure,
                  decoration: const InputDecoration(
                    labelText: 'Confirm New Password',
                    prefixIcon: Icon(Icons.lock_reset_rounded),
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Update Password'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
