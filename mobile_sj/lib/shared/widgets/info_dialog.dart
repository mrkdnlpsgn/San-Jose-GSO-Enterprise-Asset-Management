import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

// Single-button, informational counterpart to showDeleteDialog — for telling
// the user an action can't proceed (e.g. "this category has assets assigned
// to it"), not asking them to confirm one.
Future<void> showInfoDialog(BuildContext context, {required String title, required String message}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ctx.colors.surface,
      icon: const Icon(Icons.error_outline_rounded, color: Colors.amber, size: 32),
      title: Text(title, style: TextStyle(color: ctx.colors.textPrimary), textAlign: TextAlign.center),
      content: Text(message, style: TextStyle(color: ctx.colors.textTertiary, fontSize: 13), textAlign: TextAlign.center),
      actions: [
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ),
      ],
    ),
  );
}
