import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/provider/auth_provider.dart';

/// Top of Home: who is signed in, and today's date and time.
///
///   Good morning, Mark Daniel Pesigan
///   Treasury Office · Thursday, October 15, 2026 · 11:55 AM
///
/// The name is there so a shared office phone shows whose account actions will be
/// recorded under — not as decoration, so no avatar, icons or "Mabuhay".
class HomeHeader extends ConsumerStatefulWidget {
  const HomeHeader({super.key});

  @override
  ConsumerState<HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends ConsumerState<HomeHeader> {
  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // keep the clock (and the morning/afternoon greeting) current while the screen is open
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      final n = DateTime.now();
      if (n.minute != _now.minute && mounted) setState(() => _now = n);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _greeting => _now.hour < 12
      ? 'Good morning'
      : _now.hour < 18
          ? 'Good afternoon'
          : 'Good evening';

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).value;
    final c = context.colors;
    final h = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
    final time = '$h:${_now.minute.toString().padLeft(2, '0')} ${_now.hour < 12 ? 'AM' : 'PM'}';
    final date = '${_days[_now.weekday - 1]}, ${_months[_now.month - 1]} ${_now.day}, ${_now.year}';
    // office for staff, role for admins — skipped when it would just repeat the name
    // (the seeded admin account's full name is literally "Administrator")
    final where = user == null
        ? null
        : user.isAdmin
            ? (user.displayName.toLowerCase() == 'administrator' ? null : 'Administrator')
            : (user.officeName ?? 'No office assigned');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          user == null ? _greeting : '$_greeting, ${user.displayName}',
          style: TextStyle(fontSize: 20, height: 1.25, fontWeight: FontWeight.w700, color: c.heading),
        ),
        const SizedBox(height: 4),
        Text(
          [if (where != null) where, date, time].join(' · '),
          style: TextStyle(fontSize: 15, height: 1.35, color: c.textSecondary),
        ),
      ],
    );
  }
}
