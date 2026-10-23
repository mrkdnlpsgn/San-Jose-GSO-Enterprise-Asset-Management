import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// A consistent full-body error state (icon + message + optional Retry) -
/// used wherever a screen fails to load, instead of each screen picking its
/// own plain-text-only or icon-only treatment.
class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorState({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 48, color: context.colors.textSecondary),
            const SizedBox(height: 12),
            Text(message, style: TextStyle(color: context.colors.textTertiary), textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
