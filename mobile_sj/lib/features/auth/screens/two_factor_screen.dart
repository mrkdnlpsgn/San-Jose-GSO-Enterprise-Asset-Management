import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../provider/auth_provider.dart';

// Shown in place of the login screen when the backend reports requiresTwoFactor —
// correct credentials, but this account needs the emailed code before a session
// is issued. Mirrors the web app's TwoFactorForm.
class TwoFactorScreen extends ConsumerStatefulWidget {
  final String identifier;
  final String password;

  const TwoFactorScreen({
    super.key,
    required this.identifier,
    required this.password,
  });

  @override
  ConsumerState<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends ConsumerState<TwoFactorScreen> {
  final _otpCtrl = TextEditingController();
  bool _loading = false;
  bool _resending = false;
  bool _resent = false;
  String? _error;

  @override
  void dispose() {
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final otp = _otpCtrl.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      setState(() => _error = 'Enter the 6-digit code from your email.');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(authProvider.notifier).completeLoginOtp(widget.identifier, otp);
      if (!mounted) return;
      final error = ref.read(authProvider).error;
      if (error != null) {
        setState(() => _error = error is ApiException ? error.message : 'Invalid or expired code. Please try again.');
        return;
      }
      // authProvider now holds the logged-in user — pop back so go_router's
      // redirect (listening to authProvider) takes it from here to the dashboard.
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _resent = false;
    });
    try {
      await ref.read(authProvider.notifier).resendLoginOtp(widget.identifier, widget.password);
    } finally {
      if (mounted) setState(() { _resending = false; _resent = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enter Verification Code')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text.rich(
                    TextSpan(
                      style: TextStyle(color: context.colors.textSecondary, fontSize: 14),
                      children: [
                        const TextSpan(text: 'We emailed a 6-digit code to the address on file for '),
                        TextSpan(
                          text: widget.identifier,
                          style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_error != null)
                    Padding(
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
                    ),
                  TextFormField(
                    controller: _otpCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 22, letterSpacing: 8),
                    decoration: const InputDecoration(
                      labelText: 'Verification code',
                      counterText: '',
                      hintText: '000000',
                    ),
                    onChanged: (v) {
                      final digits = v.replaceAll(RegExp(r'\D'), '');
                      if (digits != v) {
                        _otpCtrl.value = TextEditingValue(
                          text: digits,
                          selection: TextSelection.collapsed(offset: digits.length),
                        );
                      }
                      setState(() => _error = null);
                    },
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 4),
                  Text("Code expires 10 minutes after it's sent.",
                      style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Verify & Sign In'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Back to sign in'),
                      ),
                      TextButton(
                        onPressed: _resending ? null : _resend,
                        child: Text(_resending ? 'Sending...' : _resent ? 'Code sent' : "Didn't get it? Resend"),
                      ),
                    ],
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
