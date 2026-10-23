# 017 - Use `Curves.linear` for the looping Shimmer pulse

- **Status**: TODO
- **Commit**: de894c7
- **Severity**: LOW
- **Category**: Easing & duration (polish)
- **Estimated scope**: 1 file (`mobile_sj/lib/shared/widgets/skeleton.dart`)

## Problem

```dart
// mobile_sj/lib/shared/widgets/skeleton.dart:15-28 - current
class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}
```

Per the easing decision order (entering/exiting → ease-out; moving/morphing on screen → ease-in-out; hover/color → ease; **constant/looping motion → linear**), a repeating `reverse: true` opacity pulse is exactly the "constant motion" case. The convention calls for `linear`, not `easeInOut`. This is polish-tier (the current easeInOut "breathing" pulse is a legitimate, common stylistic choice for shimmer effects and not wrong on its own merits), included here as a cheap, low-risk consolidation with the audit's own stated convention rather than a functional bug.

## Target

```dart
// target
opacity: Tween<double>(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.linear)),
```

## Repo conventions to follow

- No shared "loop curve" token exists yet in `AppTheme`. This plan does not introduce one (out of scope); it only changes this one `CurvedAnimation`'s curve argument.

## Steps

1. In `mobile_sj/lib/shared/widgets/skeleton.dart`, change `curve: Curves.easeInOut` to `curve: Curves.linear` on line 28 (the `CurvedAnimation` inside `_ShimmerState.build`).

## Boundaries

- Do NOT change the `AnimationController`'s duration (1000ms) or the `repeat(reverse: true)` behavior.
- Do NOT change the `Tween`'s `begin`/`end` opacity values (0.4/1.0).
- If, after making this change, the shimmer pulse feels mechanically worse in your own judgment (linear pulsing can sometimes look more robotic than eased breathing for this specific kind of loop), say so explicitly in your final report rather than silently reverting. This is a low-confidence, feel-dependent call per AUDIT's own guidance to flag uncertainty rather than guess.

## Verification

- **Mechanical**: `flutter analyze` (from `mobile_sj/`), clean.
- **Feel check**: trigger any loading skeleton (e.g. reload the Dashboard, or the Assets list while data is fetching) and watch the shimmer pulse for a few full cycles, confirm it still reads as a smooth, ongoing "breathing" placeholder, not a jarring flicker. If it looks worse than the `easeInOut` version, note that in your report rather than shipping a regression.
- **Done when**: the Shimmer's opacity loop uses `Curves.linear`, and the change has been eye-checked to confirm it doesn't look worse than the previous `easeInOut` version.
