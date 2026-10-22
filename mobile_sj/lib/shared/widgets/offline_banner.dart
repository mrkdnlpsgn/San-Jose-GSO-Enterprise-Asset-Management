import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/connectivity/connectivity_provider.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../features/dashboard/widgets/ios_style.dart' show Ios;
import '../../features/outbox/sync_engine.dart';

/// What the header bar is saying.
enum _Mode { offline, uploading, attention, waiting, backOnline }

/// A slim, full-width header bar that slides down from behind the status bar to say what's
/// going on with the connection and the changes saved on this phone:
///   orange "Offline" (with how many changes are waiting), blue "Uploading…", orange
///   "N changes need attention", blue "N waiting to upload" (online, but the server hasn't
///   answered yet), or a brief green "Back online".
/// Tapping it opens the list of waiting changes. The page moves down with the bar, so nothing
/// underneath is covered.
///
/// Motion follows iOS: a critically damped spring (no bounce, response 0.4s) that starts from
/// wherever the bar is, so a flapping connection reverses it mid-flight without a jump.
/// It leaves the way it came (back up). With animations turned off it just fades.
class OfflineBanner extends ConsumerStatefulWidget {
  final Widget child;
  const OfflineBanner({super.key, required this.child});

  @override
  ConsumerState<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends ConsumerState<OfflineBanner> with SingleTickerProviderStateMixin {
  /// Height of the text row below the status bar.
  static const double _rowHeight = 24;

  // damping 1.0, response 0.4s → stiffness (2π / response)², mass 1
  static final _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: math.pow(2 * math.pi / 0.4, 2).toDouble(),
    ratio: 1,
  );

  late final AnimationController _controller = AnimationController.unbounded(vsync: this);
  Timer? _flashTimer;
  bool _flash = false; // showing "Back online"
  bool _shown = false; // where the bar is heading
  _Mode _lastMode = _Mode.offline; // kept while the bar slides away, so its text doesn't change mid-exit

  @override
  void initState() {
    super.initState();
    if (ref.read(isOnlineProvider).valueOrNull == false) {
      _shown = true;
      _controller.value = 1;
    }
  }

  void _show(bool visible) {
    if (visible == _shown) return;
    _shown = visible;
    final target = visible ? 1.0 : 0.0;
    if (MediaQuery.of(context).disableAnimations) {
      _controller.animateTo(target, duration: const Duration(milliseconds: 200), curve: Curves.linear);
    } else {
      // From the live value and velocity — interruptible, no seam on reversal.
      _controller.animateWith(SpringSimulation(_spring, _controller.value, target, _controller.velocity));
    }
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only confirm a recovery the user actually saw go wrong.
    ref.listen<AsyncValue<bool>>(isOnlineProvider, (prev, next) {
      final online = next.valueOrNull;
      if (online == true && prev?.valueOrNull == false) {
        _flashTimer?.cancel();
        setState(() => _flash = true);
        _flashTimer = Timer(const Duration(milliseconds: 1600), () {
          if (mounted) setState(() => _flash = false);
        });
      } else if (online == false) {
        _flashTimer?.cancel();
        if (_flash) setState(() => _flash = false);
      }
    });

    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
    final items = ref.watch(outboxProvider).items;
    final sync = ref.watch(syncEngineProvider);
    final attention = items.where((i) => i.needsAttention).length;

    final _Mode? mode = !online
        ? _Mode.offline
        : sync.syncing
            ? _Mode.uploading
            : attention > 0
                ? _Mode.attention
                : _flash
                    ? _Mode.backOnline
                    : items.isNotEmpty
                        ? _Mode.waiting
                        : null;
    if (mode != null) _lastMode = mode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _show(mode != null);
    });

    final shownMode = mode ?? _lastMode;
    final (color, icon, label) = switch (shownMode) {
      _Mode.offline => (
          Ios.orange,
          Icons.wifi_off_rounded,
          items.isEmpty ? 'Offline' : 'Offline · ${items.length} saved on this phone',
        ),
      _Mode.uploading => (
          Ios.blue,
          Icons.cloud_upload_rounded,
          'Uploading ${math.min(sync.done + 1, sync.total)} of ${sync.total}…'
        ),
      _Mode.attention => (
          Ios.orange,
          Icons.error_outline_rounded,
          attention == 1 ? '1 change needs attention' : '$attention changes need attention',
        ),
      _Mode.waiting => (Ios.blue, Icons.cloud_queue_rounded, '${items.length} waiting to upload'),
      _Mode.backOnline => (Ios.green, Icons.wifi_rounded, 'Back online'),
    };

    final top = MediaQuery.paddingOf(context).top;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final barHeight = top + _rowHeight;
    final tappable = items.isNotEmpty;

    final bar = Semantics(
      liveRegion: true,
      button: tappable,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tappable ? () => ref.read(appRouterProvider).push('/outbox') : null,
        child: _Bar(
          color: color,
          icon: icon,
          label: label,
          chevron: tappable,
          statusBarHeight: top,
          rowHeight: _rowHeight,
        ),
      ),
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value.clamp(0.0, 1.0);
        final visible = t > 0.001;
        return Stack(
          fit: StackFit.expand,
          children: [
            // The page keeps its own status-bar padding (the bar covers that area) and moves
            // down only by the text row, in step with the bar.
            Padding(padding: EdgeInsets.only(top: _rowHeight * t), child: child),
            if (visible)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: barHeight,
                child: AnnotatedRegion<SystemUiOverlayStyle>(
                  value: SystemUiOverlayStyle.light, // white status icons on the colored bar
                  child: reduceMotion
                      ? Opacity(opacity: t, child: bar)
                      : Transform.translate(offset: Offset(0, (1 - t) * -barHeight), child: bar),
                ),
              ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

class _Bar extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final bool chevron;
  final double statusBarHeight;
  final double rowHeight;

  const _Bar({
    required this.color,
    required this.icon,
    required this.label,
    required this.chevron,
    required this.statusBarHeight,
    required this.rowHeight,
  });

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontFamily: AppTheme.fontFamily,
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      height: 1.0,
      decoration: TextDecoration.none,
    );
    // Sits above the Navigator, outside any page's Material, so it needs its own —
    // without one Flutter draws text with the yellow double-underline debug style.
    return Material(
      type: MaterialType.transparency,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: const Cubic(0.23, 1, 0.32, 1),
        color: color,
        padding: EdgeInsets.only(top: statusBarHeight),
        child: SizedBox(
          height: rowHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: Colors.white),
              const SizedBox(width: 5),
              Flexible(child: Text(label, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (chevron) ...[
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right_rounded, size: 15, color: Colors.white),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
