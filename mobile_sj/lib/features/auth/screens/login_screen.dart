import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/auth_service.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/connectivity/connectivity_provider.dart';
import '../provider/auth_provider.dart';
import 'force_change_password_screen.dart';
import 'two_factor_screen.dart';
import 'connection_settings_screen.dart';
import '../../../core/router/page_transitions.dart';
import '../../../core/theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  String? _error;   // shown in a red box above the fields, like the web sign-in page
  bool _serverWaking = false;
  Future<bool>? _serverReady;

  @override
  void initState() {
    super.initState();
    _wake();
    // Sent here because the session ended mid-use — say so once, rather than a blank sign-in.
    final notice = ref.read(sessionExpiredNoticeProvider);
    if (notice != null) {
      _error = notice;
      Future.microtask(() => ref.read(sessionExpiredNoticeProvider.notifier).state = null);
    }
  }

  Future<bool> _wake() {
    return _serverReady = ApiClient.instance.waitForServer(onWaiting: () {
      if (mounted) setState(() => _serverWaking = true);
    }).whenComplete(() {
      if (mounted) setState(() => _serverWaking = false);
    });
  }

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    final identifier = _identifierCtrl.text.trim();
    final password = _passwordCtrl.text;
    // No network at all: check the password on the phone instead of waiting for the server.
    if (ApiClient.instance.deviceOffline) return _signInOffline(identifier, password);
    await _serverReady;
    await ref.read(authProvider.notifier).login(identifier, password);
    if (!mounted) return;
    var error = ref.read(authProvider).error;
    // went to sleep again or was mid-restart — wait for it once more, then retry
    if (error is ApiException && error.serverAsleep) {
      if (await _wake() && mounted) {
        await ref.read(authProvider.notifier).login(identifier, password);
        if (!mounted) return;
        error = ref.read(authProvider).error;
      }
    }
    // Connected, but the server still can't be reached (e.g. Wi-Fi with no internet).
    if (error is ApiException && error.serverAsleep) return _signInOffline(identifier, password);
    if (error is MustChangePasswordRequired) {
      // Not a real auth failure — clear it so it isn't mistaken for one, then
      // hand off to the password-change step.
      ref.read(authProvider.notifier).clearError();
      await Navigator.of(context).push(fadeThroughRoute(
        ForceChangePasswordScreen(
          identifier: identifier,
          currentPassword: password,
        ),
      ));
      return;
    }
    if (error is RequiresTwoFactor) {
      ref.read(authProvider.notifier).clearError();
      await Navigator.of(context).push(fadeThroughRoute(
        TwoFactorScreen(
          identifier: identifier,
          password: password,
        ),
      ));
      return;
    }
    if (error != null) setState(() => _error = _describe(error.toString()));
  }

  Future<void> _signInOffline(String identifier, String password) async {
    await ref.read(authProvider.notifier).loginOffline(identifier, password);
    if (!mounted) return;
    final error = ref.read(authProvider).error;
    if (error != null) {
      ref.read(authProvider.notifier).clearError();
      setState(() => _error = error.toString());
    }
  }

  // The backend's wording is terse — say it in plain words, as the web sign-in page does.
  String _describe(String msg) {
    if (RegExp(r'invalid (credentials|email or password|username or password)|bad credentials', caseSensitive: false)
        .hasMatch(msg)) {
      return 'The username or password is incorrect. Please check and try again.';
    }
    return msg;
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authProvider).isLoading;
    final offline = ref.watch(isOnlineProvider).valueOrNull == false;
    final c = context.colors;
    final errorFg = context.isLight ? const Color(0xFFB91C1C) : const Color(0xFFFCA5A5);

    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Philippine flag stripe, as on the web sign-in page and official government sites
            const SizedBox(
              height: 6,
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: ColoredBox(color: Color(0xFF0038A8))),
                Expanded(child: ColoredBox(color: Color(0xFFCE1126))),
                Expanded(child: ColoredBox(color: Color(0xFFFCD116))),
              ]),
            ),
            // Server address picker: debug builds only (pointing the app at a local backend).
            if (kDebugMode)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, right: 4),
                  child: TextButton.icon(
                    icon: const Icon(Icons.settings_ethernet_rounded, size: 20),
                    label: const Text('Connection'),
                    style: TextButton.styleFrom(foregroundColor: c.textSecondary),
                    onPressed: () => Navigator.of(context).push(fadeThroughRoute(const ConnectionSettingsScreen())),
                  ),
                ),
              )
            else
              const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Form(
                      key: _formKey,
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Seal, office and system name — the web login's side panel, stacked
                            Center(
                              child: Container(
                                width: 88,
                                height: 88,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: c.border),
                                ),
                                child: ClipOval(
                                  child: Image.asset('assets/images/images.png', fit: BoxFit.cover),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'SAN JOSE MUNICIPAL HALL',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.6,
                                color: context.brandAccent,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'GSO Inventory Management System',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 22, height: 1.25, fontWeight: FontWeight.w800, color: c.heading),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Batangas · Republic of the Philippines',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, color: c.textTertiary),
                            ),
                            const SizedBox(height: 24),
                            const Divider(),
                            const SizedBox(height: 24),

                            Text('Sign in', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: c.heading)),
                            const SizedBox(height: 4),
                            Text(
                              'Enter the username and password given to you by the system administrator.',
                              style: TextStyle(fontSize: 15, height: 1.45, color: c.textSecondary),
                            ),
                            const SizedBox(height: 20),

                            // Offline, the server isn't "starting up" — the phone just can't reach it.
                            if (_serverWaking && _error == null && !offline) ...[
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppTheme.statusMaintenance.withValues(alpha: context.isLight ? 0.10 : 0.16),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.statusMaintenance.withValues(alpha: 0.4)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(
                                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'The system is starting up after a quiet period. This can take up to 3 minutes. '
                                        'You can enter your username and password now — you will be signed in as soon as it is ready.',
                                        style: TextStyle(
                                          fontSize: 15,
                                          height: 1.4,
                                          color: context.isLight ? const Color(0xFF92400E) : const Color(0xFFFBBF24),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (_error != null) ...[
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: context.isLight ? const Color(0xFFFEF2F2) : const Color(0x33EF4444),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: context.isLight ? const Color(0xFFFECACA) : const Color(0x66EF4444)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.error_rounded, size: 20, color: errorFg),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(_error!, style: TextStyle(fontSize: 15, height: 1.4, color: errorFg)),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            const _FieldLabel('Username'),
                            TextFormField(
                              controller: _identifierCtrl,
                              decoration: const InputDecoration(
                                hintText: 'Enter your username',
                                prefixIcon: Icon(Icons.person_rounded),
                              ),
                              style: const TextStyle(fontSize: 16),
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.username, AutofillHints.email],
                              validator: (v) => v == null || v.trim().isEmpty ? 'Enter your username.' : null,
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                const Expanded(child: _FieldLabel('Password')),
                                TextButton(
                                  onPressed: () => context.push('/forgot-password'),
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(0, 36),
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                  ),
                                  child: const Text('Forgot password?'),
                                ),
                              ],
                            ),
                            TextFormField(
                              controller: _passwordCtrl,
                              obscureText: _obscure,
                              decoration: InputDecoration(
                                hintText: 'Enter your password',
                                prefixIcon: const Icon(Icons.lock_rounded),
                                // a worded toggle, as on the web form — clearer than an eye icon
                                suffixIcon: TextButton(
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                  style: TextButton.styleFrom(foregroundColor: c.textSecondary),
                                  child: Text(_obscure ? 'Show' : 'Hide'),
                                ),
                              ),
                              style: const TextStyle(fontSize: 16),
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              onFieldSubmitted: (_) => _submit(),
                              validator: (v) => v == null || v.isEmpty ? 'Enter your password.' : null,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: isLoading ? null : _submit,
                              child: isLoading
                                  ? const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        ),
                                        SizedBox(width: 10),
                                        Text('Signing in…'),
                                      ],
                                    )
                                  : const Text('Sign In'),
                            ),
                            const SizedBox(height: 24),
                            const Divider(),
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.lock_rounded, size: 18, color: c.textTertiary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'For authorized San Jose Municipal Hall personnel only. Sign-ins and activity '
                                    'in this system are recorded. For access issues, contact the ICT Administrator.',
                                    style: TextStyle(fontSize: 14, height: 1.45, color: c.textTertiary),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A form label above its field, as on the web app (instead of a floating label inside it).
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: context.colors.textSecondary),
        ),
      );
}
