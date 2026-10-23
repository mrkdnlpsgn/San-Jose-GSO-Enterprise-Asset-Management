import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:san_jose_eam_mobile/features/assets/widgets/asset_qr_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final stickers = [
    for (var i = 1; i <= 50; i++)
      (propertyNumber: 'COA-2026-${i.toString().padLeft(3, '0')}', qrPayload: 'asset:$i:COA-2026-$i:0123456789abcdef'),
  ];

  // "/Type /Page" also matches "/Type /Pages", so count the exact object type
  int pages(List<int> pdf) => RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(pdf)).length;

  test('A4 sheet: six across, eight rows a page, so 50 stickers take two pages', () async {
    final pdf = await qrStickersPdf(stickers, a4: true);
    final out = Platform.environment['QR_PDF_OUT'];
    if (out != null) File(out).writeAsBytesSync(pdf);
    expect(pages(pdf), 2);
  });

  test('label printer: one sticker per page', () async {
    final pdf = await qrStickersPdf(stickers.take(5).toList(), a4: false);
    expect(pages(pdf), 5);
  });
}
