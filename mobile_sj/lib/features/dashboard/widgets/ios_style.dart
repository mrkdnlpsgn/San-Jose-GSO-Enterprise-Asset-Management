import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ios_touch.dart';

export '../../../shared/widgets/ios_touch.dart';

/// iOS look for Home only: Apple's grouped-list colours, system tints, the press-to-shrink
/// feedback, section headers and the rounded-square icon tiles used in Settings.
class Ios {
  Ios._();

  // System colours (light / dark variants picked by [of]).
  static const blue = Color(0xFF007AFF);
  static const green = Color(0xFF34C759);
  static const orange = Color(0xFFFF9500);
  static const red = Color(0xFFFF3B30);
  static const indigo = Color(0xFF5856D6);
  static const purple = Color(0xFFAF52DE);
  static const teal = Color(0xFF30B0C7);
  static const pink = Color(0xFFFF2D55);
  static const gray = Color(0xFF8E8E93);

  /// systemGroupedBackground
  static Color groupedBg(BuildContext context) =>
      context.isLight ? const Color(0xFFF2F2F7) : const Color(0xFF000000);

  /// secondarySystemGroupedBackground — the inset section ("card") fill
  static Color cell(BuildContext context) => context.isLight ? Colors.white : const Color(0xFF1C1C1E);

  /// separator (opaque variant)
  static Color separator(BuildContext context) =>
      context.isLight ? const Color(0xFFE5E5EA) : const Color(0xFF38383A);

  /// tertiaryLabel — chevrons
  static Color chevron(BuildContext context) =>
      context.isLight ? const Color(0xFFC4C4C7) : const Color(0xFF5A5A5E);

  static const sectionRadius = 14.0;

  /// Home's Material theme, re-skinned as iOS grouped list: borderless rounded sections on
  /// the grey grouped background, hairline separators.
  static ThemeData theme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      scaffoldBackgroundColor: groupedBg(context),
      cardTheme: base.cardTheme.copyWith(
        color: cell(context),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(sectionRadius)),
      ),
      dividerTheme: base.dividerTheme.copyWith(color: separator(context), thickness: 0.6),
      extensions: [
        base.extension<AppColors>()!.copyWith(border: separator(context), surface: cell(context)),
      ],
    );
  }
}

/// iOS bold section header ("Overview"), sitting above a grouped section.
class IosSectionHeader extends StatelessWidget {
  final String text;
  const IosSectionHeader(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 22,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: context.colors.textPrimary,
          ),
        ),
      );
}

/// The rounded-square coloured icon of an iOS Settings row.
class IosIconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IosIconTile({super.key, required this.icon, required this.color, this.size = 30});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: ShapeDecoration(
          color: color,
          shape: ContinuousRectangleBorder(borderRadius: BorderRadius.circular(size * 0.45)),
        ),
        child: Icon(icon, size: size * 0.62, color: Colors.white),
      );
}

/// The thin grey chevron at the end of a tappable iOS row.
typedef IosChevron = DisclosureChevron;
