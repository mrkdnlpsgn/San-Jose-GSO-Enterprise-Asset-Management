import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/main_shell.dart';
import '../../auth/provider/auth_provider.dart';
import '../provider/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final user = ref.watch(authProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + context.mainShellBottomInset),
        children: [
          _sectionLabel(context, 'APPEARANCE'),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Theme',
                      style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('Choose how San Jose GSO looks on this device.',
                      style: TextStyle(color: context.colors.textTertiary, fontSize: 13)),
                  const SizedBox(height: 14),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded), label: Text('System')),
                      ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: Text('Light')),
                      ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: Text('Dark')),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (selection) => notifier.setThemeMode(selection.first),
                  ),
                  const Divider(height: 32),
                  Text('Text Size',
                      style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('Adjust text size for easier reading.',
                      style: TextStyle(color: context.colors.textTertiary, fontSize: 13)),
                  const SizedBox(height: 14),
                  SegmentedButton<TextSizeOption>(
                    segments: TextSizeOption.values
                        .map((opt) => ButtonSegment(value: opt, label: Text(opt.label)))
                        .toList(),
                    selected: {settings.textSize},
                    onSelectionChanged: (selection) => notifier.setTextSize(selection.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _sectionLabel(context, 'ACCOUNT'),
          const SizedBox(height: 12),
          if (user != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.brand.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.brand.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.brand.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
                      style: const TextStyle(color: AppTheme.brand, fontWeight: FontWeight.w700, fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.username,
                            style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                        const SizedBox(height: 4),
                        StatusBadge(
                          label: user.role,
                          color: user.isAdmin ? AppTheme.brand : AppTheme.statusAssigned,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_reset_rounded, color: AppTheme.brand),
              title: Text('Change Password', style: TextStyle(color: context.colors.textPrimary)),
              trailing: Icon(Icons.chevron_right_rounded, color: context.colors.textSecondary),
              onTap: () => context.push('/settings/change-password'),
            ),
          ),
          const SizedBox(height: 24),
          _sectionLabel(context, 'ABOUT'),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.privacy_tip_outlined, color: AppTheme.brand),
              title: Text('Privacy, Terms & Conditions', style: TextStyle(color: context.colors.textPrimary)),
              trailing: Icon(Icons.chevron_right_rounded, color: context.colors.textSecondary),
              onTap: () => context.push('/legal'),
            ),
          ),
          const SizedBox(height: 12),
          const _AboutCard(),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) => Text(
        label,
        style: TextStyle(
          color: context.colors.textTertiary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      );
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.brand.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.location_city_rounded, color: AppTheme.brand, size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('San Jose GSO',
                        style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                    Text('Enterprise Asset Management',
                        style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final version = snapshot.hasData
                    ? 'Version ${snapshot.data!.version} (${snapshot.data!.buildNumber})'
                    : 'Version —';
                return Text(version, style: TextStyle(color: context.colors.textTertiary, fontSize: 12.5));
              },
            ),
            const SizedBox(height: 4),
            Text('San Jose Municipal Hall · Batangas · Republic of the Philippines',
                style: TextStyle(color: context.colors.textTertiary, fontSize: 12.5)),
            const SizedBox(height: 4),
            Text('For access issues, contact the ICT Administrator.',
                style: TextStyle(color: context.colors.textTertiary, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}
