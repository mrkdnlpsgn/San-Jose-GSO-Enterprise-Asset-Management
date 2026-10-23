# 021 - Bump the stagger delay into the recommended 30-80ms band

- **Status**: TODO
- **Commit**: de894c7
- **Severity**: LOW
- **Category**: Cohesion & tokens (polish)
- **Estimated scope**: 1 file (`mobile_sj/lib/shared/widgets/staggered_entrance.dart`)

## Problem

```dart
// mobile_sj/lib/shared/widgets/staggered_entrance.dart:19-26 - current
@override
void initState() {
  super.initState();
  final delay = Duration(milliseconds: 25 * widget.index.clamp(0, 10));
  Future.delayed(delay, () {
    if (mounted) setState(() => _visible = true);
  });
}
```

AUDIT.md #7 recommends a 30-80ms stagger delay between items ("Everything-at-once group entrances where a 30–80ms stagger belongs" / "Keep stagger delays short (30-80ms between items). Longer delays feel slow."). This app's `25 * index` undershoots that band slightly, not wrong, just under the recommended minimum.

## Target

```dart
// target
final delay = Duration(milliseconds: 40 * widget.index.clamp(0, 10));
```

`40ms` sits comfortably inside the 30-80ms band, roughly in the middle-low end (matching this app's stated "restrained, functional" motion personality per the comment in `app_theme.dart:100-101`. A value near the top of the band, e.g. 70-80ms, would read as more deliberately theatrical than this app's enterprise tone calls for). The existing `.clamp(0, 10)` cap is unchanged, so the maximum possible delay moves from 250ms (25×10) to 400ms (40×10) for the 11th+ item in a cascading group, still well within a reasonable total cascade length for a list of visible items on one screen.

## Repo conventions to follow

- This is a single-constant change in the one file that owns the app's stagger behavior. No other file references the `25`/`40` literal, so no other changes are needed.

## Steps

1. In `mobile_sj/lib/shared/widgets/staggered_entrance.dart`, change `25 * widget.index.clamp(0, 10)` to `40 * widget.index.clamp(0, 10)` on line 22.

## Boundaries

- Do NOT change the `.clamp(0, 10)` cap itself, `AppTheme.motionMedium`/`motionCurve` (the fade/slide duration and curve used once the delay elapses), or any consumer of `StaggeredEntrance`.

## Verification

- **Mechanical**: `flutter analyze` (from `mobile_sj/`), clean.
- **Feel check**: open any list screen with several visible rows at once (e.g. Assets with 8+ results, or the Dashboard's module cards) and watch the cascade, confirm it still reads as a quick, cohesive cascade rather than a slow reveal, just with slightly more separation between each item's entrance than before.
- **Done when**: the per-item stagger delay is `40 * index` (clamped at index 10, i.e. max 400ms), and the cascade still feels quick and cohesive, not slow.
