// lib/widgets/mini_map_widget.dart
// Contextual Bubble Universe - Mini Map Widget
// Bản đồ mini hiển thị khoảng cách thời gian thực khi ở Location Mode

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Widget bản đồ thu nhỏ hiển thị trong bubble khi Location Mode
class MiniMapWidget extends StatefulWidget {
  final double? myLat;
  final double? myLng;
  final double? peerLat;
  final double? peerLng;
  final String peerName;
  final String peerAvatar;
  final VoidCallback? onOpenFullMap;

  const MiniMapWidget({
    super.key,
    this.myLat,
    this.myLng,
    this.peerLat,
    this.peerLng,
    required this.peerName,
    required this.peerAvatar,
    this.onOpenFullMap,
  });

  @override
  State<MiniMapWidget> createState() => _MiniMapWidgetState();
}

class _MiniMapWidgetState extends State<MiniMapWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseAnim;
  late AnimationController _pingAnim;

  @override
  void initState() {
    super.initState();
    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pingAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseAnim.dispose();
    _pingAnim.dispose();
    super.dispose();
  }

  double? get _distance {
    if (widget.myLat == null ||
        widget.myLng == null ||
        widget.peerLat == null ||
        widget.peerLng == null) return null;

    // Haversine formula
    const R = 6371.0;
    final dLat = _toRad(widget.peerLat! - widget.myLat!);
    final dLon = _toRad(widget.peerLng! - widget.myLng!);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(widget.myLat!)) *
            math.cos(_toRad(widget.peerLat!)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.asin(math.sqrt(a));
    return R * c;
  }

  double _toRad(double deg) => deg * math.pi / 180;

  String get _distanceLabel {
    final d = _distance;
    if (d == null) return 'Đang xác định...';
    if (d < 0.1) return '${(d * 1000).round()} m';
    if (d < 1) return '${(d * 1000).round()} m';
    return '${d.toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2E7D32).withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            // Map background (styled grid)
            _buildMapBackground(),
            // Distance info
            _buildDistanceInfo(),
            // Open map button
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap:
                    widget.onOpenFullMap ?? () => HapticFeedback.lightImpact(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.open_in_new_rounded,
                          color: Colors.white, size: 12),
                      SizedBox(width: 4),
                      Text(
                        'Mở Maps',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapBackground() {
    return CustomPaint(
      painter: _MapGridPainter(),
      child: Container(),
    );
  }

  Widget _buildDistanceInfo() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.6),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            // My location ping
            AnimatedBuilder(
              animation: _pingAnim,
              builder: (_, __) {
                return _LocationPing(
                  color: const Color(0xFF2196F3),
                  label: 'Bạn',
                  pingProgress: _pingAnim.value,
                );
              },
            ),
            const SizedBox(width: 12),
            // Distance
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, __) {
                      return Text(
                        _distanceLabel,
                        style: TextStyle(
                          color: Colors.white
                              .withOpacity(0.8 + _pulseAnim.value * 0.2),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      );
                    },
                  ),
                  const Text(
                    'khoảng cách',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 10,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            // Peer location ping
            AnimatedBuilder(
              animation: _pingAnim,
              builder: (_, __) {
                return _LocationPing(
                  color: const Color(0xFF4CAF50),
                  label: widget.peerName.split(' ').first,
                  pingProgress: (_pingAnim.value + 0.3) % 1.0,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── LOCATION PING ────────────────────────────────────────────────────────────

class _LocationPing extends StatelessWidget {
  final Color color;
  final String label;
  final double pingProgress;

  const _LocationPing({
    required this.color,
    required this.label,
    required this.pingProgress,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // Ping ring
            Opacity(
              opacity: (1 - pingProgress).clamp(0, 1),
              child: Container(
                width: 32 + pingProgress * 16,
                height: 32 + pingProgress * 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color.withOpacity(0.5),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            // Pin
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.4),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.person_pin_rounded,
                color: Colors.white,
                size: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ─── MAP GRID PAINTER ─────────────────────────────────────────────────────────

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF2E7D32);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Roads (horizontal)
    final roadPaint = Paint()
      ..color = Colors.white.withOpacity(0.12)
      ..strokeWidth = 2;
    for (double y = 0; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), roadPaint);
    }
    // Roads (vertical)
    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), roadPaint);
    }

    // Main road
    final mainRoadPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..strokeWidth = 4;
    canvas.drawLine(
      Offset(size.width * 0.2, 0),
      Offset(size.width * 0.2, size.height),
      mainRoadPaint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.45),
      Offset(size.width, size.height * 0.45),
      mainRoadPaint,
    );

    // Block fills
    final blockPaint = Paint()..color = Colors.white.withOpacity(0.05);
    final blocks = [
      Rect.fromLTWH(50, 10, 60, 50),
      Rect.fromLTWH(130, 70, 80, 40),
      Rect.fromLTWH(230, 10, 60, 80),
    ];
    for (final b in blocks) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(b, const Radius.circular(3)),
        blockPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
