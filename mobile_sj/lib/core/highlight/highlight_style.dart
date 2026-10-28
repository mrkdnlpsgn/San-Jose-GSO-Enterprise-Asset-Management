import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// How a card a notification pointed to looks: an amber tint and outline, like the web's rows.
Color highlightTint(BuildContext context) =>
    context.isLight ? const Color(0xFFFFFBEB) : AppTheme.statusMaintenance.withValues(alpha: 0.12);

ShapeBorder highlightShape() => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: AppTheme.statusMaintenance, width: 1.5),
    );

/// Above a list opened from a notification: what is highlighted, and a way to clear it.
class HighlightBanner extends StatelessWidget {
  final int count;
  final String noun; // singular, e.g. "asset"
  final String plural;
  final String title;
  final String clearLabel;
  final VoidCallback onClear;
  final EdgeInsetsGeometry margin;
  const HighlightBanner({
    super.key,
    required this.count,
    required this.noun,
    required this.plural,
    required this.title,
    required this.onClear,
    this.clearLabel = 'Clear',
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 4),
  });

  @override
  Widget build(BuildContext context) {
    final fg = context.isLight ? const Color(0xFF92400E) : const Color(0xFFFCD34D);
    return Container(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: highlightTint(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.statusMaintenance.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_active_rounded, size: 20, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                count == 0
                    ? 'Nothing from this notification is in the list right now.'
                    : 'Highlighting $count ${count == 1 ? noun : plural} · $title',
                style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w500),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(foregroundColor: fg, minimumSize: const Size(48, 44)),
            child: Text(clearLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
