// lib/bubble/widgets/mini_map_widget.dart
// ignore_for_file: use_super_parameters

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC WIDGET
// ─────────────────────────────────────────────────────────────────────────────

/// Compact location card that shows distance between two users.
///
/// Renders a stylised map grid background with animated ping rings for
/// both users. If coordinates are null the distance shows "Đang xác định…".
class MiniMapWidget extends StatefulWidget {
  final double? myLat;
  final double? myLng;
  final double? peerLat;
  final double? peerLng;
  final String peerName;
  final String peerAvatar;

  /// Called when the user taps the "Mở Maps" button.
  final VoidCallback? onOpenFullMap;

  /// Called when the user taps the "Chỉ đường" button.
  final VoidCallback? onGetDirections;

  const MiniMapWidget({
    super.key,
    this.myLat,
    this.myLng,
    this.peerLat,
    this.peerLng,
    required this.peerName,
    required this.peerAvatar,
    this.onOpenFullMap,
    this.onGetDirections,
  });

  @override
  State<MiniMapWidget> createState() => _MiniMapWidgetState();
}

class _MiniMapWidgetState extends State<MiniMapWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseAnim;
  late AnimationController _pingAnim;
  late AnimationController _entryAnim;

  @override
  void initState() {
    super.initState();
    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pingAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _entryAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
  }

  @override
  void dispose() {
    _pulseAnim.dispose();
    _pingAnim.dispose();
    _entryAnim.dispose();
    super.dispose();
  }

  // ── Distance ──────────────────────────────────────────────────────────────

  double? get _distanceKm {
    if (widget.myLat == null ||
        widget.myLng == null ||
        widget.peerLat == null ||
        widget.peerLng == null) return null;
    return _haversine(
        widget.myLat!, widget.myLng!, widget.peerLat!, widget.peerLng!);
  }

  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.pow(math.sin(dLon / 2), 2);
    return r * 2 * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
  }

  static double _rad(double d) => d * math.pi / 180;

  String get _distanceLabel {
    final d = _distanceKm;
    if (d == null) return 'Đang xác định...';
    if (d < 0.05) return 'Rất gần bạn!';
    if (d < 1) return '${(d * 1000).round()} m';
    if (d < 10) return '${d.toStringAsFixed(1)} km';
    return '${d.round()} km';
  }

  String get _proximityHint {
    final d = _distanceKm;
    if (d == null) return '';
    if (d < 0.05) return '• Cùng địa điểm';
    if (d < 0.5) return '• Đi bộ vài phút';
    if (d < 2) return '• Cách khoảng ${(d * 1000 / 80).round()} phút đi bộ';
    if (d < 20) return '• Cách khoảng ${(d / 40 * 60).round()} phút xe';
    return '• Khoảng cách xa';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _entryAnim, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
            .animate(CurvedAnimation(
                parent: _entryAnim, curve: Curves.easeOutCubic)),
        child: Container(
          height: 172,
          margin: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2E7D32).withOpacity(0.35),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // Map background
                const Positioned.fill(child: _MapBackground()),

                // Gradient overlay for bottom panel
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: 90,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.75),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                // Bottom info panel
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildInfoPanel(),
                ),

                // Action buttons (top-right)
                Positioned(
                  top: 8,
                  right: 8,
                  child: _buildActionButtons(),
                ),

                // Mode badge (top-left)
                Positioned(
                  top: 8,
                  left: 8,
                  child: _MapBadge(label: '📍 Live Location'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        children: [
          // My ping
          AnimatedBuilder(
            animation: _pingAnim,
            builder: (_, __) => _PingDot(
              label: 'Bạn',
              color: const Color(0xFF2196F3),
              pingProgress: _pingAnim.value,
            ),
          ),

          // Distance label
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (_, __) => Text(
                    _distanceLabel,
                    style: TextStyle(
                      color: Color.lerp(Colors.white, const Color(0xFF69F0AE),
                          _pulseAnim.value * 0.3),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      shadows: const [
                        Shadow(blurRadius: 8, color: Colors.black54)
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (_proximityHint.isNotEmpty)
                  Text(
                    _proximityHint,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                    ),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),

          // Peer ping
          AnimatedBuilder(
            animation: _pingAnim,
            builder: (_, __) => _PingDot(
              label: widget.peerName.split(' ').first,
              color: const Color(0xFF66BB6A),
              pingProgress: (_pingAnim.value + 0.35) % 1.0,
              avatarUrl: widget.peerAvatar,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.onGetDirections != null) ...[
          _MapActionBtn(
            icon: Icons.directions_rounded,
            label: 'Đường đi',
            onTap: widget.onGetDirections!,
          ),
          const SizedBox(width: 5),
        ],
        _MapActionBtn(
          icon: Icons.open_in_new_rounded,
          label: 'Mở Maps',
          onTap: widget.onOpenFullMap ?? () => HapticFeedback.lightImpact(),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PING DOT
// ─────────────────────────────────────────────────────────────────────────────

class _PingDot extends StatelessWidget {
  final Color color;
  final String label;
  final double pingProgress;
  final String? avatarUrl;

  const _PingDot({
    required this.color,
    required this.label,
    required this.pingProgress,
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final ringSize = 28.0 + pingProgress * 18.0;
    final ringOpacity = (1 - pingProgress).clamp(0.0, 0.6);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 46,
          height: 46,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Expanding ring
              Container(
                width: ringSize,
                height: ringSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color.withOpacity(ringOpacity),
                    width: 1.5,
                  ),
                ),
              ),
              // Core dot / avatar
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  image: (avatarUrl != null && avatarUrl!.isNotEmpty)
                      ? DecorationImage(
                          image: NetworkImage(avatarUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.5),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: (avatarUrl == null || avatarUrl!.isEmpty)
                    ? const Icon(Icons.person_pin_rounded,
                        color: Colors.white, size: 15)
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAP ACTION BUTTON
// ─────────────────────────────────────────────────────────────────────────────

class _MapActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MapActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withOpacity(0.25),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 12),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAP BADGE
// ─────────────────────────────────────────────────────────────────────────────

class _MapBadge extends StatelessWidget {
  final String label;
  const _MapBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAP BACKGROUND (CustomPainter)
// ─────────────────────────────────────────────────────────────────────────────

class _MapBackground extends StatelessWidget {
  const _MapBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MapGridPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Dark map background with subtle gradient
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF1B4332), Color(0xFF2D6A4F)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Minor grid (dots)
    final dotPaint = Paint()..color = Colors.white.withOpacity(0.06);
    for (double y = 20; y < size.height; y += 20) {
      for (double x = 20; x < size.width; x += 20) {
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }

    // Secondary roads
    final roadPaint = Paint()
      ..color = Colors.white.withOpacity(0.09)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    // Horizontal roads
    for (final y in [size.height * 0.35, size.height * 0.65]) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), roadPaint);
    }
    // Vertical roads
    for (final x in [size.width * 0.28, size.width * 0.62]) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), roadPaint);
    }

    // Main roads
    final mainRoad = Paint()
      ..color = Colors.white.withOpacity(0.18)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, size.height * 0.5),
        Offset(size.width, size.height * 0.5), mainRoad);
    canvas.drawLine(Offset(size.width * 0.45, 0),
        Offset(size.width * 0.45, size.height), mainRoad);

    // Building blocks
    final blockPaint = Paint()..color = Colors.white.withOpacity(0.07);
    final blocks = [
      Rect.fromLTWH(size.width * 0.05, size.height * 0.06, size.width * 0.18,
          size.height * 0.22),
      Rect.fromLTWH(size.width * 0.50, size.height * 0.06, size.width * 0.14,
          size.height * 0.18),
      Rect.fromLTWH(size.width * 0.68, size.height * 0.06, size.width * 0.25,
          size.height * 0.25),
      Rect.fromLTWH(size.width * 0.05, size.height * 0.55, size.width * 0.20,
          size.height * 0.28),
      Rect.fromLTWH(size.width * 0.50, size.height * 0.58, size.width * 0.16,
          size.height * 0.24),
      Rect.fromLTWH(size.width * 0.70, size.height * 0.55, size.width * 0.22,
          size.height * 0.20),
    ];
    for (final b in blocks) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(b, const Radius.circular(3)), blockPaint);
    }

    // Park / green area
    final parkPaint = Paint()
      ..color = const Color(0xFF52B788).withOpacity(0.15);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.28, size.height * 0.06, size.width * 0.18,
            size.height * 0.20),
        const Radius.circular(4),
      ),
      parkPaint,
    );

    // Water body
    final waterPaint = Paint()
      ..color = const Color(0xFF4FC3F7).withOpacity(0.12);
    final waterPath = Path()
      ..moveTo(0, size.height * 0.42)
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.38,
        size.width * 0.45,
        size.height * 0.42,
      )
      ..lineTo(size.width * 0.45, size.height * 0.50)
      ..lineTo(0, size.height * 0.50)
      ..close();
    canvas.drawPath(waterPath, waterPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
