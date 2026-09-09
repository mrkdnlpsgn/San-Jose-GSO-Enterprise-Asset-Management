import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../features/settings/provider/settings_provider.dart';

enum _TestResult { none, testing, success, failure }

/// Lets the user override the backend host:port the app connects to — needed
/// whenever the device's network changes (different Wi-Fi, off the LAN the
/// dev backend is reachable on, etc.). Deliberately reusable outside the
/// authenticated Settings screen (see ConnectionSettingsScreen): if the
/// currently-saved address is wrong, login itself fails before the user can
/// ever reach Settings to fix it, so this needs a pre-login entry point too.
class ServerAddressCard extends ConsumerStatefulWidget {
  const ServerAddressCard({super.key});

  @override
  ConsumerState<ServerAddressCard> createState() => _ServerAddressCardState();
}

class _ServerAddressCardState extends ConsumerState<ServerAddressCard> {
  late final TextEditingController _ctrl;
  _TestResult _testResult = _TestResult.none;
  String? _testError;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: ref.read(settingsProvider).serverAddress);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final address = _ctrl.text.trim();
    if (address.isEmpty) return;
    setState(() { _testResult = _TestResult.testing; _testError = null; });
    try {
      final res = await Dio().get(
        'http://$address/actuator/health',
        options: Options(sendTimeout: const Duration(seconds: 6), receiveTimeout: const Duration(seconds: 6)),
      );
      setState(() => _testResult = (res.statusCode ?? 0) == 200 ? _TestResult.success : _TestResult.failure);
    } on DioException catch (e) {
      setState(() {
        _testResult = _TestResult.failure;
        _testError = e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.connectionError
            ? 'Could not reach that address. Check the IP/port and that both devices are on the same network.'
            : e.message;
      });
    } catch (_) {
      setState(() => _testResult = _TestResult.failure);
    }
  }

  Future<void> _save() async {
    await ref.read(settingsProvider.notifier).setServerAddress(_ctrl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server address saved.'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _reset() async {
    _ctrl.text = ApiClient.defaultAddress;
    await ref.read(settingsProvider.notifier).setServerAddress(null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reset to default server address.'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Server Address',
                style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 4),
            Text('The backend host:port this app connects to — change this if the IP changes (e.g. a different Wi-Fi network).',
                style: TextStyle(color: context.colors.textTertiary, fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Host:Port', hintText: 'e.g. 192.168.1.7:8080'),
              onChanged: (_) => setState(() => _testResult = _TestResult.none),
            ),
            if (_testResult != _TestResult.none) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_testResult == _TestResult.testing)
                    const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brand))
                  else
                    Icon(
                      _testResult == _TestResult.success ? Icons.check_circle_rounded : Icons.error_rounded,
                      size: 16,
                      color: _testResult == _TestResult.success ? AppTheme.brand : Colors.red,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _testResult == _TestResult.testing
                          ? 'Testing connection…'
                          : _testResult == _TestResult.success
                              ? 'Connected successfully.'
                              : _testError ?? 'Could not connect.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: _testResult == _TestResult.failure ? Colors.red.shade300 : context.colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _testResult == _TestResult.testing ? null : _test,
                    child: const Text('Test Connection'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: _reset,
              child: Text('Reset to default (${ApiClient.defaultAddress})',
                  style: TextStyle(color: context.colors.textTertiary, fontSize: 12.5)),
            ),
          ],
        ),
      ),
    );
  }
}
