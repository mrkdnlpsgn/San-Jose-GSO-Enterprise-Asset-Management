import 'package:flutter/material.dart';
/// Theme-aware neutrals. Registered as a [ThemeExtension] so every screen that
/// reads them via `context.colors.X` rebuilds automatically when the theme
/// changes — a plain static constant can't do that, since Dart consts are
/// fixed at compile time.
class AppColors extends ThemeExtension<AppColors> {
  final Color bg;
  final Color surface;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  const AppColors({
    required this.bg,
    required this.surface,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
  });

  // Dark palette — unchanged from the app's original (and only) theme.
  // white70 ≈ 9.7:1, white54 ≈ 6.1:1 against bg (#09090B); both clear WCAG AA.
  static const dark = AppColors(
    bg: Color(0xFF09090B),
    surface: Color(0xFF18181B),
    border: Color(0xFF27272A),
    textPrimary: Colors.white,
    textSecondary: Colors.white70,
    textTertiary: Colors.white54,
  );

  // Light palette — mirrors the web app's DESIGN.md tokens exactly (Paper White,
  // Ink Slate, Slate Border) so both clients agree on what "light mode" means.
  // slate-700 ≈ 12.6:1, slate-500 ≈ 4.76:1 against white; both clear WCAG AA
  // (slate-500 is the same shade the web app's login page was fixed to use).
  static const light = AppColors(
    bg: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFE2E8F0),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF334155),
    textTertiary: Color(0xFF64748B),
  );

  @override
  AppColors copyWith({
    Color? bg,
    Color? surface,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
    );
  }
}

/// Shorthand for `Theme.of(context).extension<AppColors>()!`.
extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

class AppTheme {
  // Brand identity — the same across both themes, per DESIGN.md's "One Desk Rule".
  static const Color brand = Color(0xFF1FAD55);     // matches web brand-500
  static const Color brandDark = Color(0xFF178A44);
  static const Color brandButton = Color(0xFF126E36); // matches web's Seal Green Deep — passes WCAG AA (6.3:1) with white text on either theme; `brand` alone is ~2.9:1 and fails

  // Lifecycle status colors — mirrors web, unchanged across themes (used inside
  // tinted 15%-alpha badges, not as full-bleed fills, so they read fine on light or dark).
  static const Color statusAssigned = Color(0xFF3B82F6);       // blue
  static const Color statusMaintenance = Color(0xFFF59E0B);    // amber
  static const Color statusDisposed = Color(0xFFEF4444);       // red
  static const Color statusTransferred = Color(0xFF60A5FA);    // blue-400
  static const Color statusRegistered = Color(0xFF6B7280);     // gray

  // Motion tokens — restrained, functional timings (not playful/bouncy) so
  // transitions read as "responsive UI", matching an enterprise system's tone.
  static const Duration motionFast = Duration(milliseconds: 160);
  static const Duration motionMedium = Duration(milliseconds: 260);
  static const Duration motionSlow = Duration(milliseconds: 420);
  static const Curve motionCurve = Cubic(0.23, 1, 0.32, 1);

  static ThemeData _themeFor(AppColors colors, Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: colors.bg,
      extensions: [colors],
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: brand,
        onPrimary: Colors.white,
        secondary: brand,
        onSecondary: Colors.white,
        surface: colors.surface,
        onSurface: colors.textPrimary,
        error: Colors.red,
        onError: Colors.white,
        outline: colors.border,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: brand, width: 1.5),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: Colors.red),
        ),
        labelStyle: TextStyle(color: colors.textTertiary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandButton,
          foregroundColor: Colors.white,
          disabledBackgroundColor: brandButton.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: colors.border, thickness: 1),
      listTileTheme: ListTileThemeData(
        tileColor: colors.surface,
        iconColor: colors.textTertiary,
      ),
      navigationBarTheme: NavigationBarThemeData(
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? brand : colors.textTertiary,
              size: 24,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
              color: states.contains(WidgetState.selected) ? brand : colors.textSecondary,
            )),
      ),
    );
  }

  static ThemeData get dark => _themeFor(AppColors.dark, Brightness.dark);
  static ThemeData get light => _themeFor(AppColors.light, Brightness.light);
}

/// Reflects the OS-level "Reduce Motion" accessibility setting. Reduced motion
/// means fewer/gentler animations, not zero — consumers should drop
/// position-based movement (slides, staggers) while keeping opacity fades.
extension ReducedMotionX on BuildContext {
  bool get prefersReducedMotion => MediaQuery.of(this).disableAnimations;
}
