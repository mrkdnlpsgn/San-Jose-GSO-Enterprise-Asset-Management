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
  /// Headings and the app bar title — the web app's official-document navy (gov-700) in light mode.
  final Color heading;
  /// Quiet fill for section headers, label/value rows and read-only fields (slate-100 / zinc-950).
  final Color subtle;

  const AppColors({
    required this.bg,
    required this.surface,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.heading,
    required this.subtle,
  });

  // white70 ≈ 9.7:1, white54 ≈ 6.1:1 against bg (#09090B); both clear WCAG AA.
  static const dark = AppColors(
    bg: Color(0xFF09090B),
    surface: Color(0xFF18181B),
    border: Color(0xFF27272A),
    textPrimary: Colors.white,
    textSecondary: Colors.white70,
    textTertiary: Colors.white54,
    heading: Colors.white,
    subtle: Color(0xFF111113),
  );

  // Mirrors the web app's light mode: white bordered cards on a faint slate page,
  // navy headings, slate text. slate-700 ≈ 12.6:1, slate-500 ≈ 4.76:1 against white.
  static const light = AppColors(
    bg: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFE2E8F0),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF334155),
    textTertiary: Color(0xFF64748B),
    heading: AppTheme.gov,
    subtle: Color(0xFFF1F5F9),
  );

  @override
  AppColors copyWith({
    Color? bg,
    Color? surface,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? heading,
    Color? subtle,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      heading: heading ?? this.heading,
      subtle: subtle ?? this.subtle,
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
      heading: Color.lerp(heading, other.heading, t)!,
      subtle: Color.lerp(subtle, other.subtle, t)!,
    );
  }
}

/// Shorthand for `Theme.of(context).extension<AppColors>()!`.
extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  bool get isLight => Theme.of(this).brightness == Brightness.light;
  /// Green for links, icons and active states: the deep shade on white (AA), the bright one on dark.
  Color get brandAccent => isLight ? AppTheme.brandButton : AppTheme.brand;
}

class AppTheme {
  static const String fontFamily = 'Inter';   // same typeface as the web app

  // Brand identity — the same across both themes, per DESIGN.md's "One Desk Rule".
  static const Color brand = Color(0xFF1FAD55);       // web brand-500
  static const Color brandDark = Color(0xFF178A44);
  static const Color brandButton = Color(0xFF126E36); // web brand-700 — 6.3:1 with white text
  static const Color brandTint = Color(0xFFEDFCF2);   // web brand-50
  // Official-document navy (web gov-700) — headings and structure, never buttons.
  static const Color gov = Color(0xFF1C3355);

  // Lifecycle status colors — the same mapping as the web app's asset drawer.
  static const Color statusRegistered = Color(0xFF3B82F6);     // blue
  static const Color statusAssigned = Color(0xFF10B981);       // emerald
  static const Color statusTransferred = Color(0xFFF97316);    // orange
  static const Color statusMaintenance = Color(0xFFF59E0B);    // amber
  static const Color statusDisposed = Color(0xFFEF4444);       // red
  static const Color statusArchived = Color(0xFF71717A);       // zinc
  /// Neutral blue for non-lifecycle meanings (Monitor, Preventive, Approved, Staff role).
  static const Color info = Color(0xFF3B82F6);

  // Motion tokens — restrained, functional timings (not playful/bouncy) so
  // transitions read as "responsive UI", matching an enterprise system's tone.
  static const Duration motionFast = Duration(milliseconds: 160);
  static const Duration motionMedium = Duration(milliseconds: 260);
  static const Duration motionSlow = Duration(milliseconds: 420);
  static const Curve motionCurve = Cubic(0.23, 1, 0.32, 1);

  static ThemeData _themeFor(AppColors colors, Brightness brightness) {
    final light = brightness == Brightness.light;
    final accent = light ? brandButton : brand;
    final inputBorder = light ? const Color(0xFFCBD5E1) : colors.border;   // slate-300: visible field edges
    final base = ThemeData(useMaterial3: true, brightness: brightness, fontFamily: fontFamily);
    // Slightly larger body text than Material's default — many users are older staff.
    final text = base.textTheme
        .copyWith(
          bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.45),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 15, height: 1.45),
          bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 13, height: 1.4),
        )
        .apply(bodyColor: colors.textPrimary, displayColor: colors.heading);

    return base.copyWith(
      scaffoldBackgroundColor: colors.bg,
      extensions: [colors],
      textTheme: text.copyWith(
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: colors.heading),
        // also the text inside dropdown fields — plain field text, not a heading
        titleMedium: text.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w500, color: colors.textPrimary),
        headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: colors.heading),
      ),
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: accent,
        onPrimary: Colors.white,
        secondary: brand,
        onSecondary: Colors.white,
        surface: colors.surface,
        onSurface: colors.textPrimary,
        error: const Color(0xFFDC2626),
        onError: Colors.white,
        outline: colors.border,
      ),
      // Flat white top bar with a hairline under it and a navy title — the web app's header.
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.heading,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        shape: Border(bottom: BorderSide(color: colors.border)),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: colors.heading,
          fontSize: 19,
          fontWeight: FontWeight.w700,
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: brand, width: 2),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: Color(0xFFDC2626)),
        ),
        // Labels always sit on the field's top edge, never inside it as a placeholder that
        // vanishes on tap — the web forms keep their labels visible above every field.
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: TextStyle(color: colors.textSecondary, fontSize: 16, fontWeight: FontWeight.w600),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith((s) => TextStyle(
              fontFamily: fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: s.contains(WidgetState.error)
                  ? const Color(0xFFDC2626)
                  : s.contains(WidgetState.focused)
                      ? accent
                      : colors.textSecondary,
            )),
        hintStyle: TextStyle(color: colors.textTertiary, fontSize: 15),
        helperStyle: TextStyle(color: colors.textTertiary, fontSize: 13),
        errorStyle: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandButton,
          foregroundColor: Colors.white,
          disabledBackgroundColor: brandButton.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white70,
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
          textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brandButton,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          minimumSize: const Size(64, 48),
          side: BorderSide(color: inputBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size(48, 44),
          textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      // Filter chips: white pill with a border; selected = solid navy, like the web app's filter row.
      chipTheme: ChipThemeData(
        backgroundColor: colors.surface,
        selectedColor: light ? gov : Colors.white,
        side: BorderSide(color: inputBorder),
        shape: const StadiumBorder(),
        showCheckmark: false,
        // Chip resolves a WidgetStateColor inside labelStyle per state (a WidgetStateTextStyle
        // isn't, which left unselected labels white-on-white).
        labelStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: WidgetStateColor.resolveWith((states) => states.contains(WidgetState.selected)
              ? (light ? Colors.white : Colors.black)
              : colors.textSecondary),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      ),
      // Segmented choices (Settings → Theme / Text size): selected = solid navy, like the filter chips.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
          side: WidgetStatePropertyAll(BorderSide(color: inputBorder)),
          backgroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? (light ? gov : Colors.white) : colors.surface),
          foregroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? (light ? Colors.white : Colors.black) : colors.textPrimary),
          iconColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? (light ? Colors.white : Colors.black) : colors.textSecondary),
          textStyle: const WidgetStatePropertyAll(
              TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      ),
      dividerTheme: DividerThemeData(color: colors.border, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        tileColor: colors.surface,
        iconColor: colors.textTertiary,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        titleTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 19, fontWeight: FontWeight.w700, color: colors.heading),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: light ? gov : const Color(0xFF27272A),
        contentTextStyle: const TextStyle(fontFamily: fontFamily, fontSize: 15, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: brand),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 72,
        indicatorColor: light ? brandTint : brand.withValues(alpha: 0.18),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? accent : colors.textTertiary,
              size: 26,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontFamily: fontFamily,
              fontSize: 13,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              color: states.contains(WidgetState.selected) ? accent : colors.textSecondary,
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
