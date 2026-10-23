# 009 - Push ForceChangePasswordScreen with the app's own transition, not the platform default

- **Status**: TODO
- **Commit**: de894c7
- **Severity**: LOW
- **Category**: Cohesion
- **Estimated scope**: 1 file (`mobile_sj/lib/features/auth/screens/login_screen.dart`)

## Problem

```dart
// mobile_sj/lib/features/auth/screens/login_screen.dart:36-46 - current
if (error is MustChangePasswordRequired) {
  // Not a real auth failure - clear it so it isn't mistaken for one, then
  // hand off to the password-change step.
  ref.read(authProvider.notifier).clearError();
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ForceChangePasswordScreen(
      identifier: identifier,
      currentPassword: password,
    ),
  ));
  return;
}
```

Every other screen transition in this app goes through `fadeThroughPage()` (`mobile_sj/lib/core/router/page_transitions.dart`), used for nearly every `GoRoute` in `mobile_sj/lib/core/router/app_router.dart`. A deliberate, documented choice ("a restrained, consistent motion language across the app rather than per-platform defaults", per the comment at `page_transitions.dart:5-7`). This one push uses a plain `MaterialPageRoute`, which falls back to the platform default (a slide-from-right on iOS, a different Material 3 default on Android). A visible cohesion break right in the middle of the auth flow.

## Target

```dart
// mobile_sj/lib/core/router/page_transitions.dart - target (new function, added alongside fadeThroughPage)
PageRouteBuilder<void> fadeThroughRoute(Widget child) {
  return PageRouteBuilder<void>(
    transitionDuration: AppTheme.motionMedium,
    reverseTransitionDuration: AppTheme.motionFast,
    pageBuilder: (context, animation, secondaryAnimation) => child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: AppTheme.motionCurve);
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

```dart
// mobile_sj/lib/features/auth/screens/login_screen.dart - target
if (error is MustChangePasswordRequired) {
  ref.read(authProvider.notifier).clearError();
  await Navigator.of(context).push(fadeThroughRoute(
    ForceChangePasswordScreen(
      identifier: identifier,
      currentPassword: password,
    ),
  ));
  return;
}
```

`fadeThroughRoute` is the exact same fade+2%-upward-slide transition as `fadeThroughPage`, just packaged as a plain `PageRouteBuilder` (for `Navigator.push`) instead of a `CustomTransitionPage` (for `GoRoute`'s `pageBuilder`), go_router's `CustomTransitionPage` can't be used with a bare `Navigator.push`, so this is a second, small function sharing the exact same `transitionsBuilder` logic, not a duplicate design.

## Repo conventions to follow

- Reuse `AppTheme.motionMedium`/`motionFast`/`motionCurve` (`mobile_sj/lib/core/theme/app_theme.dart:102-105`). Do not hand-type new duration/curve values.
- `fadeThroughPage`'s exact `transitionsBuilder` body (`mobile_sj/lib/core/router/page_transitions.dart:14-22`) is the source of truth to copy from. The two functions' `transitionsBuilder` closures should be identical.

## Steps

1. In `mobile_sj/lib/core/router/page_transitions.dart`, add the new `fadeThroughRoute` function shown in Target, placed after the existing `fadeThroughPage` function in the same file. Copy the `transitionsBuilder` logic verbatim from `fadeThroughPage` (lines 14-22) rather than retyping it, to guarantee they stay identical.

2. In `mobile_sj/lib/features/auth/screens/login_screen.dart`, add the import `import '../../../core/router/page_transitions.dart';` (check it isn't already imported under a different alias first).

3. Replace the `Navigator.of(context).push(MaterialPageRoute(builder: (_) => ForceChangePasswordScreen(...)))` call with `Navigator.of(context).push(fadeThroughRoute(ForceChangePasswordScreen(identifier: identifier, currentPassword: password)))` exactly as shown in Target.

## Boundaries

- Do NOT modify `ForceChangePasswordScreen` itself, `app_router.dart`, or `fadeThroughPage`. Only add the new sibling function and change the one call site.
- Do NOT register `ForceChangePasswordScreen` as a `GoRoute`. It's deliberately a one-off `Navigator.push` (not a deep-linkable, bookmarkable location, since it only exists mid-login-attempt), and this plan preserves that; it only fixes the *transition*, not the navigation mechanism.

## Verification

- **Mechanical**: `flutter analyze` (from `mobile_sj/`), clean, no unused-import warnings.
- **Feel check**: log in with an account that has `mustChangePassword: true` set (or trigger the flow via an admin-reset test account) and confirm the "Set a New Password" screen now fades/slides in with the same subtle upward motion as every other screen transition in the app (compare directly against, e.g., navigating from Dashboard to Assets), not the platform's default slide-from-edge.
- **Done when**: `ForceChangePasswordScreen`'s entrance uses `AppTheme.motionMedium`/`motionCurve` via the new `fadeThroughRoute`, visually indistinguishable in timing/feel from any `GoRoute`-based transition elsewhere in the app.
