import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'ui.dart';

const _kResendCooldownSeconds = 60;

/// How the code prompt ended: the repeated request's [response], the [error] it failed with
/// (the code was fine but the change itself failed), or neither when the user cancelled.
class ActionOtpOutcome {
  final Response<dynamic>? response;
  final DioException? error;
  const ActionOtpOutcome({this.response, this.error});
}

/// Emailed code before a status change or a decision on a staff request (same as the web).
/// [send] repeats the original request with the code, or without one to get a new code emailed.
Future<ActionOtpOutcome> showActionOtpDialog(
  BuildContext context, {
  required String message,
  required Future<Response<dynamic>> Function(String? code) send,
}) async {
  final outcome = await showDialog<ActionOtpOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ActionOtpDialog(message: message, send: send),
  );
  return outcome ?? const ActionOtpOutcome();
}

class _ActionOtpDialog extends StatefulWidget {
  final String message;
  final Future<Response<dynamic>> Function(String? code) send;
  const _ActionOtpDialog({required this.message, required this.send});

  @override
  State<_ActionOtpDialog> createState() => _ActionOtpDialogState();
}

class _ActionOtpDialogState extends State<_ActionOtpDialog> {
  final _otpCtrl = TextEditingController();
  late String _message = widget.message;
  bool _busy = false;
  int _cooldown = 0;
  String? _error;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _otpCtrl.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _cooldown = _kResendCooldownSeconds);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        if (_cooldown <= 1) { _cooldown = 0; t.cancel(); } else { _cooldown--; }
      });
    });
  }

  static String? _messageOf(DioException e) {
    final data = e.response?.data;
    return data is Map && data['message'] != null ? data['message'].toString() : null;
  }

  Future<void> _confirm() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) { setState(() => _error = 'Enter the 6-digit code from your email.'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      final res = await widget.send(otp);
      if (mounted) Navigator.pop(context, ActionOtpOutcome(response: res));
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['code'] == 'ACTION_OTP_INVALID') {
        if (mounted) setState(() { _error = _messageOf(e) ?? 'Invalid or expired code.'; _busy = false; });
        return;
      }
      if (mounted) Navigator.pop(context, ActionOtpOutcome(error: e));
    }
  }

  // The same request without a code makes the server email a new one (answering 428 again).
  Future<void> _resend() async {
    setState(() => _error = null);
    try {
      await widget.send(null);
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 428) {
        setState(() => _message = _messageOf(e) ?? _message);
        _startCooldown();
      } else {
        setState(() => _error = _messageOf(e) ?? 'Could not send a new code.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final digits = _otpCtrl.text.trim().length;
    return AlertDialog(
      title: const Text('Confirm with your code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_message, style: TextStyle(color: context.colors.textSecondary, fontSize: 15, height: 1.45)),
          const SizedBox(height: 14),
          TextField(
            controller: _otpCtrl,
            autofocus: true,
            maxLength: 6,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            textAlign: TextAlign.center,
            style: const TextStyle(letterSpacing: 8, fontSize: 22, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(counterText: '', hintText: '••••••'),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _confirm(),
          ),
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: (_cooldown > 0 || _busy) ? null : _resend,
              child: Text(_cooldown > 0 ? 'Resend code in ${_cooldown}s' : 'Resend code'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Callout(_error!, tone: CalloutTone.error),
          ],
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: _busy ? null : () => Navigator.pop(context, const ActionOtpOutcome()),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_busy || digits != 6) ? null : _confirm,
          child: Text(_busy ? 'Confirming…' : 'Confirm'),
        ),
      ],
    );
  }
}
