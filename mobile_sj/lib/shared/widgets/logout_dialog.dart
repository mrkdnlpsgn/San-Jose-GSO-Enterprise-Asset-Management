import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

// Returns true if the user confirmed, null/false if cancelled.
Future<bool?> showLogoutDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ctx.colors.surface,
      title: Text('Log out?', style: TextStyle(color: ctx.colors.textPrimary)),
      content: Text("You'll need to sign in again to continue.",
          style: TextStyle(color: ctx.colors.textTertiary, fontSize: 13)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Cancel', style: TextStyle(color: ctx.colors.textTertiary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Log Out', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}
