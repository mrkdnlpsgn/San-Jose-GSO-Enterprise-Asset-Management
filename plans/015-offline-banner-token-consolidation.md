# 015 - Swap OfflineBanner's hand-typed duration/curve for the shared motion tokens

- **Status**: TODO
- **Commit**: de894c7
- **Severity**: LOW
- **Category**: Cohesion & tokens
- **Estimated scope**: 1 file (`mobile_sj/lib/shared/widgets/offline_banner.dart`)

## Problem

```dart
// mobile_sj/lib/shared/widgets/offline_banner.dart:19-21 - current
AnimatedSize(
  duration: const Duration(milliseconds: 250),
  curve: Curves.easeOut,
  child: isOnline
```

This is a near-duplicate of the app's shared `AppTheme.motionMedium` (260ms) and `AppTheme.motionCurve` (`Curves.easeOutCubic`) tokens (`mobile_sj/lib/core/theme/app_theme.dart:102-105`), close enough that it's clearly meant to be "the standard medium transition" but hand-typed instead of referencing the token, so it will silently drift further if `motionMedium`/`motionCurve` is ever retuned.

## Target

```dart
// target
AnimatedSize(
  duration: AppTheme.motionMedium,
  curve: AppTheme.motionCurve,
  child: isOnline
```

## Repo conventions to follow

- `AppTheme` is already imported in this file (`import '../../core/theme/app_theme.dart';`, used for `AppTheme.statusMaintenance` a few lines below). No new import needed.

## Steps

1. In `mobile_sj/lib/shared/widgets/offline_banner.dart`, replace `duration: const Duration(milliseconds: 250)` with `duration: AppTheme.motionMedium` and `curve: Curves.easeOut` with `curve: AppTheme.motionCurve` on the `AnimatedSize` widget (lines 19-21).

## Boundaries

- Do NOT change anything else in this file. The connectivity-detection logic, the banner's content/styling, or the `Expanded(child: child)` structure.

## Verification

- **Mechanical**: `flutter analyze` (from `mobile_sj/`), clean.
- **Feel check**: toggle device connectivity off/on (or use the app's connectivity provider's test/mock path if one exists) and confirm the offline banner still grows/shrinks smoothly. The 10ms duration difference (250ms → 260ms) should be imperceptible.
- **Done when**: `offline_banner.dart` references `AppTheme.motionMedium`/`AppTheme.motionCurve` instead of a hand-typed duration/curve.
