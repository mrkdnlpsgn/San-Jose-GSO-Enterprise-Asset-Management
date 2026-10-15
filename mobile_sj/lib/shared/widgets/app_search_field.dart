import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// A search field shared by every list screen (Assets, Maintenance, Disposal,
/// Accounts, Asset Picker). Debounces [onChanged] so typing doesn't fire a
/// network request per keystroke; Enter/clear bypass the debounce for an
/// instant response.
class AppSearchField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final bool autofocus;
  final Duration debounce;

  const AppSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.autofocus = false,
    this.debounce = const Duration(milliseconds: 350),
  });

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _handleChanged(String value) {
    setState(() {}); // refresh clear-button visibility
    _debounceTimer?.cancel();
    _debounceTimer = Timer(widget.debounce, () => widget.onChanged(value));
  }

  void _submit(String value) {
    _debounceTimer?.cancel();
    widget.onChanged(value);
  }

  void _clear() {
    _debounceTimer?.cancel();
    widget.controller.clear();
    widget.onChanged('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      autofocus: widget.autofocus,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: TextStyle(color: context.colors.textTertiary, fontSize: 15),
        prefixIcon: Icon(Icons.search_rounded, size: 22, color: context.colors.textTertiary),
        suffixIcon: widget.controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 20),
                tooltip: 'Clear search',
                onPressed: _clear,
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
      onChanged: _handleChanged,
      onSubmitted: _submit,
    );
  }
}
