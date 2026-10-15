import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Mirrors backend/StrongPasswordValidator.java and the web app's REQUIREMENTS
/// list exactly, so all three clients agree on what a valid password is.
class PasswordRequirement {
  final String key;
  final String label;
  final bool Function(String) test;
  const PasswordRequirement(this.key, this.label, this.test);
}

final List<PasswordRequirement> kPasswordRequirements = [
  PasswordRequirement('length', '8–128 characters', (p) => p.length >= 8 && p.length <= 128),
  PasswordRequirement('uppercase', 'One uppercase letter (A–Z)', (p) => RegExp(r'[A-Z]').hasMatch(p)),
  PasswordRequirement('lowercase', 'One lowercase letter (a–z)', (p) => RegExp(r'[a-z]').hasMatch(p)),
  PasswordRequirement('digit', 'One number (0–9)', (p) => RegExp(r'[0-9]').hasMatch(p)),
  PasswordRequirement('special', 'One special character (@\$!%*?&_#^-)', (p) => RegExp(r'[@$!%*?&_#^\-]').hasMatch(p)),
];

bool passwordMeetsRequirements(String password) =>
    kPasswordRequirements.every((r) => r.test(password));

/// Checklist shown under a new-password field, ticking off requirements live as
/// the user types. Hidden entirely until the field has content, matching the web app.
class PasswordRequirementsList extends StatelessWidget {
  final String password;
  const PasswordRequirementsList({super.key, required this.password});

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: AppTheme.motionFast,
      curve: AppTheme.motionCurve,
      alignment: Alignment.topCenter,
      child: password.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: kPasswordRequirements.map((r) {
                  final met = r.test(password);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: Row(
                      children: [
                        Icon(
                          met ? Icons.check_circle_rounded : Icons.circle_outlined,
                          size: 14,
                          color: met ? AppTheme.brand : context.colors.textTertiary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          r.label,
                          style: TextStyle(
                            fontSize: 14,
                            color: met ? AppTheme.brand : context.colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
    );
  }
}
