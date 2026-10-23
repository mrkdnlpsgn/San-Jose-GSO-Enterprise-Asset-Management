# 013 - Add haptic feedback to destructive/security-sensitive confirmations

- **Status**: TODO
- **Commit**: de894c7
- **Severity**: LOW-MEDIUM
- **Category**: Missed opportunity (multimodal feedback)
- **Estimated scope**: 2 files (`mobile_sj/lib/shared/widgets/delete_dialog.dart`, `mobile_sj/lib/features/accounts/widgets/reset_password_dialog.dart`)

## Problem

Earlier this session, `mobile_sj/lib/features/qr_scanner/screens/qr_scanner_screen.dart` was fixed to call `HapticFeedback.mediumImpact()`/`.lightImpact()` on scan success/not-found, closing the loop on a "meaningful moment" per the Apple fluid-interface multimodal-feedback principle (causality: trigger feedback on the actual causal event; utility: reserve it for moments that matter). Two other genuinely impactful actions in the app still get zero physical feedback, identical in feel to a plain Cancel button:

```dart
// mobile_sj/lib/shared/widgets/delete_dialog.dart:58-64 - current
TextButton(
  onPressed: () {
    if (widget.requireReason && _ctrl.text.trim().isEmpty) return;
    Navigator.pop(context, widget.requireReason ? _ctrl.text.trim() : 'deleted');
  },
  child: const Text('Delete', style: TextStyle(color: Colors.red)),
),
```

```dart
// mobile_sj/lib/features/accounts/widgets/reset_password_dialog.dart:33-43 - current
void _submit() {
  if (!passwordMeetsRequirements(_passwordCtrl.text)) {
    setState(() => _error = 'Password does not meet the requirements below.');
    return;
  }
  if (_passwordCtrl.text != _confirmCtrl.text) {
    setState(() => _error = 'Passwords do not match.');
    return;
  }
  Navigator.pop(context, _passwordCtrl.text);
}
```

Both are irreversible/impactful actions (a permanent delete, a forced password reset that also clears failed-login lockout state), exactly the "meaningful moment" AUDIT.md's spirit (translated from the web-focused audit categories to this session's Apple-fluid-interface work) calls out for physical feedback, and the app is now inconsistent about which impactful actions get it.

## Target

```dart
// mobile_sj/lib/shared/widgets/delete_dialog.dart - target
TextButton(
  onPressed: () {
    if (widget.requireReason && _ctrl.text.trim().isEmpty) return;
    HapticFeedback.mediumImpact();
    Navigator.pop(context, widget.requireReason ? _ctrl.text.trim() : 'deleted');
  },
  child: const Text('Delete', style: TextStyle(color: Colors.red)),
),
```

```dart
// mobile_sj/lib/features/accounts/widgets/reset_password_dialog.dart - target
void _submit() {
  if (!passwordMeetsRequirements(_passwordCtrl.text)) {
    setState(() => _error = 'Password does not meet the requirements below.');
    return;
  }
  if (_passwordCtrl.text != _confirmCtrl.text) {
    setState(() => _error = 'Passwords do not match.');
    return;
  }
  HapticFeedback.mediumImpact();
  Navigator.pop(context, _passwordCtrl.text);
}
```

`HapticFeedback.mediumImpact()`, matching the exact call used for the QR scanner's success case (`qr_scanner_screen.dart`), fires only after validation passes, on the actual causal moment (the confirm action committing), not on every button tap.

## Repo conventions to follow

- `HapticFeedback.mediumImpact()` is already the app's precedent for "this confirmed/succeeded" feedback (added to `qr_scanner_screen.dart` this session), reuse the exact same call, do not introduce `.heavyImpact()` or `.vibrate()` without a specific reason.
- Import as `import 'package:flutter/services.dart' show HapticFeedback;`, matching exactly how `qr_scanner_screen.dart` imports it (check that file's import list as the exemplar).

## Steps

1. In `mobile_sj/lib/shared/widgets/delete_dialog.dart`, add the import `import 'package:flutter/services.dart' show HapticFeedback;` at the top (alongside the existing `import 'package:flutter/material.dart';`). Add `HapticFeedback.mediumImpact();` as the first statement inside the Delete button's `onPressed`, after the existing `if (widget.requireReason && _ctrl.text.trim().isEmpty) return;` guard (so it only fires when the delete will actually proceed, not when validation blocks it).

2. In `mobile_sj/lib/features/accounts/widgets/reset_password_dialog.dart`, add the same import. Add `HapticFeedback.mediumImpact();` inside `_submit()`, after both validation checks (`passwordMeetsRequirements` and the passwords-match check) and immediately before `Navigator.pop(context, _passwordCtrl.text);`.

## Boundaries

- Do NOT add haptic feedback to the Cancel buttons in either dialog. Only the destructive/confirming action.
- Do NOT add haptics to any other dialog not explicitly named in this plan (e.g. `ConfirmDialog`-equivalents elsewhere), if you notice other candidates while making this change, report them as a follow-up finding rather than expanding scope.
- Do NOT change either dialog's validation logic, text, or layout. Only add the one `HapticFeedback` call plus its import in each file.

## Verification

- **Mechanical**: `flutter analyze` (from `mobile_sj/`), clean.
- **Feel check** (requires a physical device or simulator with haptics support: Flutter's haptic feedback typically doesn't fire in a desktop/web debug run):
  - Trigger a delete confirmation (e.g. delete an asset) and tap Delete, confirm a distinct haptic tap fires at the moment of confirming, not before.
  - Trigger a password reset from the Accounts screen and submit a valid new password, confirm the same haptic fires on successful submission, and does NOT fire if validation blocks the submit (e.g. submit a too-weak password first and confirm no haptic until a valid one is entered).
- **Done when**: both destructive/security-sensitive confirmations fire `HapticFeedback.mediumImpact()` exactly once, only on a successful confirm.
