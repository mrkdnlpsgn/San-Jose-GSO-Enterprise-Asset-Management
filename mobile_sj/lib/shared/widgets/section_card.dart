import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// The web app's card: white, 1px border, a header row (navy title, optional
/// trailing text or action) separated from the body by a hairline.
class SectionCard extends StatelessWidget {
  final String title;
  final String? trailingText;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailingText,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, trailing != null ? 6 : 14, trailing != null ? 6 : 16, trailing != null ? 6 : 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.heading)),
                ),
                if (trailingText != null)
                  Text(trailingText!, style: TextStyle(fontSize: 13, color: c.textTertiary)),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Divider(height: 1, color: c.border),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// Small uppercase label above a group of cards ("OVERVIEW", "MODULES"), like the web sidebar's section names.
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 10),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: context.colors.textTertiary,
          ),
        ),
      );
}
