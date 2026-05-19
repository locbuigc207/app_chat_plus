import 'package:flutter/material.dart';

import '../services/realtime_ai_service.dart';

class AICallShield extends StatelessWidget {
  const AICallShield({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SecurityStatus>(
        stream: RealtimeAIService().securityStream,
        initialData: SecurityStatus.safe,
        builder: (context, snapshot) {
          final status = snapshot.data!;

          Color shieldColor = Colors.green;
          IconData shieldIcon = Icons.security;
          String statusText = "AI Đang bảo vệ";

          if (status == SecurityStatus.scanning) {
            shieldColor = Colors.blueAccent;
            shieldIcon = Icons.radar;
            statusText = "AI Đang quét...";
          } else if (status == SecurityStatus.warning) {
            shieldColor = Colors.orange;
            shieldIcon = Icons.warning_amber_rounded;
            statusText = "Phát hiện nhạy cảm";
          } else if (status == SecurityStatus.danger) {
            shieldColor = Colors.red;
            shieldIcon = Icons.gpp_bad;
            statusText = "NGUY HIỂM!";
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Banner chữ đỏ nếu nguy hiểm
              if (status == SecurityStatus.danger ||
                  status == SecurityStatus.warning)
                StreamBuilder<String>(
                    stream: RealtimeAIService().warningMsgStream,
                    builder: (context, msgSnapshot) {
                      if (!msgSnapshot.hasData || msgSnapshot.data!.isEmpty)
                        return const SizedBox.shrink();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: shieldColor.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          msgSnapshot.data!,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                        ),
                      );
                    }),

              // Icon Khiên
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: shieldColor, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(shieldIcon, color: shieldColor, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      statusText,
                      style: TextStyle(
                          color: shieldColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          );
        });
  }
}
