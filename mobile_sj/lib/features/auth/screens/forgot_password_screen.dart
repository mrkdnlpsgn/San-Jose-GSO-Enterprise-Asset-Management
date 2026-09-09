import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/widgets/password_requirements.dart';
import '../data/auth_service.dart';

enum _Step { request, confirm, done }

// 3-step flow: request (enter username, email a code) -> confirm (enter code + new
// password) -> done. Requiring the emailed code — not just the username — is what
// stops anyone who merely knows/guesses a username from taking over the account.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  _Step _step = _Step.request;
  String? _error;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _otpCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await AuthService().requestPasswordReset(_usernameCtrl.text.trim());
      if (mounted) setState(() => _step = _Step.confirm);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitConfirm() async {
    setState(() => _error = null);
    if (_otpCtrl.text.trim().length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your email.');
      return;
    }
    if (!passwordMeetsRequirements(_passwordCtrl.text)) {
      setState(() => _error = 'New password does not meet the requirements below.');
      return;
    }
    if (_passwordCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthService().confirmPasswordReset(
        _usernameCtrl.text.trim(), _otpCtrl.text.trim(), _passwordCtrl.text);
      if (mounted) setState(() => _step = _Step.done);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: switch (_step) {
                _Step.request => _buildRequestForm(context),
                _Step.confirm => _buildConfirmForm(context),
                _Step.done => _buildDone(context),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorBanner(BuildContext context) {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
      ),
    );
  }

  Widget _buildRequestForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Enter your username and we'll email you a verification code.",
            style: TextStyle(color: context.colors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 24),
          _errorBanner(context),
          TextFormField(
            controller: _usernameCtrl,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submitRequest(),
            validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          Text(
            'You can only request a new code once every 15 minutes per account.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.textTertiary, fontSize: 12),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loading ? null : _submitRequest,
            child: _loading
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Send Verification Code'),
          ),
        ],
      ),
    );
  }

  bool get _otpComplete => _otpCtrl.text.trim().length == 6;

  Widget _buildConfirmForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter the code sent to the email on file for "${_usernameCtrl.text.trim()}".',
          style: TextStyle(color: context.colors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 24),
        _errorBanner(context),
        TextFormField(
          controller: _otpCtrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: 'monospace', letterSpacing: 8, fontSize: 20),
          decoration: const InputDecoration(labelText: 'Verification Code', counterText: ''),
          onChanged: (v) {
            final digitsOnly = v.replaceAll(RegExp(r'\D'), '');
            if (digitsOnly != v) {
              _otpCtrl.value = TextEditingValue(text: digitsOnly);
            }
            setState(() {});
          },
        ),
        AnimatedSize(
          duration: AppTheme.motionFast,
          curve: AppTheme.motionCurve,
          alignment: Alignment.topCenter,
          child: _otpComplete
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordCtrl,
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
                      onChanged: (_) => setState(() {}),
                    ),
                    PasswordRequirementsList(password: _passwordCtrl.text),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmCtrl,
                      obscureText: _obscure,
                      decoration: const InputDecoration(labelText: 'Confirm New Password'),
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submitConfirm(),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _loading ? null : _submitConfirm,
                      child: _loading
                          ? const SizedBox(
                              height: 20, width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Reset Password'),
                    ),
                  ],
                )
              : const SizedBox(height: 20),
        ),
        TextButton(
          onPressed: _loading
              ? null
              : () => setState(() {
                    _step = _Step.request;
                    _otpCtrl.clear();
                    _error = null;
                  }),
          child: const Text("Didn't get a code? Try a different username"),
        ),
      ],
    );
  }

  Widget _buildDone(BuildContext context) {
    // Deliberately not CrossAxisAlignment.stretch like the rest of this file's
    // Columns — that would also stretch the fixed-size 64x64 icon circle below
    // into a full-width bar. Only the button needs to be full width, via its
    // own SizedBox instead.
    return Column(
      children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(color: AppTheme.brand.withValues(alpha: 0.15), shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, color: AppTheme.brand, size: 32),
        ),
        const SizedBox(height: 20),
        Text('Password Reset',
            style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 16)),
        const SizedBox(height: 8),
        Text(
          'Your password has been updated. You can now sign in with your new password.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.colors.textTertiary, fontSize: 13),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to Sign In'),
          ),
        ),
      ],
    );
  }
}
