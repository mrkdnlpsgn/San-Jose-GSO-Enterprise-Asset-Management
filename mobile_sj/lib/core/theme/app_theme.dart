import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
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
  /// Headings and the app bar title.
  final Color heading;
  /// Quiet fill for section headers, label/value rows and read-only fields.
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

  // iOS dark grouped palette: black page, #1C1C1E sections, #38383A separators.
  // white70 ≈ 13:1, white54 ≈ 8:1 on black; both clear WCAG AA.
  static const dark = AppColors(
    bg: Color(0xFF000000),
    surface: Color(0xFF1C1C1E),
    border: Color(0xFF38383A),
    textPrimary: Colors.white,
    textSecondary: Colors.white70,
    textTertiary: Colors.white54,
    heading: Colors.white,
    subtle: Color(0xFF2C2C2E),
  );

  // iOS light grouped palette: systemGroupedBackground page, white sections, opaque
  // separator, and label / secondaryLabel / tertiaryLabel made opaque so contrast is exact
  // (#6E6E73 ≈ 4.6:1 on the grey page, 5.1:1 on white).
  static const light = AppColors(
    bg: Color(0xFFF2F2F7),
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFE5E5EA),
    textPrimary: Color(0xFF000000),
    textSecondary: Color(0xFF3C3C43),
    textTertiary: Color(0xFF6E6E73),
    heading: Color(0xFF000000),
    subtle: Color(0xFFF2F2F7),
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

  // Brand identity — the app's tint colour (iOS apps keep their own accent).
  static const Color brand = Color(0xFF1FAD55);       // web brand-500
  static const Color brandDark = Color(0xFF178A44);
  static const Color brandButton = Color(0xFF126E36); // web brand-700 — 6.3:1 with white text
  static const Color brandTint = Color(0xFFEDFCF2);   // web brand-50
  // Official-document navy (web gov-700).
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

  // Motion tokens.
  static const Duration motionFast = Duration(milliseconds: 160);
  static const Duration motionMedium = Duration(milliseconds: 260);
  static const Duration motionSlow = Duration(milliseconds: 420);
  static const Curve motionCurve = Cubic(0.23, 1, 0.32, 1);

  static ThemeData _themeFor(AppColors colors, Brightness brightness) {
    final light = brightness == Brightness.light;
    final accent = light ? brandButton : brand;
    // iOS fill for fields, chips and the grey segmented track (tertiarySystemFill made opaque) —
    // visible both on the grey page and inside white sections.
    final fill = light ? const Color(0xFFE9E9EE) : const Color(0xFF2C2C2E);
    // hairline edge for form fields (iOS opaqueSeparator-ish, a touch stronger for older eyes)
    final fieldEdge = light ? const Color(0xFFD1D1D6) : const Color(0xFF3A3A3C);
    const red = Color(0xFFFF3B30);
    final base = ThemeData(useMaterial3: true, brightness: brightness, fontFamily: fontFamily);
    // Slightly larger body text than Material's default — many users are older staff.
    final text = base.textTheme
        .copyWith(
          bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 17, height: 1.4, letterSpacing: -0.2),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 15, height: 1.45, letterSpacing: -0.1),
          bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 13, height: 1.4),
        )
        .apply(bodyColor: colors.textPrimary, displayColor: colors.heading);
    final r10 = BorderRadius.circular(10);
    final r12 = BorderRadius.circular(12);
    const ios = CupertinoPageTransitionsBuilder();

    return base.copyWith(
      scaffoldBackgroundColor: colors.bg,
      extensions: [colors],
      // iOS push: slide in from the right with parallax; swipe from the left edge to go back.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: ios,
        TargetPlatform.iOS: ios,
        TargetPlatform.windows: ios,
        TargetPlatform.macOS: ios,
        TargetPlatform.linux: ios,
      }),
      textTheme: text.copyWith(
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4, color: colors.heading),
        // also the text inside dropdown fields — plain field text, not a heading
        titleMedium: text.titleMedium
            ?.copyWith(fontSize: 17, fontWeight: FontWeight.w400, letterSpacing: -0.2, color: colors.textPrimary),
        headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5, color: colors.heading),
      ),
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: accent,
        onPrimary: Colors.white,
        secondary: brand,
        onSecondary: Colors.white,
        surface: colors.surface,
        onSurface: colors.textPrimary,
        error: red,
        onError: Colors.white,
        outline: colors.border,
      ),
      // iOS navigation bar: grouped grey, centred 17pt semibold title, ‹ back chevron in the tint.
      appBarTheme: AppBarTheme(
        backgroundColor: colors.bg,
        foregroundColor: colors.textPrimary,
        iconTheme: IconThemeData(color: accent),
        actionsIconTheme: IconThemeData(color: accent),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: colors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
      ),
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (_) => const Icon(Icons.arrow_back_ios_new_rounded, size: 21),
      ),
      // inset grouped section: white, borderless, rounded
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      // iOS grouped-form field: a white row on the grey page (dark: #1C1C1E on black), with a
      // faint hairline so it still reads inside white cards; a tint ring while focused (kept
      // for accessibility — older staff need to see which field they're typing in).
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        border: OutlineInputBorder(borderRadius: r10, borderSide: BorderSide(color: fieldEdge, width: 0.8)),
        enabledBorder: OutlineInputBorder(borderRadius: r10, borderSide: BorderSide(color: fieldEdge, width: 0.8)),
        disabledBorder: OutlineInputBorder(borderRadius: r10, borderSide: BorderSide(color: colors.border, width: 0.8)),
        focusedBorder: OutlineInputBorder(borderRadius: r10, borderSide: BorderSide(color: accent, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: r10, borderSide: const BorderSide(color: red)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: r10, borderSide: const BorderSide(color: red, width: 1.5)),
        // Labels always sit above the value, never a placeholder that vanishes on tap.
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: TextStyle(color: colors.textSecondary, fontSize: 16, fontWeight: FontWeight.w600),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith((s) => TextStyle(
              fontFamily: fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: s.contains(WidgetState.error)
                  ? red
                  : s.contains(WidgetState.focused)
                      ? accent
                      : colors.textSecondary,
            )),
        hintStyle: TextStyle(color: colors.textTertiary, fontSize: 16),
        helperStyle: TextStyle(color: colors.textTertiary, fontSize: 13),
        errorStyle: const TextStyle(color: red, fontSize: 13),
        prefixIconColor: colors.textTertiary,
        suffixIconColor: colors.textTertiary,
      ),
      // iOS filled button: large, 12pt corners, semibold label
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandButton,
          foregroundColor: Colors.white,
          disabledBackgroundColor: fill,
          disabledForegroundColor: colors.textTertiary,
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: r12),
          elevation: 0,
          textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brandButton,
          foregroundColor: Colors.white,
          disabledBackgroundColor: fill,
          disabledForegroundColor: colors.textTertiary,
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: r12),
          textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        ),
      ),
      // iOS "tinted" button: soft tint fill, tint-coloured label, no outline
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          backgroundColor: accent.withValues(alpha: light ? 0.10 : 0.18),
          minimumSize: const Size(64, 48),
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: r12),
          textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size(48, 44),
          textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: -0.2),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: brandButton,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      // Filter chips: grey capsules; selected = solid tint (white text at 6.3:1).
      chipTheme: ChipThemeData(
        backgroundColor: fill,
        selectedColor: brandButton,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        showCheckmark: false,
        // Chip resolves a WidgetStateColor inside labelStyle per state (a WidgetStateTextStyle
        // isn't, which left unselected labels white-on-white).
        labelStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          color: WidgetStateColor.resolveWith((states) =>
              states.contains(WidgetState.selected) ? Colors.white : colors.textPrimary),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      ),
      // iOS segmented control: grey track, the chosen segment a raised white thumb.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
          side: WidgetStatePropertyAll(BorderSide(color: fill, width: 2)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
          backgroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? (light ? Colors.white : const Color(0xFF636366)) : fill),
          foregroundColor: WidgetStatePropertyAll(colors.textPrimary),
          iconColor: WidgetStatePropertyAll(colors.textPrimary),
          textStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
                fontFamily: fontFamily,
                fontSize: 15,
                fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: -0.2,
              )),
        ),
      ),
      dividerTheme: DividerThemeData(color: colors.border, thickness: 0.6, space: 1),
      listTileTheme: ListTileThemeData(
        tileColor: colors.surface,
        iconColor: colors.textTertiary,
        titleTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 17, letterSpacing: -0.3, color: colors.textPrimary),
        subtitleTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 15, color: colors.textTertiary),
      ),
      // iOS switch: green track when on
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? const Color(0xFF34C759)
            : (light ? const Color(0xFFE9E9EA) : const Color(0xFF39393D))),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      // iOS sheet: grouped background, 12pt top corners, grabber
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: light ? colors.bg : colors.surface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: light ? const Color(0xFFC7C7CC) : const Color(0xFF5A5A5E),
        dragHandleSize: const Size(36, 5),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      ),
      // iOS alert: rounded 14pt
      dialogTheme: DialogThemeData(
        backgroundColor: light ? const Color(0xFFF7F7F8) : const Color(0xFF2C2C2E),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        titleTextStyle: TextStyle(
            fontFamily: fontFamily, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.4, color: colors.textPrimary),
        contentTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 15, height: 1.4, color: colors.textSecondary),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: light ? const Color(0xFF1C1C1E) : const Color(0xFF3A3A3C),
        contentTextStyle: const TextStyle(fontFamily: fontFamily, fontSize: 15, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      // iOS activity indicators are grey, not brand-coloured
      progressIndicatorTheme:
          ProgressIndicatorThemeData(color: light ? const Color(0xFF8E8E93) : const Color(0xFF98989F)),
      popupMenuTheme: PopupMenuThemeData(
        color: light ? const Color(0xFFF7F7F8) : const Color(0xFF2C2C2E),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        elevation: 8,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: colors.textTertiary,
        indicatorColor: accent,
        dividerColor: colors.border,
        labelStyle: const TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w500),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? accent : const Color(0xFF8E8E93),
              size: 26,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontFamily: fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: states.contains(WidgetState.selected) ? accent : const Color(0xFF8E8E93),
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
