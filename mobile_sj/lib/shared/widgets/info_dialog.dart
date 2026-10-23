import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

// Single-button, informational counterpart to showDeleteDialog - for telling
// the user an action can't proceed (e.g. "this category has assets assigned
// to it"), not asking them to confirm one.
Future<void> showInfoDialog(BuildContext context, {required String title, required String message}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.info_rounded, color: AppTheme.statusMaintenance, size: 36),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(message,
          style: TextStyle(color: ctx.colors.textSecondary, fontSize: 15, height: 1.45), textAlign: TextAlign.center),
      actions: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ),
      ],
    ),
  );
}
