import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../features/settings/provider/settings_provider.dart';

enum _TestResult { none, testing, success, failure }

/// Which server the app talks to: the live system (Render, the default), this computer's
/// local Docker backend (for development on the emulator), or any address typed in.
/// Deliberately reusable outside the authenticated Account screen (see
/// ConnectionSettingsScreen): if the saved address is wrong, sign-in itself fails before
/// the user can reach Account to fix it, so this needs a pre-login entry point too.
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
    setState(() {
      _testResult = _TestResult.testing;
      _testError = null;
    });
    try {
      // generous timeout — the live server may need a minute to wake up
      final res = await Dio().get(
        '${ApiClient.originFor(address)}/actuator/health',
        options: Options(sendTimeout: const Duration(seconds: 60), receiveTimeout: const Duration(seconds: 60)),
      );
      setState(() => _testResult = (res.statusCode ?? 0) == 200 ? _TestResult.success : _TestResult.failure);
    } on DioException catch (e) {
      setState(() {
        _testResult = _TestResult.failure;
        _testError = e.type == DioExceptionType.connectionTimeout ||
                e.type == DioExceptionType.receiveTimeout ||
                e.type == DioExceptionType.connectionError
            ? 'Could not reach that address. Check the internet connection, or the address and port.'
            : e.message;
      });
    } catch (_) {
      setState(() => _testResult = _TestResult.failure);
    }
  }

  Future<void> _use(String? address, String message) async {
    _ctrl.text = address ?? ApiClient.defaultAddress;
    setState(() => _testResult = _TestResult.none);
    await ref.read(settingsProvider.notifier).setServerAddress(address);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final current = ref.watch(settingsProvider).serverAddress;
    final onLive = ApiClient.originFor(current) == ApiClient.originFor(ApiClient.liveAddress);
    final onLocal = ApiClient.originFor(current) == ApiClient.originFor(ApiClient.localAddress);

    Widget choice({required bool selected, required IconData icon, required String title, required String detail, required VoidCallback onTap}) =>
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected ? (context.isLight ? AppTheme.brandTint : AppTheme.brand.withValues(alpha: 0.12)) : c.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected ? AppTheme.brand : c.border, width: selected ? 2 : 1),
            ),
            child: Row(
              children: [
                Icon(icon, color: selected ? context.brandAccent : c.textTertiary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(detail, style: TextStyle(color: c.textTertiary, fontSize: 13)),
                    ],
                  ),
                ),
                if (selected) Icon(Icons.check_circle_rounded, color: context.brandAccent),
              ],
            ),
          ),
        );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Server', style: TextStyle(color: c.heading, fontWeight: FontWeight.w700, fontSize: 17)),
            const SizedBox(height: 4),
            Text('Which system this app connects to. Most people should use the live system.',
                style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.45)),
            const SizedBox(height: 14),
            choice(
              selected: onLive,
              icon: Icons.public_rounded,
              title: 'Live system',
              detail: ApiClient.liveAddress,
              onTap: () => _use(null, 'Connected to the live system.'),
            ),
            const SizedBox(height: 8),
            choice(
              selected: onLocal,
              icon: Icons.computer_rounded,
              title: 'This computer (for testing)',
              detail: '${ApiClient.localAddress} — the local Docker backend',
              onTap: () => _use(ApiClient.localAddress, 'Connected to this computer.'),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _ctrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              style: const TextStyle(fontSize: 16),
              decoration: const InputDecoration(
                labelText: 'Or type an address',
                hintText: 'https://example.com or 192.168.1.7:8080',
              ),
              onChanged: (_) => setState(() => _testResult = _TestResult.none),
            ),
            if (_testResult != _TestResult.none) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_testResult == _TestResult.testing)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    Icon(
                      _testResult == _TestResult.success ? Icons.check_circle_rounded : Icons.error_rounded,
                      size: 18,
                      color: _testResult == _TestResult.success ? context.brandAccent : const Color(0xFFDC2626),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _testResult == _TestResult.testing
                          ? 'Testing connection… (the live system can take a minute to wake up)'
                          : _testResult == _TestResult.success
                              ? 'Connected successfully.'
                              : _testError ?? 'Could not connect.',
                      style: TextStyle(
                        fontSize: 14,
                        color: _testResult == _TestResult.failure ? const Color(0xFFDC2626) : c.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _testResult == _TestResult.testing ? null : _test,
                    child: const Text('Test'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _use(_ctrl.text.trim().isEmpty ? null : _ctrl.text.trim(), 'Server address saved.'),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
