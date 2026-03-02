import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key});

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  final MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _isScanned = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isScanned) return;
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final barcode = barcodes.first;
      if (barcode.rawValue != null) {
        setState(() => _isScanned = true);
        controller.stop();
        Navigator.pop(context, barcode.rawValue);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code',
            style: TextStyle(color: ColorConstants.primaryColor)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_off, color: Colors.grey),
            onPressed: () => controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ✅ FIX: errorBuilder must match signature exactly
          MobileScanner(
            controller: controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, size: 60, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text('Scanner Error',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      error.errorDetails?.message ?? 'Unknown error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Go Back'),
                    ),
                  ],
                ),
              );
            },
          ),
          CustomPaint(painter: ScannerOverlay(), child: Container()),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: ColorConstants.primaryColor.withValues(alpha: 0.9),
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code_scanner, color: Colors.white, size: 48),
                  SizedBox(height: 12),
                  Text(
                    'Position the QR code within the frame',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'The scanner will automatically detect the code',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          if (_isScanned)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text('Processing...',
                          style: TextStyle(color: Colors.white, fontSize: 16)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ScannerOverlay extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double scanAreaSize = size.width * 0.75;
    final double left = (size.width - scanAreaSize) / 2;
    final double top = (size.height - scanAreaSize) / 2;
    final Rect scanArea = Rect.fromLTWH(left, top, scanAreaSize, scanAreaSize);

    final backgroundPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5);

    canvas.drawPath(
      Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
        ..addRRect(RRect.fromRectAndRadius(scanArea, const Radius.circular(16)))
        ..fillType = PathFillType.evenOdd,
      backgroundPaint,
    );

    final cornerPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLength = 30.0;
    const cornerRadius = 16.0;

    canvas.drawPath(
      Path()
        ..moveTo(left + cornerRadius, top)
        ..lineTo(left + cornerLength, top)
        ..moveTo(left, top + cornerRadius)
        ..lineTo(left, top + cornerLength),
      cornerPaint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(left + scanAreaSize - cornerLength, top)
        ..lineTo(left + scanAreaSize - cornerRadius, top)
        ..moveTo(left + scanAreaSize, top + cornerRadius)
        ..lineTo(left + scanAreaSize, top + cornerLength),
      cornerPaint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(left, top + scanAreaSize - cornerLength)
        ..lineTo(left, top + scanAreaSize - cornerRadius)
        ..moveTo(left + cornerRadius, top + scanAreaSize)
        ..lineTo(left + cornerLength, top + scanAreaSize),
      cornerPaint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(left + scanAreaSize, top + scanAreaSize - cornerLength)
        ..lineTo(left + scanAreaSize, top + scanAreaSize - cornerRadius)
        ..moveTo(left + scanAreaSize - cornerLength, top + scanAreaSize)
        ..lineTo(left + scanAreaSize - cornerRadius, top + scanAreaSize),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
