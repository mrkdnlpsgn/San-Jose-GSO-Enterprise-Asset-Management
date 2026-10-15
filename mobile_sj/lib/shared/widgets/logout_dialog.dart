import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

// Returns true if the user confirmed, null/false if cancelled.
// Worded "Sign out" to match the button that opens it (and the web app).
Future<bool?> showLogoutDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sign out?'),
      content: Text("You'll need to sign in again to continue.",
          style: TextStyle(color: ctx.colors.textSecondary, fontSize: 15, height: 1.45)),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
}
