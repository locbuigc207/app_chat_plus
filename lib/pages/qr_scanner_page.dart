import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key});

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _isScanned = false;
  bool _torchOn = false;
  bool _isFrontCamera = false;

  
  late AnimationController _scanLineCtrl;
  late Animation<double> _scanLineAnim;

  @override
  void initState() {
    super.initState();
    _scanLineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _scanLineAnim = CurvedAnimation(
      parent: _scanLineCtrl,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scanLineCtrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isScanned) return;
    final barcodes = capture.barcodes;
    if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
      setState(() => _isScanned = true);
      HapticFeedback.mediumImpact();
      _controller.stop();
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) Navigator.pop(context, barcodes.first.rawValue);
      });
    }
  }

  void _toggleTorch() {
    _controller.toggleTorch();
    setState(() => _torchOn = !_torchOn);
  }

  void _switchCamera() {
    _controller.switchCamera();
    setState(() => _isFrontCamera = !_isFrontCamera);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final scanAreaSize = size.width * 0.72;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Quét mã QR',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              color: _torchOn ? Colors.amber : Colors.white,
              size: 24,
            ),
            onPressed: _toggleTorch,
            tooltip: 'Đèn pin',
          ),
          IconButton(
            icon: Icon(
              _isFrontCamera ? Icons.camera_front_rounded : Icons.camera_rear_rounded,
              color: Colors.white,
              size: 24,
            ),
            onPressed: _switchCamera,
            tooltip: 'Đổi camera',
          ),
        ],
      ),
      body: Stack(
        children: [
          
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _buildError(error),
          ),

          
          AnimatedBuilder(
            animation: _scanLineAnim,
            builder: (context, child) {
              return CustomPaint(
                painter: _ScannerOverlayPainter(
                  scanAreaSize: scanAreaSize,
                  scanLineProgress: _scanLineAnim.value,
                  isScanned: _isScanned,
                ),
                child: Container(),
              );
            },
          ),

          
          Positioned(
            top: kToolbarHeight + MediaQuery.of(context).padding.top + 16,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _isScanned ? 0 : 1,
              duration: const Duration(milliseconds: 300),
              child: const Text(
                'Đặt mã QR vào trong khung để quét',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),

          
          if (_isScanned)
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: _isScanned ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  color: Colors.black45,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.green.shade400,
                          ),
                          child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Quét thành công!',
                          style: TextStyle(
                              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: AnimatedOpacity(
                opacity: _isScanned ? 0 : 1,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 0.8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: ColorConstants.primaryColor.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.qr_code_scanner_rounded,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tự động nhận diện',
                              style: TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Hướng camera vào mã QR để quét ngay lập tức',
                              style: TextStyle(color: Colors.white60, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(MobileScannerException error) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt_outlined, size: 40, color: Colors.red),
              ),
              const SizedBox(height: 20),
              const Text('Không thể truy cập camera',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Text(
                error.errorDetails?.message ?? 'Lỗi không xác định',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 28),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                label: const Text('Quay lại', style: TextStyle(color: Colors.white)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white30),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final double scanAreaSize;
  final double scanLineProgress;
  final bool isScanned;

  _ScannerOverlayPainter({
    required this.scanAreaSize,
    required this.scanLineProgress,
    required this.isScanned,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final left = cx - scanAreaSize / 2;
    final top = cy - scanAreaSize / 2;
    final scanRect = Rect.fromLTWH(left, top, scanAreaSize, scanAreaSize);
    const r = Radius.circular(20);

    
    canvas.drawPath(
      Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
        ..addRRect(RRect.fromRectAndRadius(scanRect, r))
        ..fillType = PathFillType.evenOdd,
      Paint()..color = Colors.black.withValues(alpha: 0.65),
    );

    
    final cornerPaint = Paint()
      ..color = isScanned ? Colors.green : Colors.white
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cl = 32.0;
    const cr = 20.0;

    void drawCorner(double x, double y, double sx, double sy) {
      canvas.drawPath(
        Path()
          ..moveTo(x + sx * cr, y)
          ..lineTo(x + sx * cl, y)
          ..moveTo(x, y + sy * cr)
          ..lineTo(x, y + sy * cl),
        cornerPaint,
      );
    }

    drawCorner(left, top, 1, 1);
    drawCorner(left + scanAreaSize, top, -1, 1);
    drawCorner(left, top + scanAreaSize, 1, -1);
    drawCorner(left + scanAreaSize, top + scanAreaSize, -1, -1);

    
    if (!isScanned) {
      final lineY = top + scanAreaSize * scanLineProgress;
      final linePaint = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            ColorConstants.primaryColor.withValues(alpha: 0.8),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(left, lineY, scanAreaSize, 2));
      canvas.drawRect(
        Rect.fromLTWH(left + 8, lineY, scanAreaSize - 16, 2),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ScannerOverlayPainter old) =>
      old.scanLineProgress != scanLineProgress || old.isScanned != isScanned;
}
