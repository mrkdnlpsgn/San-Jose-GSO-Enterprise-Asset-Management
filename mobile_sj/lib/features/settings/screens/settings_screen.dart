import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/main_shell.dart';
import '../../../shared/widgets/large_title_scaffold.dart';
import '../provider/settings_provider.dart';
import '../../../shared/widgets/ios_touch.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return LargeTitleScaffold(
      title: 'Settings',
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
          _sectionLabel(context, 'ABOUT'),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(Icons.privacy_tip_outlined, color: context.brandAccent),
              title: Text('Privacy, Terms & Conditions', style: TextStyle(color: context.colors.textPrimary)),
              trailing: const DisclosureChevron(),
              onTap: () => context.push('/legal'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(Icons.auto_stories_outlined, color: context.brandAccent),
              title: Text('App Tour', style: TextStyle(color: context.colors.textPrimary)),
              subtitle: Text('What you can do in this app', style: TextStyle(color: context.colors.textTertiary)),
              trailing: const DisclosureChevron(),
              onTap: () => context.push('/welcome?replay=1'),
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
          fontSize: 14,
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
                  child: Icon(Icons.location_city_rounded, color: context.brandAccent, size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('San Jose GSO',
                        style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                    Text('Enterprise Asset Management',
                        style: TextStyle(color: context.colors.textTertiary, fontSize: 14)),
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
                    : 'Version unknown';
                return Text(version, style: TextStyle(color: context.colors.textTertiary, fontSize: 14));
              },
            ),
            const SizedBox(height: 4),
            Text('San Jose Municipal Hall · Batangas · Republic of the Philippines',
                style: TextStyle(color: context.colors.textTertiary, fontSize: 14)),
            const SizedBox(height: 4),
            Text('For access issues, contact the GSO system administrator.',
                style: TextStyle(color: context.colors.textTertiary, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
