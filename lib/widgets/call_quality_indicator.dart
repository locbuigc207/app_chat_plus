import 'package:flutter/material.dart';

import '../services/agora_rtc_manager.dart';

// ══════════════════════════════════════════════════════
// CALL QUALITY INDICATOR
// Shows animated signal bars with quality stats tooltip
// ══════════════════════════════════════════════════════
class CallQualityIndicator extends StatelessWidget {
  final RtcCallStats stats;

  const CallQualityIndicator({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final level = _level();
    final color = _color(level);
    final label = _label(level);

    return Tooltip(
      message: 'Kết nối: $label\n'
          'RTT: ${stats.rtt} ms\n'
          'Gửi: ${stats.txBitrate} kbps\n'
          'Nhận: ${stats.rxBitrate} kbps\n'
          'Mất gói: ${stats.txPacketLoss}%',
      preferBelow: false,
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      textStyle:
          const TextStyle(color: Colors.white70, fontSize: 12, height: 1.6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.36),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AnimatedSignalBars(level: level, color: color),
            if (level < 3) ...[
              const SizedBox(width: 6),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
                child: Text(label),
              ),
            ],
          ],
        ),
      ),
    );
  }

  int _level() {
    // No stats yet → show full bars
    if (stats.rtt == 0 && stats.txBitrate == 0) return 4;
    if (stats.rtt < 80 && stats.txPacketLoss < 2) return 4;
    if (stats.rtt < 160 && stats.txPacketLoss < 5) return 3;
    if (stats.rtt < 300 && stats.txPacketLoss < 12) return 2;
    return 1;
  }

  Color _color(int level) {
    switch (level) {
      case 4:
        return const Color(0xFF34C759);
      case 3:
        return const Color(0xFFAED581);
      case 2:
        return const Color(0xFFFF9F0A);
      default:
        return const Color(0xFFFF3B30);
    }
  }

  String _label(int level) {
    switch (level) {
      case 4:
        return 'Tốt';
      case 3:
        return 'Khá';
      case 2:
        return 'Yếu';
      default:
        return 'Kém';
    }
  }
}

// ── Animated signal bars ──────────────────────────────
class _AnimatedSignalBars extends StatefulWidget {
  final int level;
  final Color color;

  const _AnimatedSignalBars({required this.level, required this.color});

  @override
  State<_AnimatedSignalBars> createState() => _AnimatedSignalBarsState();
}

class _AnimatedSignalBarsState extends State<_AnimatedSignalBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const barCount = 4;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(barCount, (i) {
        final filled = i < widget.level;
        final barH = 5.0 + i * 3.5;
        final isWeak = !filled && widget.level <= 1;

        return AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            // Pulse weak bars
            final opacity = (filled || !isWeak) ? 1.0 : 0.3 + _ctrl.value * 0.3;

            return Opacity(
              opacity: opacity,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
                width: 4,
                height: barH,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: filled
                      ? widget.color
                      : Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

// ══════════════════════════════════════════════════════
// NETWORK QUALITY BADGE  (standalone, larger version)
// ══════════════════════════════════════════════════════
class NetworkQualityBadge extends StatelessWidget {
  final NetworkQuality quality;

  const NetworkQualityBadge({super.key, required this.quality});

  @override
  Widget build(BuildContext context) {
    final (color, label, icon) = _info();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  (Color, String, IconData) _info() {
    switch (quality) {
      case NetworkQuality.excellent:
        return (
          const Color(0xFF34C759),
          'Xuất sắc',
          Icons.network_wifi_rounded
        );
      case NetworkQuality.good:
        return (
          const Color(0xFF34C759),
          'Tốt',
          Icons.network_wifi_3_bar_rounded
        );
      case NetworkQuality.poor:
        return (
          const Color(0xFFFF9F0A),
          'Yếu',
          Icons.network_wifi_2_bar_rounded
        );
      case NetworkQuality.bad:
      case NetworkQuality.veryBad:
        return (
          const Color(0xFFFF3B30),
          'Kém',
          Icons.network_wifi_1_bar_rounded
        );
      case NetworkQuality.down:
        return (const Color(0xFFFF3B30), 'Mất mạng', Icons.wifi_off_rounded);
      default:
        return (Colors.white38, 'Đang đo', Icons.network_check_rounded);
    }
  }
}

// ══════════════════════════════════════════════════════
// CALL STATS OVERLAY  (debug / detailed stats panel)
// ══════════════════════════════════════════════════════
class CallStatsOverlay extends StatelessWidget {
  final RtcCallStats stats;

  const CallStatsOverlay({super.key, required this.stats});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatRow(label: 'RTT', value: '${stats.rtt} ms'),
            _StatRow(label: 'Gửi', value: '${stats.txBitrate} kbps'),
            _StatRow(label: 'Nhận', value: '${stats.rxBitrate} kbps'),
            _StatRow(label: 'Mất gói', value: '${stats.txPacketLoss}%'),
            _StatRow(label: 'Thời gian', value: '${stats.duration}s'),
          ],
        ),
      );
}

class _StatRow extends StatelessWidget {
  final String label, value;

  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$label: ',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ]),
      );
}
