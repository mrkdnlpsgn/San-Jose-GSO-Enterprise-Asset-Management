import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/theme/app_theme.dart';
import '../../assets/model/asset_model.dart';
import '../../reports/utils/formatters.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/main_shell.dart';
import '../provider/qr_lookup_provider.dart';

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
  MobileScannerController? _controller;
  bool _scanning = false;
  bool _notFound = false;
  AssetModel? _result;
  final _manualCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (_cameraScanSupported) {
      _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  void _lookup(String rawCode) {
    final assetsAsync = ref.read(qrLookupAssetsProvider);
    final assets = assetsAsync.value;
    if (assets == null) return;

    final match = findAssetForCode(assets, rawCode);
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
    });
  }

  // The MobileScanner widget starts/stops the controller itself on
  // mount/unmount (MobileScannerController.autoStart defaults to true) —
  // calling controller.start() here too, before setState's rebuild has
  // actually mounted the widget, raced the platform channel and crashed
  // the native analyzer with a null reference on every frame.
  void _startScanning() {
    setState(() {
      _scanning = true;
      _result = null;
      _notFound = false;
    });
  }

  void _stopScanning() {
    setState(() => _scanning = false);
  }

  void _clear() {
    setState(() {
      _result = null;
      _notFound = false;
      _manualCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Keep the asset list warm so lookups after a scan/manual entry are instant.
    ref.watch(qrLookupAssetsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR Code')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + context.mainShellBottomInset),
        children: [
          // The answer goes first once there is one, so it isn't hidden below the camera
          if (_result != null) ...[
            _ResultCard(asset: _result!, onClear: _clear),
            const SizedBox(height: 16),
          ] else if (_notFound) ...[
            _NotFoundCard(onClear: _clear),
            const SizedBox(height: 16),
          ],
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
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 280,
              child: _scanning
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        MobileScanner(
                          controller: _controller,
                          errorBuilder: (context, error) => Container(
                            color: Colors.black,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'The camera could not start (${error.errorCode.name}). '
                              'Allow camera access for this app in your phone\'s Settings, then try again.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                            ),
                          ),
                          onDetect: (capture) {
                            final code = capture.barcodes.firstOrNull?.rawValue;
                            if (code == null) return;
                            _stopScanning();
                            _lookup(code);
                          },
                        ),
                        // square guide, like the web scanner's
                        Center(
                          child: Container(
                            width: 190,
                            height: 190,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white, width: 3),
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: c.subtle,
                        border: Border.all(color: c.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.qr_code_scanner_rounded, size: 64, color: c.textTertiary),
                          const SizedBox(height: 8),
                          Text('Camera is off', style: TextStyle(color: c.textTertiary, fontSize: 15)),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          _scanning
              ? OutlinedButton.icon(
                  onPressed: _stopScanning,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Stop camera'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                )
              : ElevatedButton.icon(
                  onPressed: _startScanning,
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 22),
                  label: const Text('Start scanning'),
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
  final VoidCallback onClear;
  const _ResultCard({required this.asset, required this.onClear});

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

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
