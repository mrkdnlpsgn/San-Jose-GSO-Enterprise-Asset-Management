import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Shrinks a little the instant a finger lands (not on release), springs back on lift —
/// Apple's "respond on touch-down". Off when the phone asks for reduced motion.
class PressScale extends StatefulWidget {
  final Widget child;
  final double scale;
  const PressScale({super.key, required this.child, this.scale = 0.96});

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;
  Offset? _origin;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (context.prefersReducedMotion) return widget.child;
    return Listener(
      onPointerDown: (e) {
        _origin = e.position;
        _set(true);
      },
      // A finger that starts moving is scrolling, not pressing — let go at once, like iOS
      // cancelling a cell's highlight, instead of holding the card shrunk for the whole drag.
      onPointerMove: (e) {
        final o = _origin;
        if (_down && o != null && (e.position - o).distance > kTouchSlop) _set(false);
      },
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        // quick in on touch-down; back out on the app's strong ease-out — no overshoot, since
        // bounce belongs to flung gestures, not taps
        duration: Duration(milliseconds: _down ? 90 : 200),
        curve: _down ? Curves.easeOut : AppTheme.motionCurve,
        child: widget.child,
      ),
    );
  }
}

/// Opens / closes [child] by animating its height (220ms, the app's ease-out), so expanded
/// content grows out of the row that was tapped instead of jumping in. Reduce Motion: instant.
class ExpandReveal extends StatelessWidget {
  final bool expanded;
  final Widget child;
  const ExpandReveal({super.key, required this.expanded, required this.child});

  @override
  Widget build(BuildContext context) => ClipRect(
        child: AnimatedSize(
          duration: context.prefersReducedMotion ? Duration.zero : const Duration(milliseconds: 220),
          curve: AppTheme.motionCurve,
          alignment: Alignment.topCenter,
          child: expanded ? child : const SizedBox(width: double.infinity),
        ),
      );
}

/// The ⌄ on an expandable row: turns to ⌃ as it opens (a rotation, not an icon swap),
/// so the arrow visibly points where the content went. Reduce Motion: instant.
class DisclosureArrow extends StatelessWidget {
  final bool expanded;
  final Color? color;
  const DisclosureArrow({super.key, required this.expanded, this.color});

  @override
  Widget build(BuildContext context) => AnimatedRotation(
        turns: expanded ? 0.5 : 0,
        duration: context.prefersReducedMotion ? Duration.zero : const Duration(milliseconds: 200),
        curve: AppTheme.motionCurve,
        child: Icon(Icons.expand_more_rounded, color: color),
      );
}

/// The thin grey chevron at the end of a tappable iOS row.
class DisclosureChevron extends StatelessWidget {
  const DisclosureChevron({super.key});

  @override
  Widget build(BuildContext context) => Icon(
        Icons.arrow_forward_ios_rounded,
        size: 15,
        color: context.isLight ? const Color(0xFFC4C4C7) : const Color(0xFF5A5A5E),
      );
}
