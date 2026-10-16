import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Sheet title bar: Cancel on the left, the title centred.
class _SheetHeader extends StatelessWidget {
  final String title;
  final VoidCallback onCancel;
  const _SheetHeader({required this.title, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 52,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border, width: 0.5))),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: TextButton(onPressed: onCancel, child: const Text('Cancel')),
          ),
          Expanded(
            child: Text(title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.4, color: c.textPrimary)),
          ),
          const SizedBox(width: 92), // balances Cancel so the title stays centred
        ],
      ),
    );
  }
}

/// Plain text of a menu item's label, for search and the sheet rows.
String _labelOf(DropdownMenuItem item) {
  final child = item.child;
  if (child is Text) return child.data ?? child.textSpan?.toPlainText() ?? '';
  return item.value?.toString() ?? '';
}

/// A form field that opens an iOS-style selection sheet — a checkmarked list, with a search
/// box when the list is long (offices, personnel) — instead of Material's drop-down menu.
/// Takes the same arguments as [DropdownButtonFormField], so screens only swap the name;
/// [isExpanded], [dropdownColor] and [style] are accepted for compatibility.
class IosSelectFormField<T> extends StatefulWidget {
  final T? initialValue;
  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration? decoration;
  final FormFieldValidator<T>? validator;
  final Widget? hint;
  final bool isExpanded;
  final Color? dropdownColor;
  final TextStyle? style;

  const IosSelectFormField({
    super.key,
    this.initialValue,
    @Deprecated('Use initialValue') T? value,
    required this.items,
    this.onChanged,
    this.decoration,
    this.validator,
    this.hint,
    this.isExpanded = false,
    this.dropdownColor,
    this.style,
  });

  @override
  State<IosSelectFormField<T>> createState() => _IosSelectFormFieldState<T>();
}

class _IosSelectFormFieldState<T> extends State<IosSelectFormField<T>> {
  final _fieldKey = GlobalKey<FormFieldState<T>>();

  @override
  void didUpdateWidget(IosSelectFormField<T> old) {
    super.didUpdateWidget(old);
    // a parent that rebuilds with a new value (e.g. after loading) should show it
    if (old.initialValue != widget.initialValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fieldKey.currentState?.didChange(widget.initialValue));
    }
  }

  Future<void> _open(FormFieldState<T> field) async {
    final items = widget.items ?? const [];
    final title = widget.decoration?.labelText?.replaceAll(RegExp(r'\s*\*$'), '') ?? 'Select';
    final result = await showModalBottomSheet<_Picked<T>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SelectSheet<T>(title: title, items: items, selected: field.value),
    );
    if (result == null) return;
    field.didChange(result.value);
    widget.onChanged?.call(result.value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null && (widget.items?.isNotEmpty ?? false);
    final c = context.colors;
    return FormField<T>(
      key: _fieldKey,
      initialValue: widget.initialValue,
      validator: widget.validator,
      builder: (field) {
        DropdownMenuItem<T>? selected;
        for (final it in widget.items ?? const []) {
          if (it.value == field.value) selected = it as DropdownMenuItem<T>;
        }
        final decoration = (widget.decoration ?? const InputDecoration())
            .applyDefaults(Theme.of(context).inputDecorationTheme)
            .copyWith(
              errorText: field.errorText,
              enabled: enabled,
              suffixIcon: Icon(Icons.unfold_more_rounded, color: c.textTertiary),
            );
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? () => _open(field) : null,
          child: InputDecorator(
            decoration: decoration,
            isEmpty: selected == null,
            child: selected != null
                ? DefaultTextStyle.merge(
                    style: TextStyle(fontSize: 17, letterSpacing: -0.2, color: enabled ? c.textPrimary : c.textTertiary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: selected.child,
                  )
                : (widget.hint ??
                    Text(decoration.hintText ?? 'Choose…', style: TextStyle(fontSize: 16, color: c.textTertiary))),
          ),
        );
      },
    );
  }
}

/// Wraps the choice so "chose nothing / null" differs from "dismissed the sheet".
class _Picked<T> {
  final T? value;
  const _Picked(this.value);
}

class _SelectSheet<T> extends StatefulWidget {
  final String title;
  final List<DropdownMenuItem<T>> items;
  final T? selected;
  const _SelectSheet({required this.title, required this.items, required this.selected});

  @override
  State<_SelectSheet<T>> createState() => _SelectSheetState<T>();
}

class _SelectSheetState<T> extends State<_SelectSheet<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final searchable = widget.items.length > 10;
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty ? widget.items : widget.items.where((i) => _labelOf(i).toLowerCase().contains(q)).toList();
    final maxH = MediaQuery.sizeOf(context).height * 0.8;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SheetHeader(title: widget.title, onCancel: () => Navigator.pop(context)),
          if (searchable)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Search',
                  prefixIcon: Icon(Icons.search_rounded),
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          Flexible(
            child: shown.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('No matches.', style: TextStyle(color: c.textTertiary, fontSize: 15)),
                  )
                : ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + MediaQuery.of(context).padding.bottom),
                    children: [
                      // one inset grouped section of rows, a checkmark on the current choice
                      Card(
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (var i = 0; i < shown.length; i++) ...[
                              if (i > 0) const Divider(height: 1, indent: 16),
                              InkWell(
                                onTap: shown[i].enabled ? () => Navigator.pop(context, _Picked<T>(shown[i].value)) : null,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(minHeight: 50),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: DefaultTextStyle.merge(
                                            style: TextStyle(
                                              fontSize: 17,
                                              letterSpacing: -0.3,
                                              color: shown[i].enabled ? c.textPrimary : c.textTertiary,
                                            ),
                                            child: shown[i].child,
                                          ),
                                        ),
                                        if (shown[i].value == widget.selected)
                                          Icon(Icons.check_rounded, size: 22, color: context.brandAccent),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
