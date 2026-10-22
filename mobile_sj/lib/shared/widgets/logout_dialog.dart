import 'package:flutter/material.dart';
import '../../core/offline/outbox.dart';
import '../../core/theme/app_theme.dart';

// Returns true if the user confirmed, null/false if cancelled.
// Worded "Sign out" to match the button that opens it (and the web app).
Future<bool?> showLogoutDialog(BuildContext context) {
  // Changes saved offline stay on the phone, tied to this account.
  final waiting = Outbox.instance.items.length;
  final message = waiting == 0
      ? "You'll need to sign in again to continue."
      : waiting == 1
          ? "1 change hasn't uploaded yet. It stays on this phone and will upload the next time you sign in to this account."
          : "$waiting changes haven't uploaded yet. They stay on this phone and will upload the next time you sign in "
              'to this account.';
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sign out?'),
      content: Text(message,
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
