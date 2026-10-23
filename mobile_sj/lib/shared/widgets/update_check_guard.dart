import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/router/root_navigator.dart';
import '../../core/theme/app_theme.dart';

// Once per app launch, asks the server for the newest release (GET /api/app/version) and, when
// this install is older, offers the download. Below the server's minimum version the update is
// required: the dialog can't be dismissed. Android only - the update is an APK. Release builds
// only: a local (debug) build installs as a separate app that the release APK can't update. Any
// failure (offline, server asleep) is ignored; the app works the same without the check.
class UpdateCheckGuard extends StatefulWidget {
  final Widget child;
  const UpdateCheckGuard({super.key, required this.child});

  @override
  State<UpdateCheckGuard> createState() => _UpdateCheckGuardState();
}

class _UpdateCheckGuardState extends State<UpdateCheckGuard> {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb && Platform.isAndroid && kReleaseMode) {
      // after the first screen is up, so the dialog has a navigator to open on
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  Future<void> _check() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final res = await ApiClient.instance.dio.get('/app/version');
      final data = res.data;
      if (data is! Map) return;
      final latest = data['latestVersion']?.toString();
      final url = data['downloadUrl']?.toString();
      if (latest == null || url == null || !isOlder(info.version, latest)) return;
      final minimum = data['minVersion']?.toString();
      final required = minimum != null && isOlder(info.version, minimum);
      final prefs = await SharedPreferences.getInstance();
      final ctx = rootNavigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      await showUpdateDialog(ctx,
          current: info.version, latest: latest, url: url,
          notes: data['releaseNotes']?.toString(), required: required,
          alreadyDownloaded: prefs.getString(_kDownloadedVersion) == latest,
          onDownloadStarted: () => prefs.setString(_kDownloadedVersion, latest));
    } catch (_) {
      // no answer - try again next launch
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// The version whose download was last started, so a relaunch (Android often closes the app while
// the browser downloads) points to that file instead of downloading the same APK again.
const _kDownloadedVersion = 'update.downloadedVersion';

// True when version a (e.g. "1.0.0") is older than b ("1.0.1"). Build numbers after "+" are ignored.
bool isOlder(String a, String b) {
  List<int> parts(String v) =>
      v.split('+').first.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final xi = i < x.length ? x[i] : 0, yi = i < y.length ? y[i] : 0;
    if (xi != yi) return xi < yi;
  }
  return false;
}

Future<void> showUpdateDialog(BuildContext context,
    {required String current,
    required String latest,
    required String url,
    String? notes,
    bool required = false,
    bool alreadyDownloaded = false,
    VoidCallback? onDownloadStarted}) {
  var opening = false;
  final file = url.split('/').last;
  return showDialog<void>(
    context: context,
    barrierDismissible: !required,
    builder: (ctx) => PopScope(
      canPop: !required,
      child: StatefulBuilder(
        builder: (ctx, setState) {
          Future<void> download() async {
            // one tap, one download - a second tap while the browser opens would start another
            if (opening) return;
            setState(() => opening = true);
            final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            if (ok) onDownloadStarted?.call();
            if (!ok && ctx.mounted) {
              ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(const SnackBar(
                  content: Text('Could not open the download link.'), behavior: SnackBarBehavior.floating));
            }
            if (ctx.mounted) {
              if (!required) {
                Navigator.pop(ctx);
              } else {
                setState(() => opening = false);
              }
            }
          }

          return AlertDialog(
            icon: Icon(Icons.system_update_rounded, color: ctx.brandAccent, size: 36),
            title: Text(required ? 'Update required' : 'Update available', textAlign: TextAlign.center),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  required
                      ? 'Version $latest is out, and this version ($current) is no longer supported. '
                          'Download and install the update to keep using the app.'
                      : 'Version $latest is available. You have $current. Download and install it to get '
                          'the latest fixes.',
                  style: TextStyle(color: ctx.colors.textSecondary, fontSize: 15, height: 1.45),
                  textAlign: TextAlign.center,
                ),
                if (alreadyDownloaded) ...[
                  const SizedBox(height: 12),
                  // Downloads keeps every earlier APK too - name the one to open
                  Text('Already downloaded? Open your Downloads and tap $file to install it.',
                      style: TextStyle(color: ctx.colors.textPrimary, fontSize: 14, height: 1.45, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center),
                ],
                if (notes != null && notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(notes,
                      style: TextStyle(color: ctx.colors.textPrimary, fontSize: 14, height: 1.45),
                      textAlign: TextAlign.center),
                ],
              ],
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.download_rounded, size: 20),
                  label: Text(alreadyDownloaded ? 'Download again' : 'Download update'),
                  onPressed: opening ? null : download,
                ),
              ),
              if (!required)
                SizedBox(
                  width: double.infinity,
                  child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
                ),
            ],
          );
        },
      ),
    ),
  );
}
