import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import 'ios_touch.dart';

/// Height of the bottom bar's content (excludes the safe-area inset).
const double kMainShellBarHeight = 60;

/// How far a shell tab's scrollable content needs to pad its bottom so the
/// last item clears the bottom bar instead of sitting behind it -
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
  _Tab(Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
];
const _scanIndex = 2;

/// iOS tab bar: a translucent, frosted strip - the content scrolls underneath and blurs
/// through it - with a hairline top edge, glyph + small label, the selected tab in the
/// tint colour (no pill). Scan, the main thing people do in the field, is eGovPH's raised
/// round button sitting on the bar's top edge, under the thumb.
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
    // iOS "chrome" material: near-opaque so labels stay legible over busy content
    final material = context.isLight ? const Color(0xF0F9F9F9) : const Color(0xE6161618);
    return Scaffold(
      // Tabs pad their own bottom with mainShellBottomInset, so the bar can sit over the body.
      extendBody: true,
      body: navigationShell,
      // The scan circle rises above the bar, but the frosted blur must be clipped to the bar
      // itself - so the circle is its own layer on top. The strip above the bar is see-through
      // and lets taps fall through to the page (only the circle catches them).
      bottomNavigationBar: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: _scanRise),
            child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: material,
              border: Border(top: BorderSide(color: c.border, width: 0.5)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: kMainShellBarHeight,
                child: Row(
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
        ),
      ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: _ScanCircle(selected: current == _scanIndex, ring: material, onTap: () => _go(_scanIndex)),
            ),
          ),
        ],
      ),
    );
  }
}

const _inactive = Color(0xFF8E8E93); // iOS systemGray - unselected tab items

class _TabButton extends StatelessWidget {
  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;
  const _TabButton({required this.tab, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? context.brandAccent : _inactive;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? tab.selectedIcon : tab.icon, size: 27, color: color),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                tab.label,
                maxLines: 1,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, letterSpacing: 0.1, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How far the scan circle rises above the bar's top edge.
const double _scanRise = 20;
const double _scanSize = 60;

/// The label under the raised circle; also tappable, so the whole Scan slot works.
class _ScanButton extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  const _ScanButton({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Scan QR code',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Scan',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
                color: selected ? context.brandAccent : context.colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// eGovPH-style raised button: a solid green circle with a ring in the bar's own colour,
/// so it looks set into the bar, and a soft shadow. Shrinks on touch-down.
class _ScanCircle extends StatelessWidget {
  final bool selected;
  final Color ring;
  final VoidCallback onTap;
  const _ScanCircle({required this.selected, required this.ring, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Scan QR code',
      excludeSemantics: true,
      child: PressScale(
        scale: 0.92,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: _scanSize,
            height: _scanSize,
            decoration: BoxDecoration(
              color: AppTheme.brandButton,
              shape: BoxShape.circle,
              border: Border.all(color: Color.alphaBlend(ring, context.colors.bg), width: 4),
              boxShadow: [
                BoxShadow(color: AppTheme.brandButton.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4)),
              ],
            ),
            child: const Icon(Icons.qr_code_scanner_rounded, size: 27, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
