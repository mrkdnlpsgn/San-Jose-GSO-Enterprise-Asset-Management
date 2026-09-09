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
      appBar: AppBar(title: const Text('QR Asset Lookup')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + context.mainShellBottomInset),
        children: [
          if (_cameraScanSupported) _buildCameraPanel(),
          if (_cameraScanSupported) const SizedBox(height: 16),
          _buildManualEntryPanel(),
          const SizedBox(height: 16),
          if (_result != null) _ResultCard(asset: _result!, onClear: _clear)
          else if (_notFound) _NotFoundCard(onClear: _clear)
          else if (!_cameraScanSupported)
            const _InfoCard(
              text: 'Camera scanning isn\'t available on this platform — '
                  'enter a Property Number above to look up an asset\'s status.',
            ),
        ],
      ),
    );
  }

  Widget _buildCameraPanel() {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text('Camera Scanner',
                style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 280,
              width: double.infinity,
              child: _scanning
                  ? MobileScanner(
                      controller: _controller,
                      errorBuilder: (context, error) => Container(
                        color: Colors.black,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Camera error: ${error.errorCode.name}. '
                          'Grant camera permission in system settings and try again.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                        ),
                      ),
                      onDetect: (capture) {
                        final code = capture.barcodes.firstOrNull?.rawValue;
                        if (code == null) return;
                        _stopScanning();
                        _lookup(code);
                      },
                    )
                  : Container(
                      color: context.colors.bg,
                      alignment: Alignment.center,
                      child: Icon(Icons.qr_code_scanner_rounded, size: 56, color: context.colors.textTertiary),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: _scanning
                  ? OutlinedButton(onPressed: _stopScanning, child: const Text('Stop'))
                  : ElevatedButton.icon(
                      onPressed: _startScanning,
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                      label: const Text('Start Scanner'),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualEntryPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Manual Code Entry',
                style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 4),
            Text('Enter a Property Number to search directly.',
                style: TextStyle(color: context.colors.textTertiary, fontSize: 12.5)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualCtrl,
                    decoration: const InputDecoration(hintText: 'e.g. COA-2026-001'),
                    onSubmitted: _lookup,
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () => _lookup(_manualCtrl.text),
                  child: const Text('Search'),
                ),
              ],
            ),
          ],
        ),
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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: context.colors.textSecondary, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: TextStyle(color: context.colors.textTertiary, fontSize: 13))),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppTheme.statusDisposed, size: 36),
            const SizedBox(height: 10),
            const Text('Asset Not Found',
                style: TextStyle(color: AppTheme.statusDisposed, fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 4),
            Text('No asset matches this code. Verify the property number and try again.',
                textAlign: TextAlign.center, style: TextStyle(color: context.colors.textTertiary, fontSize: 12.5)),
            const SizedBox(height: 14),
            OutlinedButton(onPressed: onClear, child: const Text('Clear')),
          ],
        ),
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
    final fields = <String, String?>{
      'Property Number': asset.propertyNumber,
      'Description': asset.description,
      'Category': asset.category.categoryName,
      'Office': asset.office.officeName,
      'Location': asset.location,
      'Accountable': asset.accountablePerson,
      'Unit Value': fmtMoney(asset.unitValue),
      'Quantity': asset.quantity.toString(),
      'Acquisition Date': fmtDate(asset.acquisitionDate),
      if (asset.remarks != null && asset.remarks!.isNotEmpty) 'Remarks': asset.remarks,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(color: AppTheme.brand, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Asset Found',
                      style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                ),
                TextButton(
                  onPressed: () => context.push('/assets/${asset.id}'),
                  child: const Text('View'),
                ),
                TextButton(onPressed: onClear, child: const Text('Clear')),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusBadge.condition(asset.condition),
                StatusBadge.lifecycle(asset.lifecycleStatus),
              ],
            ),
            const SizedBox(height: 16),
            ...fields.entries.where((e) => e.value != null && e.value!.isNotEmpty).map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.key.toUpperCase(),
                        style: TextStyle(
                            color: context.colors.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                    const SizedBox(height: 2),
                    Text(e.value!, style: TextStyle(color: context.colors.textSecondary, fontSize: 13.5)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
