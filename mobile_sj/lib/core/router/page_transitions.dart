import 'package:flutter/cupertino.dart' show CupertinoPage, CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

/// Every route's page. iOS push - slides in from the right over a parallax-shifted
/// previous page, and can be dismissed by swiping from the left edge, following the finger
/// 1:1. With the phone's Reduce Motion on, a plain cross-fade instead (no sliding).
/// (Named for the fade it used to be; callers didn't need to change.)
Page<void> fadeThroughPage(BuildContext context, GoRouterState state, Widget child) {
  if (context.prefersReducedMotion) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: AppTheme.motionFast,
      reverseTransitionDuration: AppTheme.motionFast,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }
  return CupertinoPage<void>(key: state.pageKey, child: child);
}

/// Same, for a plain `Navigator.push` (a one-off screen mid-flow that isn't a go_router route).
PageRoute<void> fadeThroughRoute(Widget child) => CupertinoPageRoute<void>(builder: (_) => child);
