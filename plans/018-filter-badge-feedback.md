# 018 - Animate the filter-active badge instead of a hard snap

- **Status**: TODO
- **Commit**: de894c7
- **Severity**: LOW
- **Category**: Missed opportunity (polish)
- **Estimated scope**: 3 files (`mobile_sj/lib/features/assets/screens/asset_list_screen.dart`, `mobile_sj/lib/features/maintenance/screens/maintenance_list_screen.dart`, `mobile_sj/lib/features/disposal/screens/disposal_list_screen.dart`)

## Problem

All three list screens use an identical structure for their filter icon's "active filters" indicator:

```dart
// mobile_sj/lib/features/assets/screens/asset_list_screen.dart:41-49 - current
IconButton(
  icon: Badge(
    isLabelVisible: filtersActive,
    smallSize: 8,
    child: const Icon(Icons.filter_list_rounded),
  ),
  tooltip: 'Filter',
  onPressed: () => showAssetFilterSheet(context, ref),
),
```

(`maintenance_list_screen.dart:41-49` and `disposal_list_screen.dart:41-49` are byte-for-byte the same pattern, just with their own `xFiltersActive`/`showXFilterSheet` names.) `Badge`'s `isLabelVisible` toggles the little dot on/off with no transition. The only feedback that "a filter is now active" snaps on/off instantly. This is the smallest, lowest-priority item in this audit, flagged only because it's a real, if minor, "state change with no transition" gap, and it's cheap to fix identically in all three places.

## Target

Wrap the `Badge` in an `AnimatedScale` so the dot pops in/out with a small pop rather than a snap:

```dart
// target (identical in all three files)
IconButton(
  icon: Badge(
    isLabelVisible: filtersActive,
    smallSize: 8,
    label: AnimatedScale(
      scale: filtersActive ? 1.0 : 0.0,
      duration: AppTheme.motionFast,
      curve: AppTheme.motionCurve,
      child: const SizedBox.shrink(),
    ),
    child: const Icon(Icons.filter_list_rounded),
  ),
  tooltip: 'Filter',
  onPressed: () => showAssetFilterSheet(context, ref),
),
```

Note: Flutter's `Badge` widget doesn't animate its own `isLabelVisible` toggle, and doesn't expose a way to wrap just its dot in an external animated widget via `smallSize` alone, if you find, on inspecting the actual `Badge` API in the Flutter SDK version this project pins, that `label`/`smallSize` can't be combined the way shown above (the "small" dot variant may not render children via `label` at all), STOP and use an `AnimatedOpacity`-wrapped custom dot `Container` instead of Flutter's built-in `Badge`, matching whatever the simplest correct approach is for the pinned Flutter/Material version, report which approach you used and why in your final summary, since this Target snippet is a best-effort based on the general `Badge` API shape and may need adjusting to the exact SDK version.

## Repo conventions to follow

- `AppTheme.motionFast` (160ms) / `AppTheme.motionCurve`, reuse the shared tokens, consistent with every other animation touched this session.
- All three files already import `AppTheme` (used for `AppTheme.brand` elsewhere in each). No new import needed for the tokens themselves; only add whatever widget import (`AnimatedScale`/`AnimatedOpacity`) is needed, which comes from `package:flutter/material.dart`, already imported everywhere.

## Steps

1. Inspect the actual `Badge` widget API available in this project's Flutter SDK (check `flutter --version` or the `Badge` class doc via IDE/SDK source) to confirm whether wrapping its dot via `label:` is viable, or whether a hand-rolled small `AnimatedOpacity`/`AnimatedScale`-wrapped `Container` positioned via `Stack` is more appropriate. Choose the simplest approach that actually animates the on/off transition smoothly; do not force the exact code shown in Target if the SDK's `Badge` doesn't support it.
2. Apply the chosen fix identically to all three files: `mobile_sj/lib/features/assets/screens/asset_list_screen.dart:41-49`, `mobile_sj/lib/features/maintenance/screens/maintenance_list_screen.dart:41-49`, `mobile_sj/lib/features/disposal/screens/disposal_list_screen.dart:41-49`.
3. Confirm the three files' final implementations are structurally identical (same widget, same tokens). This is a shared UI pattern and should stay visibly consistent across all three list screens.

## Boundaries

- Do NOT touch `assetFiltersActive`/`maintenanceFiltersActive`/`disposalFiltersActive` (the boolean-computing functions) or the filter-sheet-opening logic (`showAssetFilterSheet` etc.). Only the badge's visual transition.
- Do NOT introduce a new shared widget for this in this plan (e.g. an `AnimatedFilterBadge` component) even though the pattern is duplicated 3x. A shared-widget extraction is a reasonable follow-up but adds scope beyond this plan; inline the fix in each of the 3 files.
- If Step 1 reveals the `Badge` API genuinely cannot be animated cleanly without a disproportionate amount of custom painting/positioning work for a LOW-priority polish item, it's acceptable to skip this plan and report why, rather than over-engineering a fix for the smallest item in this audit.

## Verification

- **Mechanical**: `flutter analyze` (from `mobile_sj/`), clean.
- **Feel check**: on any of the three list screens, apply a filter (opening the filter sheet and selecting something) and confirm the small dot on the filter icon now animates in (a brief pop/fade) rather than snapping on; clear the filter and confirm it animates back out.
- **Done when**: all three list screens' filter-active indicator animates on/off using `AppTheme.motionFast`/`motionCurve`, with identical behavior across all three.
