import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/theme/app_theme.dart';
import '../model/asset_model.dart';

/// The QR payload format shared with the web app's QR generator and this
/// app's QR Asset Lookup scanner (`asset:{id}:{propertyNumber}`) — keep all
/// three in sync if this ever changes.
String qrPayloadFor(AssetModel asset) => 'asset:${asset.id}:${asset.propertyNumber}';

/// Same seal the web sticker puts in the middle of the code (web public/logo-qr.png).
const _kSealAsset = 'assets/images/logo_qr.png';

/// The seal covers 24% of the QR's width (~6% of its area). With error-correction
/// level H (≈30% recoverable) the code still scans — the same ratio as the web sticker.
const _kSealRatio = 0.24;

Future<void> showAssetQrSheet(BuildContext context, AssetModel asset) {
  return showModalBottomSheet(
    useRootNavigator: true, // above the bottom bar, not behind it
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _AssetQrSheet(asset: asset),
  );
}

class _AssetQrSheet extends StatefulWidget {
  final AssetModel asset;
  const _AssetQrSheet({required this.asset});

  @override
  State<_AssetQrSheet> createState() => _AssetQrSheetState();
}

class _AssetQrSheetState extends State<_AssetQrSheet> {
  bool _printing = false;

  // Matches the web's printQrSticker: one 30 × 30 mm sticker — the QR (22.5 mm) with the
  // municipal seal in the middle and the property number under it. The page size is the
  // sticker itself, so a label printer puts one tag per label.
  Future<void> _print() async {
    setState(() => _printing = true);
    try {
      final asset = widget.asset;
      final seal = pw.MemoryImage((await rootBundle.load(_kSealAsset)).buffer.asUint8List());
      const qrSize = 22.5 * PdfPageFormat.mm;
      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(30 * PdfPageFormat.mm, 30 * PdfPageFormat.mm, marginAll: 1.5 * PdfPageFormat.mm),
          build: (context) => pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.SizedBox(
                width: qrSize,
                height: qrSize,
                child: pw.Stack(
                  alignment: pw.Alignment.center,
                  children: [
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(errorCorrectLevel: pw.BarcodeQRCorrectionLevel.high),
                      data: qrPayloadFor(asset),
                      width: qrSize,
                      height: qrSize,
                      drawText: false,
                    ),
                    pw.Container(
                      width: qrSize * _kSealRatio,
                      height: qrSize * _kSealRatio,
                      padding: const pw.EdgeInsets.all(0.35 * PdfPageFormat.mm),
                      decoration: const pw.BoxDecoration(color: PdfColors.white, shape: pw.BoxShape.circle),
                      child: pw.Image(seal),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 0.6 * PdfPageFormat.mm),
              pw.Text(asset.propertyNumber,
                  maxLines: 1, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, letterSpacing: 0.15)),
            ],
          ),
        ),
      );
      await Printing.layoutPdf(
        name: 'QR Sticker – ${asset.propertyNumber}',
        onLayout: (format) async => doc.save(),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    final c = context.colors;
    const qrSize = 220.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Asset QR Code', style: TextStyle(color: c.heading, fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(asset.propertyNumber,
              style: TextStyle(color: c.textTertiary, fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
          const SizedBox(height: 18),
          // same look as the web modal: white tile, QR with the seal in the middle
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            child: SizedBox(
              width: qrSize,
              height: qrSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  QrImageView(
                    data: qrPayloadFor(asset),
                    size: qrSize,
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.H,
                  ),
                  Container(
                    width: qrSize * _kSealRatio,
                    height: qrSize * _kSealRatio,
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: Image.asset(_kSealAsset),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(asset.description,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Scan with the Scan button to check this asset\'s status.',
              textAlign: TextAlign.center, style: TextStyle(color: c.textTertiary, fontSize: 14)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _printing ? null : _print,
                  icon: _printing
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.print_rounded),
                  label: Text(_printing ? 'Preparing…' : 'Print Label'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Prints one 30 × 30 mm sticker, the same as the web app.',
              textAlign: TextAlign.center, style: TextStyle(color: c.textTertiary, fontSize: 13)),
        ],
      ),
    );
  }
}
