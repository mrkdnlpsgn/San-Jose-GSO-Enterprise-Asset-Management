import 'package:flutter/cupertino.dart'
    show CupertinoSliverNavigationBar, CupertinoTextThemeData, CupertinoTheme, CupertinoThemeData;
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// iOS tab-root page: a large bold title that shrinks into a centred title in a frosted bar
/// as the content scrolls, with an optional [bottom] (search, filters, tabs) pinned under it.
///
/// The [body]'s scroll view must not have its own ScrollController — it rides the
/// NestedScrollView's, which is what lets scrolling the list collapse the title.
class LargeTitleScaffold extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final PreferredSizeWidget? bottom;
  final Widget body;

  const LargeTitleScaffold({super.key, required this.title, required this.body, this.trailing, this.bottom});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final titleFont = TextStyle(fontFamily: AppTheme.fontFamily, color: c.textPrimary, inherit: false);
    // translucent → the bar frosts whatever slides under it
    final barColor = c.bg.withValues(alpha: 0.86);

    return CupertinoTheme(
      data: CupertinoThemeData(
        brightness: context.isLight ? Brightness.light : Brightness.dark,
        primaryColor: context.brandAccent,
        textTheme: CupertinoTextThemeData(
          navLargeTitleTextStyle: titleFont.copyWith(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.9),
          navTitleTextStyle: titleFont.copyWith(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3),
        ),
      ),
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            CupertinoSliverNavigationBar(
              largeTitle: Text(title),
              trailing: trailing == null ? null : Material(type: MaterialType.transparency, child: trailing),
              automaticallyImplyLeading: false,
              transitionBetweenRoutes: false, // the app's own page transitions handle this
              backgroundColor: barColor,
              // the hairline belongs under the pinned bottom when there is one
              border: bottom == null ? Border(bottom: BorderSide(color: c.border, width: 0.5)) : null,
            ),
            if (bottom != null)
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedBottom(bottom!, c.bg, c.border),
              ),
          ],
          body: body,
        ),
      ),
    );
  }
}

class _PinnedBottom extends SliverPersistentHeaderDelegate {
  final PreferredSizeWidget child;
  final Color background;
  final Color hairline;
  _PinnedBottom(this.child, this.background, this.hairline);

  double get _h => child.preferredSize.height;

  @override
  double get minExtent => _h;
  @override
  double get maxExtent => _h;

  // A pinned header must paint exactly its declared extent, so the content is forced to that
  // height — and clipped rather than erroring if a large text size makes it taller.
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => SizedBox.expand(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            // hairline only once the list is actually sliding under it, like iOS scroll-edge
            border: overlapsContent ? Border(bottom: BorderSide(color: hairline, width: 0.5)) : null,
          ),
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: 0,
              maxHeight: double.infinity,
              child: Material(type: MaterialType.transparency, child: child),
            ),
          ),
        ),
      );

  @override
  bool shouldRebuild(_PinnedBottom old) => old.child != child || old.background != background || old.hairline != hairline;
}
