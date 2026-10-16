import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// One-time fade + slide-up entrance, staggered by [index] so a group of
/// cards/rows settles in a quick cascade rather than popping in all at once.
/// Delay is capped so long lists/groups don't accumulate a multi-second stagger.
class StaggeredEntrance extends StatefulWidget {
  final int index;
  final Widget child;
  const StaggeredEntrance({super.key, required this.index, required this.child});

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance> {
  bool _visible = false;
  bool _scheduled = false;

  // MediaQuery isn't available yet in initState() (no InheritedWidget ancestor
  // resolved that early) — didChangeDependencies() is the correct place to
  // read it once, guarded so it only schedules the entrance a single time.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    // 30ms apart, capped at the 6th item: lists open tens of times a day, so the cascade stays
    // a quick settle (last row in ~440ms) rather than making results feel slow to arrive.
    final delay = reduceMotion ? Duration.zero : Duration(milliseconds: 30 * widget.index.clamp(0, 6));
    Future.delayed(delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: AppTheme.motionMedium,
      curve: AppTheme.motionCurve,
      child: reduceMotion
          ? widget.child
          : AnimatedSlide(
              offset: _visible ? Offset.zero : const Offset(0, 0.04),
              duration: AppTheme.motionMedium,
              curve: AppTheme.motionCurve,
              child: widget.child,
            ),
    );
  }
}
