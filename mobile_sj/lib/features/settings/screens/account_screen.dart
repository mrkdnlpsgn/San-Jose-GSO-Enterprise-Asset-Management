import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/logout_dialog.dart';
import '../../../shared/widgets/password_requirements.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/ui.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../accounts/data/account_service.dart';
import '../../auth/model/user_model.dart';
import '../../auth/provider/auth_provider.dart';
import '../data/my_account_service.dart';

const _danger = Color(0xFFDC2626);

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

// Server timestamps are UTC ("…Z"); show them in the phone's time zone.
String _fmtDate(String? raw) {
  final dt = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  if (dt == null) return '—';
  return '${_months[dt.month - 1]} ${dt.day}, ${dt.year}';
}

// "3 minutes ago", "yesterday", "2 weeks ago" — the date after a month, like the web.
String _timeAgo(String? raw) {
  final dt = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  if (dt == null) return '';
  final d = DateTime.now().difference(dt);
  String plural(int n, String unit) => '$n $unit${n == 1 ? '' : 's'} ago';
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return plural(d.inMinutes, 'minute');
  if (d.inHours < 24) return plural(d.inHours, 'hour');
  if (d.inDays == 1) return 'yesterday';
  if (d.inDays < 7) return plural(d.inDays, 'day');
  if (d.inDays < 30) return plural(d.inDays ~/ 7, 'week');
  return _fmtDate(raw);
}

const _actionLabels = {
  'USER_2FA_ENABLED': '2-step verification turned on',
  'USER_2FA_DISABLED': '2-step verification turned off',
  'PROFILE_PICTURE_CHANGED': 'Profile picture changed',
  'PROFILE_PICTURE_REMOVED': 'Profile picture removed',
  'AI_RECOMMENDATION_GENERATED': 'AI recommendation generated',
};

// ASSET_UPDATED -> "Asset updated"
String _actionLabel(String action) {
  final known = _actionLabels[action];
  if (known != null) return known;
  final s = action.toLowerCase().replaceAll('_', ' ');
  return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// My Account — mirrors the web's Accounts → My Account tab: profile picture, quick facts,
/// change password, account details, 2-step verification, recent activity, and sign out.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _service = MyAccountService();
  MyOverview? _overview;
  bool _overviewFailed = false;
  bool _avatarBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final o = await _service.overview();
      if (mounted) setState(() { _overview = o; _overviewFailed = false; });
    } catch (_) {
      if (mounted) setState(() => _overviewFailed = true);
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade800 : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _choosePicture() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    // Shrunk on the phone so it stays well under the server's 2 MB limit.
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.front,
    );
    if (picked == null) return;

    setState(() => _avatarBusy = true);
    try {
      final url = await _service.uploadAvatar(picked.path, picked.name);
      ref.read(authProvider.notifier).setAvatarUrl(url);
      _toast('Profile picture updated.');
      _load();
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _removePicture() async {
    setState(() => _avatarBusy = true);
    try {
      await _service.removeAvatar();
      ref.read(authProvider.notifier).setAvatarUrl(null);
      _toast('Profile picture removed.');
      _load();
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('My Account')),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (user != null)
                _IdentityCard(
                  user: user,
                  overview: _overview,
                  loading: _overview == null && !_overviewFailed,
                  avatarBusy: _avatarBusy,
                  onPickPicture: _choosePicture,
                  onRemovePicture: _removePicture,
                ),
              const SizedBox(height: 16),
              const _ChangePasswordCard(),
              const SizedBox(height: 16),
              if (user != null) _DetailsCard(user: user, overview: _overview, loading: _overview == null && !_overviewFailed),
              const SizedBox(height: 16),
              _TwoStepCard(
                overview: _overview,
                service: _service,
                onChanged: (enabled) => setState(() => _overview = _overview?.withTwoFactor(enabled)),
                onToast: _toast,
              ),
              const SizedBox(height: 16),
              _ActivityCard(overview: _overview, failed: _overviewFailed),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  foregroundColor: _danger,
                  side: const BorderSide(color: Color(0xFFFCA5A5)),
                ),
                onPressed: () async {
                  final confirmed = await showLogoutDialog(context);
                  if (confirmed == true) ref.read(authProvider.notifier).logout();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared bits ─────────────────────────────────────────────────────────────

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(padding: const EdgeInsets.all(18), child: child),
      );
}

class _PanelTitle extends StatelessWidget {
  final String text;
  const _PanelTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(color: context.colors.heading, fontSize: 17, fontWeight: FontWeight.w700),
      );
}

class _SmallCaps extends StatelessWidget {
  final String text;
  const _SmallCaps(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          color: context.colors.textTertiary,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      );
}

class _OnOff extends StatelessWidget {
  final bool on;
  const _OnOff(this.on);

  @override
  Widget build(BuildContext context) {
    final color = on ? AppTheme.brand : context.colors.textTertiary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(on ? 'On' : 'Off',
            style: TextStyle(
              color: on ? context.brandAccent : context.colors.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            )),
      ],
    );
  }
}

class _LinkButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  const _LinkButton(this.label, {this.onTap, this.color});

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: color ?? context.brandAccent,
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
          minimumSize: const Size(0, 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      );
}

// ── Identity ────────────────────────────────────────────────────────────────

class _IdentityCard extends StatelessWidget {
  final UserModel user;
  final MyOverview? overview;
  final bool loading;
  final bool avatarBusy;
  final VoidCallback onPickPicture;
  final VoidCallback onRemovePicture;

  const _IdentityCard({
    required this.user,
    required this.overview,
    required this.loading,
    required this.avatarBusy,
    required this.onPickPicture,
    required this.onRemovePicture,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasPicture = user.avatarUrl != null;
    final officeName = overview?.officeName ?? user.officeName;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                button: true,
                label: hasPicture ? 'Change profile picture' : 'Add profile picture',
                child: GestureDetector(
                  onTap: avatarBusy ? null : onPickPicture,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedOpacity(
                        duration: AppTheme.motionFast,
                        opacity: avatarBusy ? 0.5 : 1,
                        child: UserAvatar(user: user, size: 88),
                      ),
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.brandButton,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.surface, width: 3),
                          ),
                          child: avatarBusy
                              ? const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.photo_camera_rounded, size: 17, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.displayName,
                        style: TextStyle(color: c.heading, fontSize: 22, fontWeight: FontWeight.w800, height: 1.2)),
                    const SizedBox(height: 2),
                    CodeText('@${user.username}', size: 14),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        StatusBadge(
                          label: roleLabel(user.role),
                          color: user.isAdmin ? AppTheme.brand : AppTheme.info,
                        ),
                        if (officeName != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: c.subtle,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: c.border),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.apartment_rounded, size: 13, color: c.textSecondary),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(officeName,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 16,
                      children: [
                        _LinkButton(
                          avatarBusy ? 'Saving…' : hasPicture ? 'Change profile picture' : 'Add profile picture',
                          onTap: avatarBusy ? null : onPickPicture,
                        ),
                        if (hasPicture && !avatarBusy)
                          _LinkButton('Remove picture', onTap: onRemovePicture, color: c.textTertiary),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _FactTile(
                  label: 'Member since',
                  child: loading
                      ? const Shimmer(child: Bone(width: 110, height: 16))
                      : Text(_fmtDate(overview?.memberSince),
                          style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FactTile(
                  label: '2-step verification',
                  child: loading
                      ? const Shimmer(child: Bone(width: 40, height: 16))
                      : _OnOff(overview?.twoFactorEnabled ?? false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FactTile extends StatelessWidget {
  final String label;
  final Widget child;
  const _FactTile({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 84),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.subtle,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SmallCaps(label),
            const SizedBox(height: 6),
            child,
          ],
        ),
      );
}

// ── Change password ─────────────────────────────────────────────────────────

class _ChangePasswordCard extends ConsumerStatefulWidget {
  const _ChangePasswordCard();

  @override
  ConsumerState<_ChangePasswordCard> createState() => _ChangePasswordCardState();
}

class _ChangePasswordCardState extends ConsumerState<_ChangePasswordCard> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _showCurrent = false;
  bool _showNew = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _changed() => setState(() => _error = null);

  void _clear() {
    _current.clear();
    _new.clear();
    _confirm.clear();
    setState(() => _error = null);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!passwordMeetsRequirements(_new.text)) {
      setState(() => _error = 'The new password does not meet all the requirements yet.');
      return;
    }
    if (_new.text != _confirm.text) {
      setState(() => _error = 'The new passwords do not match.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await AccountService().changePassword(_current.text, _new.text);
      if (!mounted) return;
      // The change ends every session, this one included — sign out cleanly now
      // instead of letting the next request fail.
      final messenger = ScaffoldMessenger.of(context);
      await ref.read(authProvider.notifier).logout();
      messenger.showSnackBar(const SnackBar(
        content: Text('Password changed. Sign in with your new password.'),
        behavior: SnackBarBehavior.floating,
      ));
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _saving = false; });
    }
  }

  Widget _showHide(bool shown, VoidCallback onTap) => TextButton(
        onPressed: onTap,
        child: Text(shown ? 'Hide' : 'Show', style: const TextStyle(fontWeight: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pw = _new.text;
    final met = kPasswordRequirements.where((r) => r.test(pw)).length;
    final (String strengthLabel, Color strengthColor) = met >= 5
        ? ('Meets all requirements', AppTheme.brand)
        : met >= 3
            ? ('Almost there', AppTheme.statusMaintenance)
            : ('Too weak', _danger);
    final matches = _confirm.text.isNotEmpty && _confirm.text == pw;
    final anyText = _current.text.isNotEmpty || pw.isNotEmpty || _confirm.text.isNotEmpty;
    final canSubmit = !_saving && _current.text.isNotEmpty && pw.isNotEmpty && _confirm.text.isNotEmpty;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.brand.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.lock_rounded, color: context.brandAccent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _PanelTitle('Change password'),
                    const SizedBox(height: 4),
                    Text(
                      "Use a password you don't use anywhere else. Afterwards you'll be signed out on every "
                      'device and asked to sign in with the new one.',
                      style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_error != null) ...[
            Callout(_error!, tone: CalloutTone.error),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _current,
            obscureText: !_showCurrent,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.next,
            onChanged: (_) => _changed(),
            decoration: InputDecoration(
              labelText: 'Current password',
              suffixIcon: _showHide(_showCurrent, () => setState(() => _showCurrent = !_showCurrent)),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _new,
            obscureText: !_showNew,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.next,
            onChanged: (_) => _changed(),
            decoration: InputDecoration(
              labelText: 'New password',
              suffixIcon: _showHide(_showNew, () => setState(() => _showNew = !_showNew)),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirm,
            obscureText: !_showNew,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.done,
            onChanged: (_) => _changed(),
            onSubmitted: (_) { if (canSubmit) _submit(); },
            decoration: const InputDecoration(labelText: 'Confirm new password'),
          ),
          if (_confirm.text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(matches ? Icons.check_circle_rounded : Icons.circle_outlined,
                    size: 16, color: matches ? AppTheme.brand : c.textTertiary),
                const SizedBox(width: 6),
                Text(matches ? 'Passwords match' : "Doesn't match yet",
                    style: TextStyle(
                      color: matches ? context.brandAccent : c.textTertiary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
          ],
          const SizedBox(height: 16),
          // Requirements — always visible, so the rules are known before typing
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.subtle,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Password requirements',
                          style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                    if (pw.isNotEmpty)
                      Text(strengthLabel,
                          style: TextStyle(color: strengthColor, fontSize: 14, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (var i = 0; i < kPasswordRequirements.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(
                        child: AnimatedContainer(
                          duration: AppTheme.motionMedium,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i < met ? strengthColor : c.border,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                for (final r in kPasswordRequirements)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(r.test(pw) ? Icons.check_circle_rounded : Icons.circle_outlined,
                            size: 16, color: r.test(pw) ? AppTheme.brand : c.textTertiary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(r.label,
                              style: TextStyle(
                                color: r.test(pw) ? context.brandAccent : c.textSecondary,
                                fontSize: 14.5,
                              )),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: canSubmit ? _submit : null,
            child: _saving
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Update password'),
          ),
          if (anyText && !_saving)
            Align(
              alignment: Alignment.center,
              child: _LinkButton('Clear', onTap: _clear, color: c.textTertiary),
            ),
        ],
      ),
    );
  }
}

// ── Account details ─────────────────────────────────────────────────────────

class _DetailsCard extends StatelessWidget {
  final UserModel user;
  final MyOverview? overview;
  final bool loading;
  const _DetailsCard({required this.user, required this.overview, required this.loading});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final officeName = overview?.officeName ?? user.officeName;
    final valueStyle = TextStyle(color: c.textPrimary, fontSize: 16);

    Widget row(String label, Widget value, {bool last = false}) => Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: last ? null : Border(bottom: BorderSide(color: c.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [_SmallCaps(label), const SizedBox(height: 4), value],
          ),
        );

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle('Account details'),
          const SizedBox(height: 6),
          row('Full name', Text(user.displayName, style: valueStyle)),
          row('Username', Text(user.username, style: valueStyle.copyWith(fontFamily: 'monospace'))),
          row(
            'Email',
            loading
                ? const Shimmer(child: Bone(width: 180, height: 16))
                : overview?.email != null && overview!.email!.isNotEmpty
                    ? Text(overview!.email!, style: valueStyle)
                    : const Text(
                        "None on file — you can't reset a forgotten password by email. "
                        'Ask the system administrator to add one.',
                        style: TextStyle(color: AppTheme.statusMaintenance, fontSize: 15, height: 1.4),
                      ),
          ),
          row(
            'Office',
            officeName != null
                ? Text(officeName, style: valueStyle)
                : Text('Not assigned', style: TextStyle(color: c.textTertiary, fontSize: 16)),
            last: true,
          ),
        ],
      ),
    );
  }
}

// ── 2-step verification ─────────────────────────────────────────────────────

class _TwoStepCard extends ConsumerStatefulWidget {
  final MyOverview? overview;
  final MyAccountService service;
  final ValueChanged<bool> onChanged;
  final void Function(String msg, {bool error}) onToast;

  const _TwoStepCard({
    required this.overview,
    required this.service,
    required this.onChanged,
    required this.onToast,
  });

  @override
  ConsumerState<_TwoStepCard> createState() => _TwoStepCardState();
}

class _TwoStepCardState extends ConsumerState<_TwoStepCard> {
  final _password = TextEditingController();
  bool _asking = false;
  bool _confirmForget = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save(bool enabled) async {
    if (!enabled && _password.text.isEmpty) {
      setState(() => _error = 'Enter your current password to turn it off.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final on = await widget.service.setTwoFactor(enabled, currentPassword: enabled ? null : _password.text);
      widget.onChanged(on);
      _password.clear();
      setState(() => _asking = false);
      widget.onToast(on ? '2-step verification is now on.' : '2-step verification is now off.');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forget() async {
    setState(() { _busy = true; _error = null; });
    try {
      await widget.service.forgetDevices();
      await ref.read(authProvider.notifier).logout();
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final o = widget.overview;
    if (o == null) {
      return const _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PanelTitle('2-step verification'),
            SizedBox(height: 12),
            Shimmer(child: Bone(width: double.infinity, height: 56)),
          ],
        ),
      );
    }
    final on = o.twoFactorEnabled;
    final hasEmail = o.email != null && o.email!.isNotEmpty;
    final body = TextStyle(color: c.textSecondary, fontSize: 15, height: 1.4);

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: _PanelTitle('2-step verification')),
              _OnOff(on),
            ],
          ),
          const SizedBox(height: 8),
          on
              ? Text.rich(TextSpan(style: body, children: [
                  const TextSpan(text: 'Signing in needs your password '),
                  const TextSpan(text: 'and', style: TextStyle(fontWeight: FontWeight.w700)),
                  const TextSpan(text: ' a 6-digit code sent to '),
                  TextSpan(text: o.email, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
                  const TextSpan(text: '.'),
                ]))
              : Text(
                  'Add a second check: after your password, you enter a 6-digit code sent to your email. '
                  "Someone who learns your password still can't sign in.",
                  style: body,
                ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Callout(_error!, tone: CalloutTone.error),
          ],
          if (!on) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _busy || !hasEmail ? null : () => _save(true),
              child: Text(_busy ? 'Turning on…' : 'Turn on'),
            ),
            if (!hasEmail) ...[
              const SizedBox(height: 8),
              const Text('Needs an email address on your account. Ask the system administrator to add one.',
                  style: TextStyle(color: AppTheme.statusMaintenance, fontSize: 14.5)),
            ],
          ],
          if (on && !_asking && !_confirmForget) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 20,
              children: [
                _LinkButton('Forget remembered devices…',
                    onTap: () => setState(() { _confirmForget = true; _error = null; })),
                _LinkButton('Turn off…',
                    color: c.textSecondary, onTap: () => setState(() { _asking = true; _error = null; })),
              ],
            ),
          ],
          if (on && _confirmForget) ...[
            const SizedBox(height: 14),
            Callout(
              'Every device where you ticked "Don\'t ask for a code" will ask for one again. '
              'This also signs you out everywhere, including here.',
              tone: CalloutTone.warning,
              action: Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _danger, foregroundColor: Colors.white),
                    onPressed: _busy ? null : _forget,
                    child: Text(_busy ? 'Signing out…' : 'Forget and sign out'),
                  ),
                  _LinkButton('Cancel', color: c.textSecondary, onTap: () => setState(() => _confirmForget = false)),
                ],
              ),
            ),
          ],
          if (on && _asking) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              obscureText: true,
              autofocus: true,
              autofillHints: const [AutofillHints.password],
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _save(false),
              decoration: const InputDecoration(labelText: 'Current password', hintText: "Confirm it's you"),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _danger, foregroundColor: Colors.white),
                  onPressed: _busy ? null : () => _save(false),
                  child: Text(_busy ? 'Turning off…' : 'Turn off 2-step'),
                ),
                _LinkButton('Cancel', color: c.textSecondary, onTap: () {
                  _password.clear();
                  setState(() { _asking = false; _error = null; });
                }),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Recent activity ─────────────────────────────────────────────────────────

class _ActivityCard extends StatelessWidget {
  final MyOverview? overview;
  final bool failed;
  const _ActivityCard({required this.overview, required this.failed});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final o = overview;

    final Widget content;
    if (failed) {
      content = Text("Couldn't load your recent activity. Pull down to try again.",
          style: TextStyle(color: c.textTertiary, fontSize: 15));
    } else if (o == null) {
      content = Shimmer(
        child: Column(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              const Bone(width: double.infinity, height: 36),
            ],
          ],
        ),
      );
    } else if (o.recentActivity.isEmpty) {
      content = Text('No activity recorded yet.', style: TextStyle(color: c.textTertiary, fontSize: 15));
    } else {
      content = Column(
        children: [
          for (var i = 0; i < o.recentActivity.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // timeline: dot + line down to the next entry
                  SizedBox(
                    width: 20,
                    child: Column(
                      children: [
                        const SizedBox(height: 4),
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: c.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.brand, width: 2),
                          ),
                        ),
                        if (i < o.recentActivity.length - 1)
                          Expanded(child: Container(width: 2, color: c.border)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: i < o.recentActivity.length - 1 ? 16 : 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_actionLabel(o.recentActivity[i].action),
                              style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                          if (o.recentActivity[i].details != null && o.recentActivity[i].details!.isNotEmpty)
                            Text(o.recentActivity[i].details!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: c.textSecondary, fontSize: 14)),
                          const SizedBox(height: 2),
                          Text(_timeAgo(o.recentActivity[i].loggedAt),
                              style: TextStyle(color: c.textTertiary, fontSize: 13.5)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle('Your recent activity'),
          const SizedBox(height: 14),
          content,
        ],
      ),
    );
  }
}
