import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Pulses its child's opacity to signal "loading" without pulling in a
/// shimmer package. One controller per skeleton block, shared by all
/// [Bone] placeholders inside it via [FadeTransition].
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
  late final Animation<double> _opacity = Tween<double>(begin: 0.4, end: 1.0).animate(_controller);

  // Reduce Motion: no endless pulse (a slow looping oscillation) - hold a still, dimmed
  // placeholder instead. Re-checked when the setting changes.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.prefersReducedMotion) {
      _controller.stop();
      _controller.value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _opacity, child: widget.child);
}

/// A single skeleton "bone" - a tinted rounded rect standing in for text,
/// an icon, or any other content shape while it loads.
class Bone extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const Bone({super.key, required this.width, this.height = 12, this.borderRadius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.colors.textTertiary.withValues(alpha: 0.18),
        borderRadius: borderRadius ?? BorderRadius.circular(4),
      ),
    );
  }
}

/// Matches the common list-row card shape shared by Assets, Maintenance, and
/// Disposal (header row + badge, 2-line description, footer row) - used as a
/// generic loading placeholder anywhere those lists are still fetching.
class ListCardSkeleton extends StatelessWidget {
  const ListCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Bone(width: 90, height: 12),
                const Spacer(),
                Bone(width: 70, height: 20, borderRadius: BorderRadius.circular(6)),
              ],
            ),
            const SizedBox(height: 10),
            const Bone(width: double.infinity, height: 15),
            const SizedBox(height: 6),
            const Bone(width: 160, height: 15),
            const SizedBox(height: 10),
            const Bone(width: 120, height: 12),
          ],
        ),
      ),
    );
  }
}

/// A scrollable-looking stack of [ListCardSkeleton]s, pulsing together,
/// for the initial-load state of any paginated list.
class ListSkeleton extends StatelessWidget {
  final int count;
  const ListSkeleton({super.key, this.count = 6});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, __) => const ListCardSkeleton(),
      ),
    );
  }
}
