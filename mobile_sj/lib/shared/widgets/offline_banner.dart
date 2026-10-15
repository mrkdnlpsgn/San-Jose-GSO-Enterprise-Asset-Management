import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/connectivity/connectivity_provider.dart';
import '../../core/theme/app_theme.dart';

/// Wraps [child] with a slim, animated "You're offline" strip that appears
/// app-wide whenever connectivity drops — signaling the problem proactively
/// instead of only surfacing it after a request already fails.
class OfflineBanner extends ConsumerWidget {
  final Widget child;
  const OfflineBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider).valueOrNull ?? true;

    return Column(
      children: [
        AnimatedSize(
          duration: AppTheme.motionMedium,
          curve: AppTheme.motionCurve,
          child: isOnline
              ? const SizedBox(width: double.infinity)
              : const Material(
                  color: AppTheme.statusMaintenance,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_off_rounded, size: 15, color: Colors.white),
                          SizedBox(width: 8),
                          Text("You're offline",
                              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
