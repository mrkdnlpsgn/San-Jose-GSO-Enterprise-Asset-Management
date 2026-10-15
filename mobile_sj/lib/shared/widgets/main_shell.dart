import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';

/// Height of the bottom bar's content (excludes the safe-area inset).
const double kMainShellBarHeight = 72;

/// How far a shell tab's scrollable content needs to pad its bottom so the
/// last item clears the bottom bar instead of sitting behind it —
/// [MainShell] uses `extendBody`, so each tab's own body is responsible for
/// its own clearance under the bar.
extension MainShellClearanceX on BuildContext {
  double get mainShellBottomInset => kMainShellBarHeight + MediaQuery.of(this).padding.bottom;
}

class _Tab {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _Tab(this.icon, this.selectedIcon, this.label);
}

// Branch order must match the StatefulShellRoute branches in app_router.dart.
const _tabs = [
  _Tab(Icons.home_outlined, Icons.home_rounded, 'Home'),
  _Tab(Icons.inventory_2_outlined, Icons.inventory_2_rounded, 'Assets'),
  _Tab(Icons.qr_code_scanner_rounded, Icons.qr_code_scanner_rounded, 'Scan'),
  _Tab(Icons.history_rounded, Icons.history_rounded, 'History'),
  _Tab(Icons.person_outline_rounded, Icons.person_rounded, 'Account'),
];
const _scanIndex = 2;

/// Bottom bar for the five most-used destinations, eGovPH-style: Scan — the main
/// thing people do with the app in the field — is a raised round button in the middle,
/// under the thumb. Plain white bar with a hairline on top; no blur or translucency.
class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  void _go(int index) => navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final current = navigationShell.currentIndex;
    return Scaffold(
      // Tabs pad their own bottom with mainShellBottomInset, so the bar can sit over the body.
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: kMainShellBarHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: i == _scanIndex
                        ? _ScanButton(selected: current == i, onTap: () => _go(i))
                        : _TabButton(tab: _tabs[i], selected: current == i, onTap: () => _go(i)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;
  const _TabButton({required this.tab, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? context.brandAccent : context.colors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: AppTheme.motionFast,
              width: 56,
              height: 30,
              decoration: BoxDecoration(
                color: selected
                    ? (context.isLight ? AppTheme.brandTint : AppTheme.brand.withValues(alpha: 0.18))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(selected ? tab.selectedIcon : tab.icon, size: 25, color: color),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                tab.label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The raised centre button. Overflows the bar's top edge a little, like eGovPH's
/// Digital ID button — a solid green circle with a white ring, no glow.
class _ScanButton extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  const _ScanButton({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Scan QR code',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        // the circle is positioned to stick out above the bar without changing its height
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Positioned(
              top: -18,
              child: Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: AppTheme.brandButton,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.surface, width: 4),
                ),
                child: const Icon(Icons.qr_code_scanner_rounded, size: 28, color: Colors.white),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 10,
              child: Text(
                'Scan',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? context.brandAccent : c.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
