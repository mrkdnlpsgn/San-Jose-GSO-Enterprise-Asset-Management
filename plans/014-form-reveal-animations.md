# 014 - Animate conditional form-field reveals instead of a layout jump

- **Status**: TODO
- **Commit**: de894c7
- **Severity**: LOW
- **Category**: Missed opportunity
- **Estimated scope**: 3 files (`mobile_sj/lib/features/assets/screens/asset_form_screen.dart`, `mobile_sj/lib/features/auth/screens/forgot_password_screen.dart`, `mobile_sj/lib/shared/widgets/password_requirements.dart`)

## Problem

Three recurring spots across the app reveal/hide form content via a bare conditional (`if (...) return widget;` / `if (condition) child`) with no transition. The new content just appears, shoving everything below it down instantly:

```dart
// mobile_sj/lib/features/assets/screens/asset_form_screen.dart:201 - current
if (_suggestedCategory != null) _categorySuggestionChip(),
```

```dart
// mobile_sj/lib/features/auth/screens/forgot_password_screen.dart:188-224 - current (abbreviated)
if (_otpComplete) ...[
  const SizedBox(height: 16),
  TextFormField(
    controller: _passwordCtrl,
    // ...new-password field...
  ),
  PasswordRequirementsList(password: _passwordCtrl.text),
  const SizedBox(height: 16),
  TextFormField(
    controller: _confirmCtrl,
    // ...confirm-password field...
  ),
  const SizedBox(height: 20),
  ElevatedButton(/* Reset Password */),
] else
  const SizedBox(height: 20),
```

```dart
// mobile_sj/lib/shared/widgets/password_requirements.dart:32 - current
if (password.isEmpty) return const SizedBox.shrink();
return Padding(/* ...requirements checklist... */);
```

Every "field appears once you've typed enough" moment in the app (a category suggestion chip, two password fields once an OTP is complete, a requirements checklist once you start typing a password) is a layout jump rather than an animated reveal.

## Target

Wrap each conditional reveal in `AnimatedSize` (which animates a size change smoothly regardless of what's inside, without needing to know the exact height in advance) combined with `AnimatedOpacity` for a fade, using the app's `AppTheme.motionFast` token (160ms. These are small, frequent UI reveals, not modals/drawers, so the fast tier is appropriate per the duration table).

```dart
// mobile_sj/lib/shared/widgets/password_requirements.dart - target
class PasswordRequirementsList extends StatelessWidget {
  final String password;
  const PasswordRequirementsList({super.key, required this.password});

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: AppTheme.motionFast,
      curve: AppTheme.motionCurve,
      alignment: Alignment.topCenter,
      child: password.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: kPasswordRequirements.map((r) {
                  // ...unchanged mapping body...
                }).toList(),
              ),
            ),
    );
  }
}
```

For `asset_form_screen.dart`'s suggestion chip and `forgot_password_screen.dart`'s revealed fields (both inside a `Column`'s `children` list, not a single child), wrap the conditional block in an `AnimatedSize` around a child keyed by presence, e.g.:

```dart
// asset_form_screen.dart - target (replacing the bare conditional list item)
AnimatedSize(
  duration: AppTheme.motionFast,
  curve: AppTheme.motionCurve,
  alignment: Alignment.topCenter,
  child: _suggestedCategory != null ? _categorySuggestionChip() : const SizedBox.shrink(),
),
```

```dart
// forgot_password_screen.dart - target (replacing the if/else block)
AnimatedSize(
  duration: AppTheme.motionFast,
  curve: AppTheme.motionCurve,
  alignment: Alignment.topCenter,
  child: _otpComplete
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            TextFormField(/* ...unchanged new-password field... */),
            PasswordRequirementsList(password: _passwordCtrl.text),
            const SizedBox(height: 16),
            TextFormField(/* ...unchanged confirm-password field... */),
            const SizedBox(height: 20),
            ElevatedButton(/* ...unchanged Reset Password button... */),
          ],
        )
      : const SizedBox(height: 20),
),
```

Note: in `forgot_password_screen.dart`, this `AnimatedSize` block must replace a single list *item* inside the enclosing `Column`'s `children: [...]`, since the current code is itself a spread (`...[...]`) of multiple sibling children when `_otpComplete` is true, it must be collapsed into one child (the inner `Column` shown above) for `AnimatedSize` to wrap it as a single unit. Confirm this restructuring doesn't change the surrounding `Column`'s `crossAxisAlignment`/spacing behavior. The outer enclosing `Column` around this block already uses `crossAxisAlignment: CrossAxisAlignment.stretch` per the file's existing structure; nest that same alignment on the new inner `Column` too (as shown) so `TextFormField`s/buttons still stretch full-width exactly as before.

## Repo conventions to follow

- `AppTheme.motionFast` (160ms) / `AppTheme.motionCurve` (`Curves.easeOutCubic`) are the shared tokens (`mobile_sj/lib/core/theme/app_theme.dart:102-105`). Use them, not hand-typed durations.
- `AnimatedSize`'s `alignment: Alignment.topCenter` ensures new content grows downward from the top (matching how a form naturally reads top-to-bottom) rather than from the center. Use this alignment in all three spots for consistency.

## Steps

1. In `mobile_sj/lib/shared/widgets/password_requirements.dart`, wrap the `if (password.isEmpty) return ...; return Padding(...)` pair in a single `AnimatedSize` as shown in Target. This requires restructuring the early-return into a ternary inside `AnimatedSize`'s `child:` (early returns can't coexist with wrapping the whole method's output in one widget). Keep the `Column`'s `children: kPasswordRequirements.map(...).toList()` mapping logic completely unchanged, just relocate it inside the new structure.

2. In `mobile_sj/lib/features/assets/screens/asset_form_screen.dart`, find the `if (_suggestedCategory != null) _categorySuggestionChip(),` list item (around line 201) and replace it with the `AnimatedSize(...)` wrapper shown in Target. Since this line already sits inside a `Column`'s `children: [...]` list, this is a direct one-line-to-one-widget replacement. No restructuring of siblings needed.

3. In `mobile_sj/lib/features/auth/screens/forgot_password_screen.dart`, find the `if (_otpComplete) ...[ ... ] else const SizedBox(height: 20),` block (around lines 188-225) and replace it with the single `AnimatedSize(...)` widget shown in Target, collapsing the spread children into one inner `Column`.

4. Confirm `AppTheme` is imported in all three files (check existing imports: `password_requirements.dart` and `asset_form_screen.dart` likely already import it for other styling; `forgot_password_screen.dart` should too, given it uses `context.colors` elsewhere per this app's theming convention).

## Boundaries

- Do NOT change any of the actual field validators, controllers, or button `onPressed` logic in any of the three files. Only wrap the reveal/hide transition around unchanged content.
- Do NOT change `kPasswordRequirements`'s definition or the individual requirement-row mapping logic in `password_requirements.dart`. Only the outer show/hide wrapper.
- If restructuring `forgot_password_screen.dart`'s spread-children block into a single inner `Column` changes any spacing behavior you can't reconcile with the alignment note above, STOP and report the discrepancy rather than guessing at a fix.

## Verification

- **Mechanical**: `flutter analyze` (from `mobile_sj/`), clean.
- **Feel check**:
  - On the Add/Edit Asset form, trigger a category suggestion (per whatever mechanism populates `_suggestedCategory`. Check `_categoryDebounce`/`Timer` logic in the same file) and confirm the chip animates in/out smoothly (a brief grow/fade) instead of popping the layout below it downward instantly.
  - On the Forgot Password screen, type a 6-digit code and confirm the new-password fields animate in smoothly rather than snapping into place; clear the code back to fewer digits and confirm they animate back out.
  - Start typing a password anywhere `PasswordRequirementsList` is used (Forgot Password, Reset Password dialog, Change Password screen) and confirm the requirements checklist grows in smoothly, not instantly.
- **Done when**: all three reveal/hide moments animate via `AnimatedSize` (`AppTheme.motionFast`/`motionCurve`) instead of an instant layout jump.
