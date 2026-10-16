import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:mobile_scanner/mobile_scanner.dart';

/// Opens the full-screen camera (over the bottom bar too) and returns the first QR code it
/// reads, or null if cancelled. Mirrors the web's QrScannerOverlay: dark surround, white
/// corner guide, short instructions on top and a big Cancel button at the bottom.
Future<String?> showQrScanner(BuildContext context) => Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _QrScannerOverlay()),
    );

class _QrScannerOverlay extends StatefulWidget {
  const _QrScannerOverlay();

  @override
  State<_QrScannerOverlay> createState() => _QrScannerOverlayState();
}

class _QrScannerOverlayState extends State<_QrScannerOverlay> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final barcodes = capture.barcodes;
    final code = barcodes.isEmpty ? null : barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;
    _done = true; // the camera keeps firing while the page closes
    Navigator.of(context).pop(code);
  }

  static String _errorText(MobileScannerException error) => switch (error.errorCode) {
        MobileScannerErrorCode.permissionDenied =>
          'Camera access is blocked. Allow camera access for this app in your phone\'s Settings, then try again.',
        MobileScannerErrorCode.unsupported => 'No camera was found on this device. Type the Property Number instead.',
        _ => 'Couldn\'t open the camera. Close other apps using it and try again.',
      };

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // 72% of the shorter side, capped like the web's max 420px
    final square = (size.shortestSide * 0.72).clamp(180.0, 420.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: ValueListenableBuilder<MobileScannerState>(
          valueListenable: _controller,
          builder: (context, state, _) {
            final error = state.error;
            final ready = state.isRunning;
            return Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  fit: BoxFit.cover,
                  onDetect: _onDetect,
                  errorBuilder: (_, __) => const ColoredBox(color: Colors.black),
                ),
                if (error == null)
                  IgnorePointer(child: CustomPaint(painter: _GuidePainter(square))),
                if (error != null)
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      constraints: const BoxConstraints(maxWidth: 380),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        _errorText(error),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 16, height: 1.4),
                      ),
                    ),
                  ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    child: Column(
                      children: [
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            error != null
                                ? 'Camera unavailable'
                                : ready
                                    ? 'Place the QR code inside the square'
                                    : 'Starting camera…',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w700, height: 1.3),
                          ),
                        ),
                        if (error == null && ready) ...[
                          const SizedBox(height: 6),
                          Text(
                            'It will read on its own. Hold the phone steady.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 16),
                          ),
                        ],
                        const Spacer(),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF0F172A),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Darkens everything outside the centred square and draws white corner brackets on it.
class _GuidePainter extends CustomPainter {
  final double square;
  _GuidePainter(this.square);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(center: size.center(Offset.zero), width: square, height: square);
    final hole = RRect.fromRectAndRadius(rect, const Radius.circular(6));

    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(hole)),
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );

    const len = 48.0;
    const r = 6.0;
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.square;
    final l = rect.left, t = rect.top, rt = rect.right, b = rect.bottom;
    canvas.drawPath(
      Path()
        // top-left
        ..moveTo(l, t + len)
        ..lineTo(l, t + r)
        ..arcToPoint(Offset(l + r, t), radius: const Radius.circular(r))
        ..lineTo(l + len, t)
        // top-right
        ..moveTo(rt - len, t)
        ..lineTo(rt - r, t)
        ..arcToPoint(Offset(rt, t + r), radius: const Radius.circular(r))
        ..lineTo(rt, t + len)
        // bottom-right
        ..moveTo(rt, b - len)
        ..lineTo(rt, b - r)
        ..arcToPoint(Offset(rt - r, b), radius: const Radius.circular(r))
        ..lineTo(rt - len, b)
        // bottom-left
        ..moveTo(l + len, b)
        ..lineTo(l + r, b)
        ..arcToPoint(Offset(l, b - r), radius: const Radius.circular(r))
        ..lineTo(l, b - len),
      p,
    );
  }

  @override
  bool shouldRepaint(_GuidePainter old) => old.square != square;
}
