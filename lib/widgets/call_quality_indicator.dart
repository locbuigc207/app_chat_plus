import 'package:flutter/material.dart';

import '../services/agora_rtc_manager.dart';

// ─────────────────────────────────────────────────────────────
// CallQualityIndicator
//
// Renders animated signal bars with a tooltip showing RTT,
// bitrate and packet-loss stats.
// ─────────────────────────────────────────────────────────────

class CallQualityIndicator extends StatelessWidget {
  final RtcCallStats stats;

  const CallQualityIndicator({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final level = _qualityLevel();
    final color = _qualityColor(level);
    final label = _qualityLabel(level);

    return Tooltip(
      message: 'Chất lượng: $label\n'
          'RTT: ${stats.rtt} ms\n'
          'Gửi: ${stats.txBitrate} kbps\n'
          'Nhận: ${stats.rxBitrate} kbps\n'
          'Mất gói: ${stats.txPacketLoss}%',
      preferBelow: false,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F36),
        borderRadius: BorderRadius.circular(10),
      ),
      textStyle: const TextStyle(color: Colors.white70, fontSize: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black38,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SignalBars(level: level, color: color),
            if (level < 3) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  int _qualityLevel() {
    // No stats yet → assume perfect
    if (stats.rtt == 0 && stats.txBitrate == 0) return 4;
    if (stats.rtt < 80 && stats.txPacketLoss < 2) return 4;
    if (stats.rtt < 160 && stats.txPacketLoss < 5) return 3;
    if (stats.rtt < 300 && stats.txPacketLoss < 12) return 2;
    return 1;
  }

  Color _qualityColor(int level) {
    switch (level) {
      case 4:
        return const Color(0xFF66BB6A);
      case 3:
        return const Color(0xFFAED581);
      case 2:
        return const Color(0xFFFFB74D);
      default:
        return const Color(0xFFEF5350);
    }
  }

  String _qualityLabel(int level) {
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

// ─────────────────────────────────────────────────────────────
// Signal bars
// ─────────────────────────────────────────────────────────────

class _SignalBars extends StatelessWidget {
  final int level; // 1–4
  final Color color;

  const _SignalBars({required this.level, required this.color});

  @override
  Widget build(BuildContext context) {
    const barCount = 4;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(barCount, (i) {
        final filled = i < level;
        final barHeight = 5.0 + (i * 3.5);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          width: 4,
          height: barHeight,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: filled ? color : Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
