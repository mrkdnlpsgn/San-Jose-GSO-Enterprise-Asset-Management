# 020 - Add reduced-motion accommodation across the app's key animated surfaces

- **Status**: TODO
- **Commit**: de894c7
- **Severity**: LOW (correctness/accessibility gap; broader scope than most other plans in this set)
- **Category**: Accessibility
- **Estimated scope**: 3-4 files (`mobile_sj/lib/core/router/page_transitions.dart`, `mobile_sj/lib/shared/widgets/staggered_entrance.dart`, plus a small shared helper; optionally `mobile_sj/lib/features/dashboard/screens/dashboard_screen.dart` for the count-up/ring animations)

## Problem

A full-tree grep for `disableAnimations` across `mobile_sj/lib/` returns zero hits (confirmed this session). Flutter's `MediaQuery.of(context).disableAnimations` is the platform's reduced-motion signal (reflects the OS-level "Reduce Motion" accessibility setting on iOS/Android). This app has no accommodation for it anywhere. Per AUDIT.md #6 (translated from CSS to Flutter for this app): "Reduced motion means fewer and gentler animations, not zero. Keep transitions that aid comprehension, remove position changes."

The three highest-impact surfaces to address:
1. **Page transitions** (`page_transitions.dart`'s `fadeThroughPage`), currently fade + 2%-upward-slide; under reduced motion, should drop the slide (a `transform`/position change) but can keep a brief opacity cross-fade.
2. **Stagger entrances** (`staggered_entrance.dart`), currently fade + 4%-downward-slide with a per-item delay; under reduced motion, the delay/cascade (motion-adjacent, not itself a position change, but part of the "movement" experience) and the slide should both be dropped, while the opacity fade can stay.
3. **Dashboard count-ups/ring** (`dashboard_screen.dart`'s `TweenAnimationBuilder`-based number count-ups and the lifecycle ring draw). These aren't `transform`-based, they're numeric/stroke-length changes; arguably lower priority since they don't involve on-screen movement in the strict sense, but a long 1100ms ring draw under reduced motion could reasonably jump straight to the final state. Treat this as optional/stretch scope. The executor should prioritize #1 and #2 first and only attempt #3 if time/confidence allows.

## Target

Add a small shared helper so every consumer checks the same signal the same way:

```dart
// mobile_sj/lib/core/theme/app_theme.dart - target (add alongside the existing motion tokens)
extension ReducedMotionX on BuildContext {
  bool get prefersReducedMotion => MediaQuery.of(this).disableAnimations;
}
```

**`page_transitions.dart`** - drop the slide, keep the fade, when reduced motion is on:

```dart
// mobile_sj/lib/core/router/page_transitions.dart - target
CustomTransitionPage<void> fadeThroughPage(BuildContext context, GoRouterState state, Widget child) {
  final reduceMotion = context.prefersReducedMotion;
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: AppTheme.motionMedium,
    reverseTransitionDuration: AppTheme.motionFast,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: AppTheme.motionCurve);
      if (reduceMotion) {
        return FadeTransition(opacity: curved, child: child);
      }
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}
```

**`staggered_entrance.dart`** - drop the slide and the per-item delay, keep a brief fade:

```dart
// mobile_sj/lib/shared/widgets/staggered_entrance.dart - target
class _StaggeredEntranceState extends State<StaggeredEntrance> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final delay = reduceMotion ? Duration.zero : Duration(milliseconds: 25 * widget.index.clamp(0, 10));
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
```

Note: `MediaQuery.of(context)` inside `initState` requires the widget to already be mounted with an `InheritedWidget` ancestor available, which is generally fine in `initState` for a `StatefulWidget` already inserted into the tree, but if this causes an "inheritFromWidgetOfExactType() was called before initState() completed" class of issue in practice, move the `disableAnimations` read into `didChangeDependencies()` instead and cache it in a field. Try `initState()` first since Flutter does support `MediaQuery.of(context)` there in most versions, but verify with `flutter analyze`/a real run and adjust if needed.

## Repo conventions to follow

- Add the `ReducedMotionX` extension to `app_theme.dart`, right next to the existing motion tokens (after line 105). This file is already the single source of truth for motion-related shared code in this app (see `motionFast`/`motionMedium`/`motionSlow`/`motionCurve`), so a reduced-motion helper belongs there too, not in a new file.

## Steps

1. Add the `ReducedMotionX` extension to `mobile_sj/lib/core/theme/app_theme.dart`, immediately after the existing `motionCurve` constant (line 105).
2. Update `mobile_sj/lib/core/router/page_transitions.dart`'s `fadeThroughPage` exactly as shown in Target, branch on `context.prefersReducedMotion` (using the new extension) to skip the `SlideTransition` wrapper.
3. Update `mobile_sj/lib/shared/widgets/staggered_entrance.dart` exactly as shown in Target, skip the stagger delay and the `AnimatedSlide` wrapper when reduced motion is on, keeping only the opacity fade.
4. Optional/stretch: if confident and time allows, apply the same "skip the animated reveal, jump to final state" treatment to the dashboard's `TweenAnimationBuilder` count-ups and the `_LifecycleRingCard`'s 1100ms ring draw (`mobile_sj/lib/features/dashboard/screens/dashboard_screen.dart`), e.g. wrap each `TweenAnimationBuilder`'s `duration:` in a `context.prefersReducedMotion ? Duration.zero : AppTheme.motionSlow` (or the ring's hardcoded 1100ms) ternary. If this feels like it's expanding scope beyond what's comfortable to verify, skip it and note it as a follow-up in your final report, plan 019 already touches this same file's motion curve, so avoid compounding both changes in one pass without a clear feel-check in between.

## Boundaries

- Do NOT attempt to add reduced-motion handling to every single animated widget in the app in this plan, scope is explicitly the two shared, high-leverage surfaces (`page_transitions.dart`, `staggered_entrance.dart`) plus the optional dashboard stretch goal. Broader coverage (individual screens' `AnimatedSwitcher`s from plan 006, `AnimatedSize` reveals from plan 014, etc.) is out of scope for this plan. Those can each add their own reduced-motion branch in a future pass if this pattern proves out.
- Do NOT change any duration/curve VALUES for the non-reduced-motion path. This plan only adds a conditional branch, the default (reduced motion off) behavior must be pixel-for-pixel identical to before.
- If reading `MediaQuery.of(context).disableAnimations` inside `initState()` in `staggered_entrance.dart` causes any framework assertion/error, switch to reading it in `didChangeDependencies()` and cache the result in a field. Do not leave a crash in place.

## Verification

- **Mechanical**: `flutter analyze` (from `mobile_sj/`), clean.
- **Feel check**:
  - On a real device or simulator, enable "Reduce Motion" (iOS: Settings → Accessibility → Motion; Android: varies by OEM, often Settings → Accessibility) or use Flutter's `MediaQuery` override in a debug harness if a physical toggle isn't convenient.
  - With reduced motion ON: navigate between screens and confirm transitions still fade but no longer slide upward; open a list screen and confirm cards still fade in but appear immediately (no stagger delay) and without a slide.
  - With reduced motion OFF (default): confirm every animation looks and times exactly as it did before this plan. No regression to the default experience.
- **Done when**: with the OS reduced-motion setting on, page transitions and staggered entrances still provide an opacity cue but drop position/delay-based movement; with it off, behavior is unchanged.
