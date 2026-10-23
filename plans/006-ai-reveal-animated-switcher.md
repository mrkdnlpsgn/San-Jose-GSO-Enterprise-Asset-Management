# 006 - Animate the AI recommendation/summary reveal instead of a hard teleport

- **Status**: TODO
- **Commit**: de894c7
- **Severity**: MEDIUM
- **Category**: Missed opportunity / Interruptibility
- **Estimated scope**: 2 files (`mobile_sj/lib/features/assets/screens/asset_detail_screen.dart`, `mobile_sj/lib/features/maintenance/screens/maintenance_detail_screen.dart`)

## Problem

Both screens show an AI-generated result (a lifecycle recommendation / a maintenance summary) inside a card whose body is built directly from an `AsyncValue.when(...)` with no transition between its `loading`/`data(null)`/`data(rec)` branches:

```dart
// mobile_sj/lib/features/assets/screens/asset_detail_screen.dart:585-611 - current (relevant excerpt)
recAsync.when(
  loading: () => const Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Center(child: CircularProgressIndicator(color: AppTheme.brand)),
  ),
  error: (e, _) => Text(e.toString(), style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
  data: (rec) {
    if (rec == null) {
      if (_generating) {
        return Row(
          children: [
            const SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brand),
            ),
            const SizedBox(width: 10),
            Text('Generating recommendation…',
                style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
          ],
        );
      }
      return Text(
        isAdmin
            ? 'No recommendation yet. Tap refresh to generate one.'
            : 'No recommendation generated yet.',
        style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
      );
    }
    final color = _color(rec.recommendation);
    return Column(/* ...the actual recommendation chip + rationale... */);
  },
),
```

```dart
// mobile_sj/lib/features/maintenance/screens/maintenance_detail_screen.dart:219-243 - current (identical shape)
summaryAsync.when(
  loading: () => const Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Center(child: CircularProgressIndicator(color: AppTheme.brand)),
  ),
  error: (e, _) => Text(e.toString(), style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
  data: (summary) {
    if (summary == null) {
      return Text(
        isAdmin ? 'No summary yet. Tap refresh to generate one.' : 'No summary generated yet.',
        style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
      );
    }
    return Column(/* ...the actual summary text... */);
  },
),
```

When the async call resolves (spinner → "Generating…" → real content), Flutter swaps these entirely different widget subtrees in a single frame. The card visibly reflows/jumps the instant the AI result arrives, with zero feedback that something meaningful just happened. This is the single highest-anticipation moment on either screen.

## Target

Wrap the `.when(...)` result in an `AnimatedSwitcher` using the app's shared motion tokens (`AppTheme.motionMedium` = 260ms, `AppTheme.motionCurve` = `Curves.easeOutCubic`, both defined in `mobile_sj/lib/core/theme/app_theme.dart:102-105`), keyed so each distinct visual state (loading / generating / empty / has-data) is treated as a different child and cross-fades:

```dart
// target - asset_detail_screen.dart
AnimatedSwitcher(
  duration: AppTheme.motionMedium,
  switchInCurve: AppTheme.motionCurve,
  switchOutCurve: AppTheme.motionCurve,
  transitionBuilder: (child, animation) => FadeTransition(
    opacity: animation,
    child: SizeTransition(sizeFactor: animation, axisAlignment: -1, child: child),
  ),
  child: recAsync.when(
    loading: () => const Padding(
      key: ValueKey('loading'),
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Center(child: CircularProgressIndicator(color: AppTheme.brand)),
    ),
    error: (e, _) => Text(
      key: const ValueKey('error'),
      e.toString(),
      style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
    ),
    data: (rec) {
      if (rec == null) {
        if (_generating) {
          return Row(
            key: const ValueKey('generating'),
            children: [/* unchanged */],
          );
        }
        return Text(
          key: const ValueKey('empty'),
          isAdmin ? 'No recommendation yet. Tap refresh to generate one.' : 'No recommendation generated yet.',
          style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
        );
      }
      final color = _color(rec.recommendation);
      return Column(
        key: ValueKey('data-${rec.recommendation}-${rec.generatedAt}'), // any field that changes when a new recommendation is generated
        children: [/* unchanged */],
      );
    },
  ),
),
```

The `data-...` key must include something that changes when a *new* recommendation is generated (so regenerating triggers the cross-fade too, not just the loading→data transition). Use whatever field on `rec`/`summary` represents "when this was generated" (check the model class for a timestamp field name; do not invent a field that doesn't exist).

## Repo conventions to follow

- `AppTheme.motionMedium`/`AppTheme.motionCurve` are the app's shared tokens (`mobile_sj/lib/core/theme/app_theme.dart:102-105`). Use them here rather than hand-typing a duration/curve, per this session's established convention (see how `StaggeredEntrance`, `mobile_sj/lib/shared/widgets/staggered_entrance.dart`, already consumes these same tokens as the exemplar).
- `AnimatedSwitcher` requires every child to have a distinct, stable `Key` or it won't detect a change and won't animate. This is the most common mistake when adding one; double-check every branch above has a `key:`.

## Steps

1. In `mobile_sj/lib/features/assets/screens/asset_detail_screen.dart`, locate the `recAsync.when(...)` call (around line 585) and wrap it in `AnimatedSwitcher` exactly as shown in Target. Add a `ValueKey` to every branch's returned widget (`loading`, `error`, the `generating` `Row`, the `empty` `Text`, and the `data` `Column`), for the `data` branch, inspect the `AiRecommendationModel` class (find it via the import at the top of this file) for a generated-at/timestamp-like field to include in the key.

2. Apply the identical wrapping to `mobile_sj/lib/features/maintenance/screens/maintenance_detail_screen.dart`'s `summaryAsync.when(...)` (around line 219), using the equivalent fields on whatever the summary model class is called.

3. Both files already import `package:flutter/material.dart`, which provides `AnimatedSwitcher`/`FadeTransition`/`SizeTransition`. No new imports needed. Confirm `AppTheme` is already imported in both files (it is, per their existing use of `AppTheme.brand`).

## Boundaries

- Do NOT change the actual content/logic of any branch (the recommendation chip, rationale text, summary paragraph). Only add `key:` and wrap the whole `.when(...)` result.
- Do NOT change the `_generate`/`_generating` state logic, the refresh `IconButton`, or the `ref.listen(...)` auto-generate-on-first-view logic in `asset_detail_screen.dart` (lines 545-553), out of scope.
- Do NOT introduce a new shared "AI reveal" widget in this plan, inline the `AnimatedSwitcher` in both files even though the pattern is duplicated; a shared widget extraction is a reasonable follow-up but not part of this plan's scope.

## Verification

- **Mechanical**: `flutter analyze` (run from `mobile_sj/`). No new errors/warnings, especially not "duplicate keys" or "missing key" warnings from `AnimatedSwitcher`.
- **Feel check**:
  - Open an asset that has no AI recommendation yet (as an admin, so auto-generate or the refresh button is available), confirm the "Generating…" row cross-fades into the recommendation chip/rationale when it resolves, rather than popping in instantly.
  - Tap the refresh icon to regenerate an existing recommendation, confirm the transition plays again (this confirms the `data` branch's key correctly changes on regeneration, not just on the initial load).
  - Repeat both checks on a Maintenance record's AI summary.
  - In slow motion (DevTools isn't available for Flutter the same way, instead, temporarily bump `AppTheme.motionMedium` to `Duration(milliseconds: 1500)` locally while testing, then revert before finishing) confirm the fade+size transition looks smooth, not jarring, and doesn't clip the card's rounded corners mid-transition.
- **Done when**: the AI recommendation/summary reveal cross-fades in both files instead of hard-swapping, using `AppTheme.motionMedium`/`AppTheme.motionCurve`, and regenerating also re-triggers the transition.
