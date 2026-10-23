# 019 - Replace the shared `motionCurve` builtin with a strong custom curve

- **Status**: TODO
- **Commit**: de894c7
- **Severity**: LOW (but wide blast radius, touches every animated surface in the app)
- **Category**: Easing & duration / Cohesion
- **Estimated scope**: 1 file changed (`mobile_sj/lib/core/theme/app_theme.dart`), but the effect is felt across every consumer of `AppTheme.motionCurve`, currently: `page_transitions.dart` (every screen transition), `staggered_entrance.dart` (every list/card cascade), the dashboard's count-up numbers and lifecycle ring, and every plan in this set that references `AppTheme.motionCurve` (006, 007, 009, 014, 015, 018).

## Problem

```dart
// mobile_sj/lib/core/theme/app_theme.dart:100-105 - current
// Motion tokens - restrained, functional timings (not playful/bouncy) so
// transitions read as "responsive UI", matching an enterprise system's tone.
static const Duration motionFast = Duration(milliseconds: 160);
static const Duration motionMedium = Duration(milliseconds: 260);
static const Duration motionSlow = Duration(milliseconds: 420);
static const Curve motionCurve = Curves.easeOutCubic;
```

`Curves.easeOutCubic` is Flutter's builtin cubic-out curve, serviceable, but exactly the kind of "built-in easing is too weak for deliberate motion" case AUDIT.md #2 calls out; it lacks the initial punch of a purpose-built strong ease-out. Since this one token is reused for literally every entrance/transition in the app (every page push, every staggered card, the dashboard's number count-ups and ring reveal), its relative softness is inherited everywhere.

## Target

```dart
// target
static const Curve motionCurve = Cubic(0.23, 1, 0.32, 1);
```

`Cubic(0.23, 1, 0.32, 1)` is Flutter's `Curve` equivalent of the CSS `cubic-bezier(0.23, 1, 0.32, 1)`. The exact "strong ease-out for UI" curve from AUDIT.md #2. Flutter's `Cubic` class takes the same four control-point parameters as a CSS cubic-bezier, so this is a direct, faithful port of the same curve already used conceptually in this session's frontend work (and coincidentally close to the `EASE_ENTER`/`cubic-bezier(0.16, 1, 0.3, 1)` used by the web app's own entrances, per plan 011. The two clients won't share byte-identical curves, but both move toward the same "strong ease-out" character).

## Repo conventions to follow

- `Curve`/`Cubic` come from `package:flutter/animation.dart`, already transitively available via the existing `package:flutter/material.dart` import in `app_theme.dart`. No new import needed.
- This is a single-line, single-token change specifically BECAUSE the app already centralized its curve into one shared constant. This plan is only possible/safe because that consolidation already happened; do not scatter the new `Cubic(...)` literal anywhere else, keep it defined exactly once here.

## Steps

1. In `mobile_sj/lib/core/theme/app_theme.dart`, change line 105 from `static const Curve motionCurve = Curves.easeOutCubic;` to `static const Curve motionCurve = Cubic(0.23, 1, 0.32, 1);`.
2. Do not touch `motionFast`/`motionMedium`/`motionSlow`. Only the curve.

## Boundaries

- Do NOT touch any consumer of `AppTheme.motionCurve`. This plan is a single-token change; every other file automatically picks up the new curve by referencing the same constant.
- Because this affects every animated surface in the app simultaneously, this plan should be executed and feel-checked in isolation from other plans in this set. Do not batch it together with unrelated plans in the same review pass, so a feel regression (if any) is easy to attribute and revert.
- If the new curve feels noticeably "snappier to the point of harsh" on the dashboard's 1100ms ring-reveal specifically (a long-duration animation where a strong ease-out's early punch might read differently than on a short 160-260ms UI transition), note that as a specific observation in your final report. Do not silently carve out an exception for it without flagging the tradeoff, since AUDIT.md's guidance is for this exact curve to be used broadly, but a long-duration outlier is worth calling out rather than burying.

## Verification

- **Mechanical**: `flutter analyze` (from `mobile_sj/`), clean; confirm `Cubic` resolves without a new import needed (it should, via the existing `material.dart` import chain, if not, add `import 'package:flutter/animation.dart';` explicitly and note that you needed to).
- **Feel check**. This is the single highest-leverage feel-check in this entire plan set, since it touches everything:
  - Navigate between at least 3 different screens (e.g. Dashboard → Assets → an asset detail) and confirm the page transitions feel slightly snappier/more responsive at the start of the motion, without looking jerky or overshooting.
  - Open a list screen (Assets/Maintenance/Disposal) and watch the staggered card entrance, confirm the cascade still reads as smooth, not abrupt.
  - Open the Dashboard and watch the count-up numbers and the lifecycle ring reveal, specifically check whether the ring's 1100ms draw looks noticeably different in character (see the Boundaries note above); describe what you observe.
  - Do this comparison in slow motion if possible: temporarily multiply `motionFast`/`motionMedium`/`motionSlow` by 4x locally (do NOT commit this test change) to see the curve's shape more clearly, then revert before finishing.
- **Done when**: `AppTheme.motionCurve` is `Cubic(0.23, 1, 0.32, 1)`, every consumer picks it up automatically with no other file changes, and you've explicitly recorded your feel-check observations (especially on the long-duration ring reveal) in your final report.
