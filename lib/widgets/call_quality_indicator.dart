import 'package:flutter/material.dart';

import '../services/agora_rtc_manager.dart';

class CallQualityIndicator extends StatelessWidget {
  final RtcCallStats stats;

  const CallQualityIndicator({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final quality = _qualityLevel();
    final color = _qualityColor(quality);

    return Tooltip(
      message: 'RTT: ${stats.rtt}ms  '
          'TX: ${stats.txBitrate}kbps  '
          'RX: ${stats.rxBitrate}kbps',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(4, (i) {
          final barHeight = 6.0 + (i * 4.0);
          return Container(
            width: 5,
            height: barHeight,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: i < quality ? color : Colors.white.withOpacity(0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }

  int _qualityLevel() {
    if (stats.rtt == 0 && stats.txBitrate == 0) return 4; // unknown = show full
    if (stats.rtt < 100 && stats.txPacketLoss < 3) return 4;
    if (stats.rtt < 200 && stats.txPacketLoss < 8) return 3;
    if (stats.rtt < 400 && stats.txPacketLoss < 15) return 2;
    return 1;
  }

  Color _qualityColor(int level) {
    switch (level) {
      case 4:
        return Colors.greenAccent;
      case 3:
        return Colors.lightGreenAccent;
      case 2:
        return Colors.orangeAccent;
      default:
        return Colors.redAccent;
    }
  }
}
