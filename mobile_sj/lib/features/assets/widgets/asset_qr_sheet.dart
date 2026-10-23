import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/theme/app_theme.dart';
import '../model/asset_model.dart';
import '../data/asset_service.dart';
import '../../../core/api/api_exception.dart';

/// The signed sticker text from the server (`asset:{id}:{propertyNumber}:{tag}`, see the
/// backend's AssetQrService) - the same text the web prints, so stickers from either match.
/// Falls back to the old unsigned form only when talking to a server older than QR signing.
String qrPayloadFor(AssetModel asset) => asset.qrPayload ?? 'asset:${asset.id}:${asset.propertyNumber}';

/// Same seal the web sticker puts in the middle of the code (web public/logo-qr.png).
const _kSealAsset = 'assets/images/logo_qr.png';

/// The seal covers 24% of the QR's width (~6% of its area). With error-correction
/// level H (≈30% recoverable) the code still scans - the same ratio as the web sticker.
const _kSealRatio = 0.24;

/// One 30 × 30 mm sticker's content, as the web prints it: the QR (22.5 mm, level H) with the
/// municipal seal in the middle and the property number under it. Used for the single print
/// and for bulk export.
pw.Widget _stickerPdf(String qrPayload, String propertyNumber, pw.ImageProvider seal) {
  const qrSize = 22.5 * PdfPageFormat.mm;
  return pw.Column(
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
              data: qrPayload,
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
      pw.Text(propertyNumber,
          maxLines: 1, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, letterSpacing: 0.15)),
    ],
  );
}

const _kSticker = PdfPageFormat(30 * PdfPageFormat.mm, 30 * PdfPageFormat.mm, marginAll: 1.5 * PdfPageFormat.mm);

/// Bulk QR export, matching the web's print view. [a4]: six stickers across on A4 with dashed
/// cut lines (sticker paper or plain paper). Otherwise one 30 × 30 mm sticker per page, for a
/// label printer. Opens the phone's print screen, which can also save or share the PDF.
Future<void> printQrStickers(List<QrSticker> stickers, {required bool a4}) async {
  final bytes = await qrStickersPdf(stickers, a4: a4);
  await Printing.layoutPdf(name: 'QR codes (${stickers.length})', onLayout: (_) async => bytes);
}

/// The bulk sticker PDF itself (see printQrStickers).
Future<Uint8List> qrStickersPdf(List<QrSticker> stickers, {required bool a4}) async {
  final seal = pw.MemoryImage((await rootBundle.load(_kSealAsset)).buffer.asUint8List());
  final doc = pw.Document();
  if (a4) {
    const cell = 30 * PdfPageFormat.mm;
    const gap = 2 * PdfPageFormat.mm;
    pw.Widget label(QrSticker s) => pw.Container(
          width: cell,
          height: cell,
          padding: const pw.EdgeInsets.all(1.5 * PdfPageFormat.mm),
          decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.5, style: pw.BorderStyle.dashed)),
          child: _stickerPdf(s.qrPayload, s.propertyNumber, seal),
        );
    final rows = <pw.Widget>[];
    for (var i = 0; i < stickers.length; i += 6) {
      final row = stickers.sublist(i, i + 6 > stickers.length ? stickers.length : i + 6);
      rows.add(pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: gap),
        child: pw.Row(children: [
          for (var j = 0; j < row.length; j++) ...[if (j > 0) pw.SizedBox(width: gap), label(row[j])],
        ]),
      ));
    }
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.copyWith(
          marginLeft: 10 * PdfPageFormat.mm,
          marginRight: 10 * PdfPageFormat.mm,
          marginTop: 10 * PdfPageFormat.mm,
          marginBottom: 10 * PdfPageFormat.mm),
      build: (_) => rows,
    ));
  } else {
    for (final s in stickers) {
      doc.addPage(pw.Page(pageFormat: _kSticker, build: (_) => _stickerPdf(s.qrPayload, s.propertyNumber, seal)));
    }
  }
  return doc.save();
}

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

  // Matches the web's printQrSticker: one 30 × 30 mm sticker - the QR (22.5 mm) with the
  // municipal seal in the middle and the property number under it. The page size is the
  // sticker itself, so a label printer puts one tag per label.
  Future<void> _print() async {
    setState(() => _printing = true);
    try {
      final asset = widget.asset;
      final seal = pw.MemoryImage((await rootBundle.load(_kSealAsset)).buffer.asUint8List());
      final doc = pw.Document();
      doc.addPage(
          pw.Page(pageFormat: _kSticker, build: (_) => _stickerPdf(qrPayloadFor(asset), asset.propertyNumber, seal)));
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
              style:
                  TextStyle(color: c.textTertiary, fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
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

/// Bulk QR export, step two: pick the paper, then print / save / share. Returns true once
/// the print screen was shown, so the list can leave choosing mode.
Future<bool> showQrExportSheet(BuildContext context, List<int> ids) async {
  final done = await showModalBottomSheet<bool>(
    useRootNavigator: true,
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _QrExportSheet(ids: ids),
  );
  return done ?? false;
}

class _QrExportSheet extends StatefulWidget {
  final List<int> ids;
  const _QrExportSheet({required this.ids});

  @override
  State<_QrExportSheet> createState() => _QrExportSheetState();
}

class _QrExportSheetState extends State<_QrExportSheet> {
  bool _a4 = true;
  bool _working = false;
  String? _error;

  Future<void> _export() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final stickers = await AssetService().qrStickers(widget.ids);
      if (stickers.isEmpty) {
        setState(() => _error = 'None of the chosen assets can be printed.');
        return;
      }
      await printQrStickers(stickers, a4: _a4);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not prepare the QR codes.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = widget.ids.length;
    Widget option(bool a4, String title, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: _a4 == a4 ? AppTheme.brand.withValues(alpha: 0.08) : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: _a4 == a4 ? AppTheme.brand : c.border),
            ),
            child: RadioListTile<bool>(
              value: a4,
              enabled: !_working,
              activeColor: AppTheme.brand,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Text(title, style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
              subtitle: Text(text, style: TextStyle(color: c.textTertiary, fontSize: 14)),
            ),
          ),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Export QR codes',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.heading, fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('$n asset${n == 1 ? '' : 's'} chosen',
              textAlign: TextAlign.center, style: TextStyle(color: c.textTertiary, fontSize: 15)),
          const SizedBox(height: 18),
          RadioGroup<bool>(
            groupValue: _a4,
            onChanged: (v) {
              if (!_working && v != null) setState(() => _a4 = v);
            },
            child: Column(children: [
              option(true, 'A4 sheet', 'Six stickers across, with cut lines. For sticker paper or plain paper.'),
              option(false, 'Label printer', 'One 30 × 30 mm sticker per label.'),
            ]),
          ),
          Text('The print screen can also save the PDF or share it.',
              style: TextStyle(color: c.textTertiary, fontSize: 13)),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 14)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _working ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _working ? null : _export,
                  icon: _working
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.print_rounded),
                  label: Text(_working ? 'Preparing…' : 'Print / Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
