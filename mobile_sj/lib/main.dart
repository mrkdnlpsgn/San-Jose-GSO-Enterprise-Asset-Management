import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/api/api_client.dart';
import 'core/offline/outbox.dart';
import 'core/router/app_router.dart';
import 'core/router/root_navigator.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/provider/settings_provider.dart';
import 'features/outbox/sync_engine.dart';
import 'shared/widgets/offline_banner.dart';
import 'shared/widgets/idle_timeout_guard.dart';
import 'shared/widgets/update_check_guard.dart';
import 'shared/widgets/action_otp_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await ApiClient.instance.init(prefs);
  await Outbox.instance.load();
  ApiClient.instance.actionOtpPrompt = (message, send) async {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return const ActionOtpOutcome();
    return showActionOtpDialog(context, message: message, send: send);
  };
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const EamApp(),
    ),
  );
}

class EamApp extends ConsumerWidget {
  const EamApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    // Keeps the uploader running for the app's lifetime (listen, not watch: no app-wide rebuilds).
    ref.listen(syncEngineProvider, (_, __) {});
    final settings = ref.watch(settingsProvider);
    return MaterialApp.router(
      title: 'San Jose EAM',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settings.themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        // Compose with the system's own text-scale (Dynamic Type / OS large-text
        // accessibility setting) rather than replacing it - a user relying on a
        // system-level larger-text setting shouldn't have it silently clobbered
        // down to this app's own 0.85–1.15x Settings toggle.
        final systemScale = MediaQuery.textScalerOf(context).scale(1.0);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(systemScale * settings.textSize.scaleFactor),
          ),
          child: UpdateCheckGuard(child: IdleTimeoutGuard(child: OfflineBanner(child: child!))),
        );
      },
    );
  }
}
