import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../assets/data/asset_service.dart';
import '../../assets/model/asset_model.dart';
import '../../reports/utils/formatters.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/main_shell.dart';
import '../../../shared/widgets/large_title_scaffold.dart';
import '../provider/qr_lookup_provider.dart';
import '../widgets/qr_scanner_overlay.dart';

// mobile_scanner only ships Android/iOS/macOS/web implementations — desktop platforms
// like Windows and Linux fall back to manual property-number entry (still fully usable,
// mirrors the web QR Scanner page's manual-entry path).
bool get _cameraScanSupported =>
    kIsWeb || Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

class QrScannerScreen extends ConsumerStatefulWidget {
  const QrScannerScreen({super.key});

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen> {
  bool _notFound = false;
  AssetModel? _result;
  // The server's verdict on a scanned sticker's signature (VERIFIED / UNSIGNED / INVALID /
  // NOT_FOUND / ERROR); null while checking, or for a number typed by hand.
  String? _qrCheck;
  String _lastCode = '';
  final _manualCtrl = TextEditingController();

  @override
  void dispose() {
    _manualCtrl.dispose();
    super.dispose();
  }

  void _lookup(String rawCode) {
    final assetsAsync = ref.read(qrLookupAssetsProvider);
    final assets = assetsAsync.valueOrNull;
    if (assets == null) return;

    final match = findAssetForCode(assets, rawCode);
    final code = rawCode.trim();
    _lastCode = code;
    if (code.startsWith('asset:')) _verify(code);
    // Close the loop on the moment of detection — same frame as the visual
    // result, per the causality/harmony rule for combining feedback senses.
    // Distinct weights so success and "not found" feel different, not just look different.
    if (match != null) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    setState(() {
      _result = match;
      _notFound = match == null;
      _qrCheck = null;
    });
  }

  // An answer for an older scan is dropped.
  Future<void> _verify(String code) async {
    String status;
    try {
      status = await AssetService().verifyQr(code);
    } catch (_) {
      status = 'ERROR';
    }
    if (mounted && _lastCode == code) setState(() => _qrCheck = status);
  }

  // Full-screen camera, like the web's scanner; comes back with the code (or null on Cancel).
  Future<void> _scan() async {
    setState(() {
      _result = null;
      _notFound = false;
    });
    final code = await showQrScanner(context);
    if (code != null && mounted) _lookup(code);
  }

  void _clear() {
    _lastCode = '';
    setState(() {
      _qrCheck = null;
      _result = null;
      _notFound = false;
      _manualCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Keep the asset list warm so lookups after a scan/manual entry are instant.
    ref.watch(qrLookupAssetsProvider);

    return LargeTitleScaffold(
      title: 'Scan',
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + context.mainShellBottomInset),
        children: [
          // The answer goes first once there is one, so it isn't hidden below the camera. It
          // eases in (fade + small rise, same moment as the scan's vibration) while the panels
          // below slide down to make room, instead of everything jumping. Reduce Motion: instant.
          AnimatedSize(
            duration: context.prefersReducedMotion ? Duration.zero : const Duration(milliseconds: 220),
            curve: AppTheme.motionCurve,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: context.prefersReducedMotion ? Duration.zero : const Duration(milliseconds: 220),
              switchInCurve: AppTheme.motionCurve,
              switchOutCurve: Curves.easeOut,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(anim),
                  child: child,
                ),
              ),
              child: _result != null
                  ? Padding(
                      key: ValueKey('found-${_result!.id}'),
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _ResultCard(asset: _result!, qrCheck: _qrCheck, onClear: _clear),
                    )
                  : _notFound
                      ? Padding(
                          key: const ValueKey('not-found'),
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _NotFoundCard(onClear: _clear),
                        )
                      : const SizedBox(key: ValueKey('none'), width: double.infinity),
            ),
          ),
          if (_cameraScanSupported) ...[
            _buildCameraPanel(),
            const SizedBox(height: 16),
          ],
          _buildManualEntryPanel(),
          if (!_cameraScanSupported && _result == null && !_notFound) ...[
            const SizedBox(height: 16),
            const _InfoCard(
              text: 'Camera scanning isn\'t available on this device. '
                  'Type a Property Number or PAR Number above to look up an asset.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCameraPanel() {
    final c = context.colors;
    return SectionCard(
      title: 'Scan an asset sticker',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Point the camera at the QR code on the asset\'s property sticker.',
            style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.45),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _scan,
            icon: const Icon(Icons.qr_code_scanner_rounded, size: 24),
            label: Text(_result != null || _notFound ? 'Scan another' : 'Scan QR code'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualEntryPanel() {
    final c = context.colors;
    return SectionCard(
      title: 'Or type the number',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('If the sticker won\'t scan, type its Property Number or PAR Number.',
              style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.45)),
          const SizedBox(height: 12),
          TextField(
            controller: _manualCtrl,
            style: const TextStyle(fontSize: 16),
            textInputAction: TextInputAction.search,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'e.g. COA-2026-001',
              prefixIcon: Icon(Icons.tag_rounded),
            ),
            onSubmitted: _lookup,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _lookup(_manualCtrl.text),
            icon: const Icon(Icons.search_rounded),
            label: const Text('Look up asset'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String text;
  const _InfoCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: context.colors.textSecondary, size: 22),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: TextStyle(color: context.colors.textSecondary, fontSize: 15, height: 1.45))),
          ],
        ),
      ),
    );
  }
}

class _NotFoundCard extends StatelessWidget {
  final VoidCallback onClear;
  const _NotFoundCard({required this.onClear});

  @override
  Widget build(BuildContext context) {
    final light = context.isLight;
    final fg = light ? const Color(0xFFB91C1C) : const Color(0xFFFCA5A5);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: light ? const Color(0xFFFEF2F2) : const Color(0x33EF4444),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: light ? const Color(0xFFFECACA) : const Color(0x66EF4444)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.error_rounded, color: fg, size: 24),
              const SizedBox(width: 10),
              Text('Asset not found', style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 17)),
            ],
          ),
          const SizedBox(height: 6),
          Text('No asset matches this code. Check the property number and try again.',
              style: TextStyle(color: fg, fontSize: 15, height: 1.45)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onClear, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final AssetModel asset;
  final String? qrCheck;
  final VoidCallback onClear;
  const _ResultCard({required this.asset, required this.qrCheck, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fields = <String, String?>{
      'PAR Number': asset.parNumber,
      'Category': asset.category.categoryName,
      'Office': asset.office.officeName,
      'Location': asset.location,
      'Accountable': asset.accountablePerson?.fullName,
      'Current User': asset.currentUser?.fullName,
      'Unit Value': fmtMoney(asset.unitValue),
      'Quantity': asset.quantity.toString(),
      'Acquired': fmtDate(asset.acquisitionDate),
      if (asset.remarks != null && asset.remarks!.isNotEmpty) 'Remarks': asset.remarks,
    }.entries.where((e) => e.value != null && e.value!.isNotEmpty).toList();

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.brand, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: context.isLight ? AppTheme.brandTint : AppTheme.brand.withValues(alpha: 0.15),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: context.brandAccent, size: 22),
                const SizedBox(width: 8),
                Text('Asset found', style: TextStyle(color: context.brandAccent, fontWeight: FontWeight.w700, fontSize: 16)),
              ],
            ),
          ),
          if (qrCheck != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _QrCheckBanner(status: qrCheck!),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(asset.propertyNumber,
                    style: TextStyle(color: c.textTertiary, fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
                const SizedBox(height: 4),
                Text(asset.description,
                    style: TextStyle(color: c.heading, fontSize: 20, height: 1.25, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    StatusBadge.condition(asset.condition),
                    StatusBadge.lifecycle(asset.lifecycleStatus),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final e in fields) ...[
            Divider(height: 1, indent: 16, color: c.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: Text(e.key, style: TextStyle(color: c.textTertiary, fontSize: 15))),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 6,
                    child: Text(e.value!,
                        textAlign: TextAlign.right,
                        style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
          Divider(height: 1, color: c.border),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: onClear, child: const Text('Scan another')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => context.push('/assets/${asset.id}'),
                    child: const Text('Open asset'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.swap_horiz_rounded, size: 20),
              label: const Text('Transfer this asset'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => context.push('/transfers/new', extra: asset),
            ),
          ),
        ],
      ),
    );
  }
}

/// Whether the scanned sticker's SHA-256 signature checked out (same wording as the web).
class _QrCheckBanner extends StatelessWidget {
  final String status;
  const _QrCheckBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final light = context.isLight;
    final (Color fg, Color bg, IconData icon, String title, String text) = switch (status) {
      'VERIFIED' => (
          light ? const Color(0xFF047857) : const Color(0xFF6EE7B7),
          light ? const Color(0xFFECFDF5) : const Color(0x3310B981),
          Icons.verified_rounded,
          'Genuine sticker',
          'The QR signature matches this asset.',
        ),
      'UNSIGNED' => (
          light ? const Color(0xFFB45309) : const Color(0xFFFCD34D),
          light ? const Color(0xFFFFFBEB) : const Color(0x33F59E0B),
          Icons.info_rounded,
          'Old sticker',
          'This sticker was printed before QR signing. Print a new one to replace it.',
        ),
      'INVALID' || 'NOT_FOUND' => (
          light ? const Color(0xFFB91C1C) : const Color(0xFFFCA5A5),
          light ? const Color(0xFFFEF2F2) : const Color(0x33EF4444),
          Icons.gpp_bad_rounded,
          'Sticker failed verification',
          'It may be fake, altered, or replaced by a newer sticker. Report it to the GSO.',
        ),
      _ => (
          context.colors.textSecondary,
          light ? const Color(0xFFF8FAFC) : const Color(0x22FFFFFF),
          Icons.help_outline_rounded,
          'Could not check the sticker',
          'The signature check did not respond. Try scanning again.',
        ),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(text, style: TextStyle(color: fg, fontSize: 14, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
