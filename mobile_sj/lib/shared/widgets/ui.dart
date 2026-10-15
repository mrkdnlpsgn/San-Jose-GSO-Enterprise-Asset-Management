import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'app_search_field.dart';
import 'section_card.dart';

export 'section_card.dart';

// Shared building blocks for the web-matching look: list screen headers, list cards,
// label/value rows, form labels and callouts. Screens compose these instead of styling
// each card by hand, so every module looks and reads the same.

/// App bar title with a record count under it ("Maintenance / 24 records").
class TitleWithCount extends StatelessWidget {
  final String title;
  final String? subtitle;
  const TitleWithCount(this.title, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          Text(
            subtitle ?? ' ',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: context.colors.textTertiary),
          ),
        ],
      );
}

/// "24 records" / "1 record" / blank while loading.
String countLabel(int? n, {String singular = 'record', String plural = 'records'}) =>
    n == null ? ' ' : '$n ${n == 1 ? singular : plural}';

/// The bottom of a list screen's app bar: search field, then worded buttons (Filter etc.).
class ListToolbar extends StatelessWidget implements PreferredSizeWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onSearch;
  final VoidCallback? onFilter;
  final bool filtersActive;
  final List<Widget> extraButtons;

  const ListToolbar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onSearch,
    this.onFilter,
    this.filtersActive = false,
    this.extraButtons = const [],
  });

  bool get _hasButtons => onFilter != null || extraButtons.isNotEmpty;

  @override
  Size get preferredSize => Size.fromHeight(_hasButtons ? 124 : 68);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: [
          AppSearchField(controller: controller, hintText: hintText, onChanged: onSearch),
          if (_hasButtons) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (onFilter != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Badge(
                        isLabelVisible: filtersActive,
                        smallSize: 8,
                        backgroundColor: AppTheme.brand,
                        child: const Icon(Icons.filter_list_rounded, size: 20),
                      ),
                      label: Text(filtersActive ? 'Filters on' : 'Filter'),
                      style: toolbarButtonStyle(context, active: filtersActive),
                      onPressed: onFilter,
                    ),
                  ),
                for (final b in extraButtons) ...[
                  if (onFilter != null || b != extraButtons.first) const SizedBox(width: 8),
                  Expanded(child: b),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Outlined toolbar button; [active] tints it green (e.g. filters applied).
ButtonStyle toolbarButtonStyle(BuildContext context, {bool active = false}) => OutlinedButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      backgroundColor: active
          ? (context.isLight ? AppTheme.brandTint : AppTheme.brand.withValues(alpha: 0.15))
          : context.colors.surface,
      foregroundColor: active ? context.brandAccent : context.colors.textPrimary,
      side: BorderSide(
          color: active ? AppTheme.brand : (context.isLight ? const Color(0xFFCBD5E1) : context.colors.border)),
    );

/// A tappable white card in a list, with a chevron on the right when [onTap] is set.
class RecordCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Widget? trailing;
  const RecordCard({super.key, required this.child, this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 14, onTap != null || trailing != null ? 10 : 16, 14),
          child: Row(
            children: [
              Expanded(child: child),
              if (trailing != null) trailing!,
              if (onTap != null && trailing == null) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: context.colors.textTertiary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Property number / code in the monospace style the web tables use.
class CodeText extends StatelessWidget {
  final String text;
  final double size;
  const CodeText(this.text, {super.key, this.size = 13});

  @override
  Widget build(BuildContext context) => Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: context.colors.textTertiary,
          fontSize: size,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
          letterSpacing: -0.2,
        ),
      );
}

/// Bold record title inside a list card.
class CardTitle extends StatelessWidget {
  final String text;
  final int maxLines;
  const CardTitle(this.text, {super.key, this.maxLines = 2});

  @override
  Widget build(BuildContext context) => Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: context.colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600, height: 1.3),
      );
}

/// Small icon + text line (office, date, person) under a card title.
class MetaLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const MetaLine(this.icon, this.text, {super.key});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 16, color: context.colors.textTertiary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.colors.textSecondary, fontSize: 14)),
          ),
        ],
      );
}

/// Label/value rows inside a [SectionCard], divided by hairlines — the web drawer's detail list.
class DetailSection extends StatelessWidget {
  final String title;
  final List<DetailItem> items;
  final Widget? trailing;
  const DetailSection({super.key, required this.title, required this.items, this.trailing});

  @override
  Widget build(BuildContext context) {
    final shown = items.where((i) => i.value != null && i.value!.trim().isNotEmpty || i.child != null).toList();
    return SectionCard(
      title: title,
      trailing: trailing,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 16, color: context.colors.border),
            DetailRow(item: shown[i]),
          ],
        ],
      ),
    );
  }
}

class DetailItem {
  final String label;
  final String? value;
  final Widget? child;      // custom value (e.g. a badge) instead of text
  final Color? valueColor;
  final bool multiline;     // long text: shown under the label instead of beside it
  const DetailItem(this.label, this.value, {this.valueColor, this.multiline = false}) : child = null;
  const DetailItem.widget(this.label, Widget this.child)
      : value = null,
        valueColor = null,
        multiline = false;
}

class DetailRow extends StatelessWidget {
  final DetailItem item;
  const DetailRow({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = Text(item.label, style: TextStyle(color: c.textTertiary, fontSize: 15));
    if (item.multiline) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label,
            const SizedBox(height: 4),
            Text(item.value!, style: TextStyle(color: c.textPrimary, fontSize: 15, height: 1.45)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: label),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: item.child != null
                ? Align(alignment: Alignment.centerRight, child: item.child)
                : Text(
                    item.value!,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: item.valueColor ?? c.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A form label above its field, as on the web forms. [required] adds a red asterisk.
class FieldLabel extends StatelessWidget {
  final String text;
  final bool required;
  final String? hint;
  const FieldLabel(this.text, {super.key, this.required = false, this.hint});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(text: text),
                if (required) const TextSpan(text: ' *', style: TextStyle(color: Color(0xFFDC2626))),
              ]),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: context.colors.textSecondary),
            ),
            if (hint != null) ...[
              const SizedBox(height: 2),
              Text(hint!, style: TextStyle(fontSize: 13, color: context.colors.textTertiary)),
            ],
          ],
        ),
      );
}

enum CalloutTone { info, warning, error, success }

/// Tinted message box (web's alert boxes): info, warning, error or success.
class Callout extends StatelessWidget {
  final String text;
  final String? title;
  final CalloutTone tone;
  final Widget? action;
  const Callout(this.text, {super.key, this.title, this.tone = CalloutTone.info, this.action});

  @override
  Widget build(BuildContext context) {
    final light = context.isLight;
    final (Color base, IconData icon) = switch (tone) {
      CalloutTone.info => (AppTheme.info, Icons.info_rounded),
      CalloutTone.warning => (AppTheme.statusMaintenance, Icons.warning_rounded),
      CalloutTone.error => (const Color(0xFFDC2626), Icons.error_rounded),
      CalloutTone.success => (AppTheme.brand, Icons.check_circle_rounded),
    };
    final hsl = HSLColor.fromColor(base);
    final fg = light
        ? hsl.withLightness((hsl.lightness * 0.55).clamp(0.0, 1.0)).toColor()
        : hsl.withLightness((hsl.lightness + 0.2).clamp(0.0, 1.0)).toColor();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: base.withValues(alpha: light ? 0.08 : 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: base.withValues(alpha: light ? 0.35 : 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!, style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                ],
                Text(text, style: TextStyle(color: fg, fontSize: 15, height: 1.4)),
                if (action != null) ...[const SizedBox(height: 10), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sticky bottom bar holding a form's main button (Save / Submit), above the keyboard.
class FormActionBar extends StatelessWidget {
  final Widget child;
  const FormActionBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border(top: BorderSide(color: context.colors.border)),
        ),
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
        child: child,
      );
}

/// "UNDER_MAINTENANCE" → "Under Maintenance" — for showing backend codes to people.
String titleCaseCode(String raw) => raw
    .split('_')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');
