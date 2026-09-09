import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/widgets/logout_dialog.dart';
import '../../auth/provider/auth_provider.dart';

const _summaryPoints = [
  (
    'What this system collects',
    'Asset records, accountable-person names, your account activity, and audit-trail details (including IP '
        'address and timestamps) for every action taken in the system.',
  ),
  (
    'Why we collect it',
    'Republic Act No. 10173 (Data Privacy Act of 2012) requires you be informed of this, since you are both a '
        'data subject — your own account and activity are logged — and, in daily use, a handler of other '
        'people\'s data (accountable persons, other staff).',
  ),
  (
    'Your responsibilities',
    'Enter only accurate information, never share your login credentials, and report any suspected data breach '
        'or misuse to the ICT Division immediately.',
  ),
  (
    'Retention',
    'Records are retained in accordance with Commission on Audit (COA) rules on government property and '
        'accountability records.',
  ),
];

// Real route (not an overlay) that AppRouter's redirect sends every logged-in
// user to until they acknowledge — mobile equivalent of web's MainLayout +
// PrivacyAcknowledgmentModal. Back navigation is blocked; the router keeps
// bouncing them here until AuthNotifier.acknowledgePrivacy() succeeds.
class PrivacyAcknowledgmentScreen extends ConsumerStatefulWidget {
  const PrivacyAcknowledgmentScreen({super.key});

  @override
  ConsumerState<PrivacyAcknowledgmentScreen> createState() => _PrivacyAcknowledgmentScreenState();
}

class _PrivacyAcknowledgmentScreenState extends ConsumerState<PrivacyAcknowledgmentScreen> {
  final _scrollCtrl = ScrollController();
  bool _reachedBottom = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Covers the case where content actually needs scrolling (real drag
    // gestures reliably update ScrollController and fire this listener).
    _scrollCtrl.addListener(_checkBottom);
    // Neither a one-shot addPostFrameCallback nor ScrollMetricsNotification
    // reliably catches the "content already fits, nothing to scroll" case on
    // this Flutter version — both raced or silently no-op'd on some
    // logins/devices, leaving the button stuck disabled forever. Retrying every
    // frame until ScrollController actually attaches removes the race: it's
    // cheap, stops the instant _reachedBottom flips true, and is guaranteed to
    // eventually run after a real attach instead of possibly running before one.
    _scheduleBottomCheck();
  }

  void _scheduleBottomCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _reachedBottom) return;
      if (_scrollCtrl.hasClients) _checkBottom();
      if (!_reachedBottom) _scheduleBottomCheck();
    });
  }

  void _checkBottom() {
    if (!_scrollCtrl.hasClients) return;
    final metrics = _scrollCtrl.position;
    final atBottom = metrics.maxScrollExtent <= 0 || metrics.pixels >= metrics.maxScrollExtent - 8;
    if (atBottom && !_reachedBottom) {
      setState(() => _reachedBottom = true);
    }
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_checkBottom);
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _acknowledge() async {
    setState(() => _loading = true);
    try {
      await ref.read(authProvider.notifier).acknowledgePrivacy();
      // On success the router's redirect (privacyAcknowledgedAt now set) takes
      // over and sends us to the dashboard automatically.
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade800, behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Privacy, Terms & Conditions'),
          actions: [
            TextButton.icon(
              onPressed: () async {
                final confirmed = await showLogoutDialog(context);
                if (confirmed == true) ref.read(authProvider.notifier).logout();
              },
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Log out'),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This is a private, internal government system for authorized GSO/ICT staff only. '
                      'Please review before continuing.',
                      style: TextStyle(fontSize: 12, color: context.colors.textSecondary, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  ..._summaryPoints.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 24, height: 24,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppTheme.brand.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Text('${_summaryPoints.indexOf(p) + 1}',
                                  style: const TextStyle(color: AppTheme.brand, fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.$1, style: TextStyle(color: context.colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 3),
                                  Text(p.$2, style: TextStyle(color: context.colors.textSecondary, fontSize: 13, height: 1.5)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )),
                  Padding(
                    padding: const EdgeInsets.only(left: 36),
                    child: InkWell(
                      onTap: () => context.push('/legal'),
                      child: const Text('Read the full Privacy, Terms & Conditions →',
                          style: TextStyle(color: AppTheme.brand, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: context.colors.border))),
              child: Row(
                children: [
                  if (!_reachedBottom)
                    Expanded(
                      child: Text('Scroll down to continue ↓',
                          style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
                    )
                  else
                    const Spacer(),
                  SizedBox(
                    height: 46,
                    child: ElevatedButton(
                      onPressed: (_reachedBottom && !_loading) ? _acknowledge : null,
                      // The app's global ElevatedButtonTheme only sets vertical padding
                      // (relying on full-width buttons elsewhere to be stretched by an
                      // outer SizedBox) — this button isn't stretched, so without its own
                      // horizontal padding the text touches the button's edges.
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20)),
                      child: _loading
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('I Understand and Acknowledge'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
